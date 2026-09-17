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
                      w = c(0.5, 1.5, 2, 1, 0.25, 3, 1, 1, 2.5, 0.75, 1, 2)),
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
  class3    = fixture(c(1, 2, 3, 4, 2, 2, 5, 9, 7, 3, 6),
                      g = c("A", "A", "A", "A", "B", "B", "B", "C", "C", "C",
                            NA))
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
