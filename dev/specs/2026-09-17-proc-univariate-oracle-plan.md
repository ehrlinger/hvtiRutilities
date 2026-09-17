# `proc_univariate()` SAS Oracle Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SAS oracle kit that the `proc_univariate()` port will be tested against: deterministic synthetic fixtures, a scenario manifest, a SAS program that records `PROC UNIVARIATE OUTPUT OUT=` for every scenario, and a checker for the returned output. Then open PR A.

**Architecture:** Everything lives in `dev/oracle/proc_univariate/`, which `.Rbuildignore` (`^dev$`) keeps out of the package. `make_fixtures.R` is the single source of fixtures and of `scenarios.csv`. `oracle.sas` reads `scenarios.csv` and generates one `%uni` call per row with `CALL EXECUTE`, so SAS runs cannot drift from the manifest. `check_oracle.R` reads the same manifest to validate `out/`.

**Tech Stack:** base R (`utils`, `stats`), SAS 9.4 (`PROC UNIVARIATE`, macro language, `CALL EXECUTE`).

**Spec:** `dev/specs/2026-09-17-proc-univariate-design.md` (sections "SAS oracle" and "Delivery").

**Verified:** `make_fixtures.R` and `check_oracle.R` were prototyped on 2026-09-17: fixture generation is byte-identical across runs; the checker exits 1 on a missing file, a missing column and a wrong row count, exits 0 on complete output, and treats `optional` scenarios as notes; neither file has lints. `oracle.sas` **cannot be run in this environment**; it is verified by the maintainer's SAS run, and `check_oracle.R` is the gate on its output.

## Global Constraints

- All new files are under `dev/oracle/proc_univariate/`. Nothing under `R/`, `tests/`, `man/`, `vignettes/` changes. The PR ships nothing, so no `NEWS.md` entry and no version bump.
- Fixtures are synthetic and deterministic: no random numbers, no study data, no PHI.
- Generated files (`fixtures/*.csv`, `scenarios.csv`) are committed and never hand-edited; change `make_fixtures.R` and regenerate.
- R and SAS lines at most 80 characters.
- Scripts run from the package root.
- Commit messages end with the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Branch `spec/proc-univariate` (already created; the design spec is committed there).

## File Map

| file | action | responsibility |
|---|---|---|
| `dev/oracle/proc_univariate/make_fixtures.R` | create | writes fixtures and the scenario manifest |
| `dev/oracle/proc_univariate/fixtures/*.csv` | generate | 14 synthetic inputs, columns `id,g,x,w` |
| `dev/oracle/proc_univariate/scenarios.csv` | generate | 21 SAS runs |
| `dev/oracle/proc_univariate/check_oracle.R` | create | validates `out/` against the manifest |
| `dev/oracle/proc_univariate/oracle.sas` | create | the SAS runs |
| `dev/oracle/proc_univariate/README.md` | create | how to run the kit |
| `dev/specs/README.md` | modify | index row for this plan |

---

### Task 1: Fixtures and scenario manifest

**Files:**
- Create: `dev/oracle/proc_univariate/make_fixtures.R`
- Generate: `dev/oracle/proc_univariate/fixtures/*.csv`, `dev/oracle/proc_univariate/scenarios.csv`

**Interfaces:**
- Produces: fixture CSVs with header `"id","g","x","w"` (blank `g`/`w` when unused, `NA` written as empty); `scenarios.csv` with columns `scenario,fixture,weight,vardef,mu0,class,ttest,ranktests,optional` in that order. Tasks 2 and 3 read both.

- [ ] **Step 1: Write the script**

Create `dev/oracle/proc_univariate/make_fixtures.R`:

```r
## Writes the synthetic fixtures and the scenario manifest for the
## proc_univariate() SAS oracle. Deterministic: no random numbers, so the
## fixtures are identical on every run and every machine.
##
## Run from the package root:
##   Rscript dev/oracle/proc_univariate/make_fixtures.R

kit <- file.path("dev", "oracle", "proc_univariate")
fix_dir <- file.path(kit, "fixtures")
dir.create(fix_dir, recursive = TRUE, showWarnings = FALSE)

## Every fixture has the same four columns so oracle.sas reads them all with
## one INPUT statement. `g` and `w` are blank when a scenario does not use them.
fixture <- function(x, w = NA_real_, g = NA_character_) {
  data.frame(id = seq_along(x), g = g, x = round(x, 6), w = w,
             stringsAsFactors = FALSE)
}

skewed <- function(n) {
  z <- stats::qnorm(stats::ppoints(n))
  z + 0.25 * z^2
}

basic_x <- c(-3.5, -1, 0, 0, 1.25, 2, 2, 2, 4.75, 6, 9.5, 15)

fixtures <- list(
  basic     = fixture(basic_x),
  basic_w2  = fixture(basic_x, w = 2),
  wt_frac   = fixture(basic_x,
                      w = c(0.5, 1.5, 2, 3, 0.25, 1, 1, 1, 2.5, 0.75, 1, 2)),
  wt_exact  = fixture(1:8, w = c(1, 1, 3, 1, 1, 1, 1, 1)),
  n20       = fixture(c(-4, -2, -2, -1, 0.5, 1, 1, 2, 2, 2,
                        3, 3.5, 4, 4, 5, 6, 7, 7, 8, 10)),
  n21       = fixture(c(-4, -2, -2, -1, 0.5, 1, 1, 2, 2, 2,
                        3, 3.5, 4, 4, 5, 6, 7, 7, 8, 10, 12)),
  n3        = fixture(c(1, 2, 4)),
  n4        = fixture(c(1, 2, 4, 8)),
  const     = fixture(rep(5, 6)),
  allmiss   = fixture(rep(NA_real_, 5)),
  skewed50  = fixture(skewed(50)),
  n2000     = fixture(skewed(2000)),
  n2001     = fixture(skewed(2001)),
  class3    = fixture(c(1, 2, 3, 4, 2, 2, 5, 8, 9, 7, 3, 4, 6),
                      g = c("A", "A", "A", "A", "B", "B", "B", "B",
                            "C", "C", "C", "C", NA))
)

for (nm in names(fixtures)) {
  utils::write.csv(fixtures[[nm]], file.path(fix_dir, paste0(nm, ".csv")),
                   row.names = FALSE, na = "")
}

## One row per SAS run.
## - `ttest`: request T and PROBT. Off under VARDEF other than DF, which SAS
##   requires for the t test.
## - `ranktests`: request MSIGN, PROBM, SIGNRANK, PROBS and the NORMAL option
##   with NORMAL and PROBN. Off under WEIGHT: SAS computes only the t test.
## - `optional`: runs that deliberately request what the design expects SAS
##   to refuse. A missing output file for them is itself an oracle result.
scenarios <- data.frame(
  scenario = c("basic", "basic_mu0", "n20", "n21", "n3", "n4", "const",
               "allmiss", "skewed50", "n2000", "n2001", "class3",
               "wt_exact", "wt_equal", "wt_frac",
               "vardef_n", "vardef_n_w", "vardef_wdf_w", "vardef_weight_w",
               "wt_frac_alltests", "vardef_n_alltests"),
  fixture  = c("basic", "basic", "n20", "n21", "n3", "n4", "const",
               "allmiss", "skewed50", "n2000", "n2001", "class3",
               "wt_exact", "basic_w2", "wt_frac",
               "basic", "wt_frac", "wt_frac", "wt_frac",
               "wt_frac", "basic"),
  weight    = c(rep(0L, 12), 1L, 1L, 1L, 0L, 1L, 1L, 1L, 1L, 0L),
  vardef    = c(rep("DF", 15), "N", "N", "WDF", "WEIGHT", "DF", "N"),
  mu0       = c(0, 2, rep(0, 19)),
  class     = c(rep(0L, 11), 1L, rep(0L, 9)),
  ttest     = c(rep(1L, 15), 0L, 0L, 0L, 0L, 1L, 1L),
  ranktests = c(rep(1L, 12), 0L, 0L, 0L, 1L, 0L, 0L, 0L, 1L, 1L),
  optional  = c(rep(0L, 19), 1L, 1L),
  stringsAsFactors = FALSE
)
utils::write.csv(scenarios, file.path(kit, "scenarios.csv"),
                 row.names = FALSE)

message("Wrote ", length(fixtures), " fixtures and ", nrow(scenarios),
        " scenarios to ", kit)
```

Fixture intent (for reviewers): `basic` has ties and two values equal to 0 (default `mu0`); `basic_mu0` reuses it with `mu0 = 2` so three values equal `mu0`; `n20`/`n21` sit either side of the exact signed-rank limit and include tied absolute differences; `wt_exact` has cumulative weights `1,2,5,6,7,8,9,10`, so `pW` is hit exactly at p = 0.1, 0.5 and 0.9 and missed at 0.25; `basic_w2` gives equal weights; `n3`/`n4` are the minimum n for skewness and kurtosis; `n2000`/`n2001` bracket the Shapiro-Wilk limit; `class3` has three levels of four observations each (enough for kurtosis) plus a missing class value; `wt_frac` weights the two zeros (total 5) above the three 2s (total 3), so a weighted `mode` (0) differs from the unweighted one (2).

- [ ] **Step 2: Run it**

Run: `Rscript dev/oracle/proc_univariate/make_fixtures.R`
Expected: `Wrote 14 fixtures and 21 scenarios to dev/oracle/proc_univariate`

- [ ] **Step 3: Verify determinism and content**

Run:

```bash
md5 -q dev/oracle/proc_univariate/fixtures/n2001.csv > /tmp/pu-md5-1 && Rscript dev/oracle/proc_univariate/make_fixtures.R >/dev/null 2>&1 && md5 -q dev/oracle/proc_univariate/fixtures/n2001.csv | diff - /tmp/pu-md5-1 && echo deterministic
head -3 dev/oracle/proc_univariate/fixtures/class3.csv
head -2 dev/oracle/proc_univariate/scenarios.csv
```

Expected: `deterministic`; `class3.csv` begins `"id","g","x","w"` then `1,"A",1,`; `scenarios.csv` header is `"scenario","fixture","weight","vardef","mu0","class","ttest","ranktests","optional"` and the first row is `"basic","basic",0,"DF",0,0,1,1,0`.

Run: `Rscript -e 'print(lintr::lint("dev/oracle/proc_univariate/make_fixtures.R"))'`
Expected: `No lints found.`

- [ ] **Step 4: Commit**

```bash
git add dev/oracle/proc_univariate/make_fixtures.R dev/oracle/proc_univariate/fixtures dev/oracle/proc_univariate/scenarios.csv
git commit -m "feat(oracle): synthetic fixtures and scenario manifest for proc_univariate()

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Output checker

**Files:**
- Create: `dev/oracle/proc_univariate/check_oracle.R`

**Interfaces:**
- Consumes: `scenarios.csv` from Task 1.
- Produces: exit status 0 when `out/` is complete, 1 otherwise; messages prefixed `ERROR`, `NOTE`, `OK`. Expected output column names (lower-cased): `g` (class scenarios), the 35 base columns below, `t`/`probt` when `ttest == 1`, the six rank/normality columns when `ranktests == 1`. Task 3's `oracle.sas` must emit exactly these names.

- [ ] **Step 1: Write the checker**

Create `dev/oracle/proc_univariate/check_oracle.R`:

```r
## Checks the SAS oracle output before it is committed as test fixtures:
## every required scenario produced a CSV, with the expected columns and row
## count. It does not compare values; that is the parity tests' job.
##
## Run from the package root after copying SAS's out/ directory into the kit:
##   Rscript dev/oracle/proc_univariate/check_oracle.R

kit <- file.path("dev", "oracle", "proc_univariate")
out_dir <- file.path(kit, "out")
scenarios <- utils::read.csv(file.path(kit, "scenarios.csv"),
                             stringsAsFactors = FALSE)

base_cols <- c("n", "nobs", "nmiss", "sum", "mean", "std", "var", "cv",
               "stdmean", "uss", "css", "skewness", "kurtosis", "sumwgt",
               "range", "qrange", "mode", "min", "max", "median", "q1", "q3",
               "p1", "p5", "p10", "p90", "p95", "p99",
               "pp_0", "pp_2_5", "pp_16", "pp_50", "pp_84", "pp_97_5",
               "pp_100")
t_cols <- c("t", "probt")
rank_cols <- c("msign", "probm", "signrank", "probs", "normal", "probn")

problems <- character()
notes <- character()
n_absent <- 0L

if (!file.exists(file.path(out_dir, "sas_version.txt"))) {
  problems <- c(problems, "out/sas_version.txt is missing")
}

for (i in seq_len(nrow(scenarios))) {
  sc <- scenarios[i, ]
  path <- file.path(out_dir, paste0(sc$scenario, ".csv"))
  if (!file.exists(path)) {
    msg <- paste0(sc$scenario, ": no output file")
    if (sc$optional == 1L) {
      notes <- c(notes, paste0(msg, " (optional: SAS refused the request)"))
      n_absent <- n_absent + 1L
    } else {
      problems <- c(problems, msg)
    }
    next
  }
  res <- utils::read.csv(path, stringsAsFactors = FALSE)
  names(res) <- tolower(names(res))
  expected <- c(if (sc$class == 1L) "g", base_cols,
                if (sc$ttest == 1L) t_cols,
                if (sc$ranktests == 1L) rank_cols)
  absent <- setdiff(expected, names(res))
  if (length(absent) > 0L) {
    problems <- c(problems, paste0(sc$scenario, ": missing column(s) ",
                                   paste(absent, collapse = ", ")))
  }
  want_rows <- if (sc$class == 1L) 3L else 1L
  if (nrow(res) != want_rows) {
    problems <- c(problems, paste0(sc$scenario, ": ", nrow(res),
                                   " row(s), expected ", want_rows))
  }
  all_na <- vapply(expected, function(col) {
    col %in% names(res) && all(is.na(res[[col]]))
  }, logical(1))
  if (any(all_na)) {
    cols <- expected[all_na]
    notes <- c(notes, paste0(sc$scenario, ": entirely missing column(s) ",
                             paste(cols, collapse = ", "),
                             " (check oracle.log)"))
  }
}

for (n in notes) message("NOTE  ", n)
if (length(problems) > 0L) {
  for (p in problems) message("ERROR ", p)
  quit(status = 1L)
}
message("OK    ", nrow(scenarios) - n_absent, " of ", nrow(scenarios),
        " scenario outputs present and well-formed")
```

- [ ] **Step 2: Verify it fails on an empty kit**

Run: `Rscript dev/oracle/proc_univariate/check_oracle.R; echo "exit=$?"`
Expected: `ERROR out/sas_version.txt is missing`, one `ERROR <scenario>: no output file` per required scenario, two `NOTE` lines for `wt_frac_alltests` and `vardef_n_alltests`, and `exit=1`.

- [ ] **Step 3: Verify it passes on well-formed output, using a throwaway fake**

Write this to `/tmp/pu-fake-out.R` (not committed) and run it from the package root: `Rscript /tmp/pu-fake-out.R`.

```r
kit <- "dev/oracle/proc_univariate"
dir.create(file.path(kit, "out"))
sc <- read.csv(file.path(kit, "scenarios.csv"))
base <- c("n", "nobs", "nmiss", "sum", "mean", "std", "var", "cv", "stdmean",
          "uss", "css", "skewness", "kurtosis", "sumwgt", "range", "qrange",
          "mode", "min", "max", "median", "q1", "q3", "p1", "p5", "p10",
          "p90", "p95", "p99", "pp_0", "pp_2_5", "pp_16", "pp_50", "pp_84",
          "pp_97_5", "pp_100")
writeLines("fake", file.path(kit, "out", "sas_version.txt"))
for (i in seq_len(nrow(sc))) {
  s <- sc[i, ]
  if (s$scenario == "wt_frac_alltests") next
  cols <- toupper(c(if (s$class == 1) "g", base,
                    if (s$ttest == 1) c("t", "probt"),
                    if (s$ranktests == 1) c("msign", "probm", "signrank",
                                            "probs", "normal", "probn")))
  nr <- if (s$class == 1) 3 else 1
  d <- as.data.frame(matrix(1.5, nr, length(cols),
                            dimnames = list(NULL, cols)))
  write.csv(d, file.path(kit, "out", paste0(s$scenario, ".csv")),
            row.names = FALSE)
}
```

Run: `Rscript dev/oracle/proc_univariate/check_oracle.R; echo "exit=$?"`
Expected: `NOTE  wt_frac_alltests: no output file (optional: SAS refused the request)`, `OK    20 of 21 scenario outputs present and well-formed`, `exit=0`.

- [ ] **Step 4: Verify each failure path, then remove the fake**

Run:

```bash
Rscript -e 'f <- "dev/oracle/proc_univariate/out/basic.csv"; d <- read.csv(f); d$PROBN <- NULL; write.csv(d, f, row.names = FALSE); f <- "dev/oracle/proc_univariate/out/class3.csv"; d <- read.csv(f); write.csv(d[1:2, ], f, row.names = FALSE)'
rm dev/oracle/proc_univariate/out/n21.csv
Rscript dev/oracle/proc_univariate/check_oracle.R; echo "exit=$?"
rm -rf dev/oracle/proc_univariate/out
```

Expected: `ERROR basic: missing column(s) probn`, `ERROR n21: no output file`, `ERROR class3: 2 row(s), expected 3`, `exit=1`. After `rm`, `git status --short dev/oracle` shows only `check_oracle.R` untracked.

Run: `Rscript -e 'print(lintr::lint("dev/oracle/proc_univariate/check_oracle.R"))'`
Expected: `No lints found.`

- [ ] **Step 5: Commit**

```bash
git add dev/oracle/proc_univariate/check_oracle.R
git commit -m "feat(oracle): checker for proc_univariate() SAS oracle output

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The SAS program and kit README

**Files:**
- Create: `dev/oracle/proc_univariate/oracle.sas`
- Create: `dev/oracle/proc_univariate/README.md`
- Modify: `dev/specs/README.md`
- Create: `.gitattributes`
- Modify: `.Rbuildignore`

**Interfaces:**
- Consumes: `scenarios.csv` column order from Task 1 (the `INPUT` statement reads them positionally); output column names required by Task 2.

- [ ] **Step 1: Write the SAS program**

Create `dev/oracle/proc_univariate/oracle.sas`:

```sas
/*--------------------------------------------------------------------------
  SAS oracle for hvtiRutilities::proc_univariate()

  Runs PROC UNIVARIATE with OUTPUT OUT= on every scenario in scenarios.csv
  and writes one CSV per scenario to out/, plus sas_version.txt and
  oracle.log. The fixtures are synthetic; nothing here reads study data.

  Design: dev/specs/2026-09-17-proc-univariate-design.md

  To run: set ROOT below to this kit's directory, then submit the whole file.
--------------------------------------------------------------------------*/

%let root = /path/to/hvtiRutilities/dev/oracle/proc_univariate;

options nodate nonumber missing=' ' dlcreatedir nosyntaxcheck;

/* Create out/ if it does not exist. */
libname _mkout "&root/out";
libname _mkout clear;

proc printto log="&root/out/oracle.log" new;
run;

data _null_;
  file "&root/out/sas_version.txt";
  put "&sysvlong";
  put "&sysscp &sysscpl";
run;

%macro uni(scenario=, fixture=, weight=0, vardef=DF, mu0=0, class=0,
           ttest=1, ranktests=1);
  %local _rc vars hdr;

  proc datasets lib=work nolist nowarn;
    delete fx o cols;
  quit;

  filename _old "&root/out/&scenario..csv";
  %if %sysfunc(fexist(_old)) %then %do;
    %let _rc = %sysfunc(fdelete(_old));
    %if &_rc ne 0 %then %put ERROR: could not delete stale &scenario..csv.;
  %end;
  filename _old clear;

  data work.fx;
    infile "&root/fixtures/&fixture..csv" dsd firstobs=2 truncover;
    input id g :$8. x w;
  run;

  proc univariate data=work.fx noprint mu0=&mu0 vardef=&vardef
    %if &ranktests = 1 %then normal;
    ;
    %if &class = 1 %then %do;
      class g;
    %end;
    var x;
    %if &weight = 1 %then %do;
      weight w;
    %end;
    output out=work.o
      n=n nobs=nobs nmiss=nmiss sum=sum mean=mean std=std var=var cv=cv
      stdmean=stdmean uss=uss css=css skewness=skewness kurtosis=kurtosis
      sumwgt=sumwgt range=range qrange=qrange mode=mode min=min max=max
      median=median q1=q1 q3=q3 p1=p1 p5=p5 p10=p10 p90=p90 p95=p95 p99=p99
      %if &ttest = 1 %then %do;
        t=t probt=probt
      %end;
      %if &ranktests = 1 %then %do;
        msign=msign probm=probm signrank=signrank probs=probs
        normal=normal probn=probn
      %end;
      pctlpts=0 2.5 16 50 84 97.5 100 pctlpre=pp_;
  run;

  %if &syserr > 4 or not %sysfunc(exist(work.o)) %then %do;
    %put WARNING: scenario &scenario produced no output (syserr=&syserr).;
    %goto done;
  %end;

  proc contents data=work.o out=work.cols(keep=name varnum) noprint;
  run;

  proc sql noprint;
    select name into :vars separated by ' '
      from work.cols order by varnum;
    select lowcase(name) into :hdr separated by ','
      from work.cols order by varnum;
  quit;

  data _null_;
    set work.o;
    file "&root/out/&scenario..csv" dsd lrecl=32767;
    format _numeric_ best32.;
    if _n_ = 1 then put "&hdr";
    put (&vars) (:);
  run;

  %done:
%mend uni;

/* One %uni call per row of scenarios.csv, so the SAS runs cannot drift from
   the manifest that make_fixtures.R writes and check_oracle.R reads. */
data _null_;
  infile "&root/scenarios.csv" dsd firstobs=2 truncover;
  length scenario fixture vardef $32;
  input scenario $ fixture $ weight vardef $ mu0 class ttest ranktests
        optional;
  call execute(cats('%nrstr(%uni)(scenario=', scenario,
                    ', fixture=', fixture, ', weight=', weight,
                    ', vardef=', vardef, ', mu0=', mu0,
                    ', class=', class, ', ttest=', ttest,
                    ', ranktests=', ranktests, ')'));
run;

proc printto;
run;
```

Notes for reviewers (SAS cannot run here, so these are the points to check by reading):
- `%if &ranktests = 1 %then normal;` emits `normal` without a semicolon; the following bare `;` ends the `PROC UNIVARIATE` statement.
- Every `OUTPUT` keyword is written `keyword=keyword`, and `PCTLPRE=pp_` with `PCTLPTS=0 2.5 16 50 84 97.5 100` gives `pp_0 pp_2_5 pp_16 pp_50 pp_84 pp_97_5 pp_100`, the names `check_oracle.R` expects.
- `proc datasets ... delete fx o cols` runs first in each call, so a failed scenario cannot write the previous scenario's `work.o`.
- `options missing=' '` with `DSD` writes missing numbers as empty fields; `format _numeric_ best32.` keeps full precision.
- `%nrstr(%uni)` inside `CALL EXECUTE` defers each macro call until the reading step finishes, the standard idiom.
- The `INPUT` order must match `scenarios.csv`: `scenario fixture weight vardef mu0 class ttest ranktests optional`.
- `nosyntaxcheck` on the `OPTIONS` statement: in batch SAS the first erroring
  step otherwise sets `OBS=0` for every later step, silently emptying every
  later scenario's output.
- The `filename _old` / `%sysfunc(fdelete(_old))` block deletes this
  scenario's previous CSV before the run, so a scenario that fails this time
  cannot leave behind a stale CSV from an earlier run that the checker would
  accept.

- [ ] **Step 2: Check lines and manifest agreement**

Run:

```bash
awk 'length > 80 {print FNR": "length}' dev/oracle/proc_univariate/oracle.sas
Rscript -e 'h <- names(read.csv("dev/oracle/proc_univariate/scenarios.csv")); sas <- paste(readLines("dev/oracle/proc_univariate/oracle.sas"), collapse = " "); inp <- regmatches(sas, regexpr("input scenario[^;]*;", sas)); w <- strsplit(gsub("[$;]|input", " ", inp), "[[:space:]]+")[[1]]; w <- w[nzchar(w)]; stopifnot(identical(w, h)); cat("input matches manifest", fill = TRUE)'
```

Expected: no `awk` output; `input matches manifest`.

- [ ] **Step 3: Write the kit README**

Create `dev/oracle/proc_univariate/README.md`:

```markdown
# SAS oracle for `proc_univariate()`

Real SAS output that `proc_univariate()` is tested against. Design:
`dev/specs/2026-09-17-proc-univariate-design.md`. Everything here is under
`dev/`, so none of it ships in the package.

| file | role |
|---|---|
| `make_fixtures.R` | writes `fixtures/*.csv` and `scenarios.csv`. Deterministic: no random numbers |
| `fixtures/` | small synthetic inputs, each aimed at one behaviour. No study data |
| `scenarios.csv` | one row per SAS run: fixture, `WEIGHT`, `VARDEF=`, `MU0=`, `CLASS`, which tests to request |
| `oracle.sas` | runs `PROC UNIVARIATE ... OUTPUT OUT=` for every scenario and writes `out/` |
| `check_oracle.R` | checks `out/` is complete and well formed before it is committed |

## Running it

1. If `scenarios.csv` or a fixture needs to change, edit `make_fixtures.R`
   and run it from the package root:
   `Rscript dev/oracle/proc_univariate/make_fixtures.R`.
   Commit the regenerated files; never edit them by hand.
2. In SAS, set `%let root =` at the top of `oracle.sas` to this directory and
   submit the whole file. It writes `out/<scenario>.csv`,
   `out/sas_version.txt` and `out/oracle.log`.
3. Copy `out/` back into this directory if SAS ran elsewhere, then from the
   package root run:
   `Rscript dev/oracle/proc_univariate/check_oracle.R`.
   It exits 0 when every required scenario is present with the expected
   columns and rows. A `NOTE` for an `optional` scenario means SAS refused a
   request the design expects it to refuse; read `out/oracle.log` to confirm
   why. Also search `out/oracle.log` for `ERROR` and `Invalid data`; an
   `Invalid data` line means a fixture was read wrongly (for example with
   Windows line endings), and the run must be repeated.
4. Commit `out/` on the branch. The implementation work moves the outputs
   and fixtures under `tests/testthat/fixtures/proc_univariate/`.

## Scenarios that are expected to fail

`wt_frac_alltests` requests the sign, signed-rank and normality tests under
`WEIGHT`, and `vardef_n_alltests` requests the t test under `VARDEF=N`. The
design assumes SAS does not compute these and returns `NA` for them. Whether
SAS writes missing values, or refuses and writes no file, is the result being
recorded.
```

- [ ] **Step 4: Index the plan**

In `dev/specs/README.md`, insert directly below the row that begins `| 2026-09-17 | [Porting SAS \`PROC UNIVARIATE\``:

```
| 2026-09-17 | [`proc_univariate()` SAS oracle kit plan](2026-09-17-proc-univariate-oracle-plan.md) | plan for PR A of the design above |
```

- [ ] **Step 5: Commit**

```bash
git add dev/oracle/proc_univariate/oracle.sas dev/oracle/proc_univariate/README.md dev/specs/README.md
git commit -m "feat(oracle): SAS program and README for the proc_univariate() oracle kit

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Verify the package is untouched and open PR A

**Files:** none.

- [ ] **Step 1: Nothing ships**

Run: `git diff --name-only main...HEAD`
Expected: only paths under `dev/`.

Run: `Rscript -e 'cat(devtools::build(path = tempdir(), quiet = TRUE))' | xargs tar -tzf | grep -c "dev/oracle" || true`
Expected: `0`.

- [ ] **Step 2: Push and open the PR**

```bash
git push -u origin spec/proc-univariate
gh pr create --base main --title "docs: proc_univariate() design spec and SAS oracle kit" --body "$(cat <<'EOF'
Design spec for `proc_univariate()` (a port of SAS `PROC UNIVARIATE`'s `OUTPUT OUT=` statistics) and the SAS oracle kit it will be tested against. Ships nothing: every change is under `dev/`, so there is no NEWS entry.

- Spec: `dev/specs/2026-09-17-proc-univariate-design.md`
- Oracle plan: `dev/specs/2026-09-17-proc-univariate-oracle-plan.md`
- Kit: `dev/oracle/proc_univariate/` (fixtures, `scenarios.csv`, `oracle.sas`, `check_oracle.R`, README)

**Next:** the maintainer runs `oracle.sas`, `check_oracle.R` gates the output, and the output is committed. Any contradiction with the spec's definitions table is corrected before the implementation plan (PR B) is written.

`oracle.sas` could not be run where it was written; the SAS run is its test.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: a PR URL.
