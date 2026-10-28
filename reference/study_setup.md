# Set up study identity and directories

The usual entry point is `hvtiR::setup()`. Creates the numbered
directory structure for a new study and writes an identity-only
`_study.yml`. With `adopt = TRUE`, an existing study keeps its legacy or
numbered directory layout and every existing initialization file.

Data are deliberately not required. Call
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md)
after the default or a named dataset exists.

When the root holds no `.Rproj` file, one named for the root directory
is written, so that opening the project and
[`study_root`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md)
agree on the study root. An existing project is left unchanged.

With `cleanup = TRUE`, the template copies a legacy study carries are
deleted before anything else reads the study, anywhere in it: every file
whose name starts with `tp.`, every `binder.summaries.doc`, and every
other file whose name and exact content match a file in the template
corpus at `template_dir`. A study's own file that shares a name with a
corpus file but differs from it (an edited `references.bib`, say) is
kept, as are `.renvignore` and `.gitignore`. These files are copied in
when a study is created, months before any analysis, and the corpus they
came from is kept centrally, so no backup is made. A folder the
deletions leave holding nothing (desktop litter such as `Thumbs.db`
aside) is removed, whatever its name, as is an empty `templates` or
`old_RF_templates*` folder; a folder still holding other files stays, as
does one holding any folder the cleanup did not empty, and a top-level
study folder is never removed. Symbolic links are neither followed nor
deleted, and folders named `.git`, `.checkpoint` or `renv` are never
entered, at any depth. The root and `template_dir` must not overlap. A
file that cannot be deleted stops the setup with an error.

With `renv = TRUE`, the study's `renv` environment is set up after any
cleanup, in a separate R process. A complete environment is kept: a
`renv/` folder holding `activate.R`, a `.Rprofile` that sources it, and
a `renv.lock` that parses as a lockfile. One interrupted after
initialization (no lockfile yet) is resumed at the snapshot; any other
partial or invalid environment stops with an error. Otherwise the study
`DESCRIPTION` is written (see
[`study_declare`](https://ehrlinger.github.io/hvtiRutilities/reference/study_declare.md)),
`renv::init(bare = TRUE)` creates the environment, and the project is
loaded and snapshotted explicitly in explicit mode, so `renv.lock` comes
from the `DESCRIPTION` and not from a scan of the study's code. The
study's `renv` does not use a per-user package cache (`use.cache` is
`FALSE` in `renv/settings.json`), because the library is shared by the
team and links into one person's cache that others cannot read break
their installs. The renv package must be installed.

## Usage

``` r
study_setup(
  root = NULL,
  study,
  study_tracker_id,
  umbrella = NULL,
  owner = NULL,
  irb_number = NULL,
  cvir_no = NULL,
  study_creation_date = NULL,
  adopt = FALSE,
  identity_source = c("tracker", "manual"),
  cleanup = adopt,
  renv = TRUE,
  template_dir = "/programs/development/template",
  r_upgrade = FALSE
)
```

## Arguments

- root:

  Character. Study root to create or adopt. When omitted, the study
  enclosing the working directory (found as
  [`study_root`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md)
  finds it) is used. Outside a study there is no default:
  `study_setup()` stops and writes nothing, so a new study always names
  its directory. Use `root = "."` with `adopt = TRUE` to set up the
  current folder.

- study:

  Character(1). Study title.

- study_tracker_id:

  Integer(1). Study Tracker topic ID.

- umbrella, owner, irb_number, cvir_no:

  Optional identity values.

- study_creation_date:

  Optional Study Tracker creation date.

- adopt:

  Logical. Permit additive setup in an existing root. When the root
  already holds a `_study.yml` for the same Study Tracker ID and the
  session is interactive, `study_setup()` asks whether to adopt it
  instead of stopping.

- identity_source:

  Character(1). Where the identity values came from: `"tracker"` (the
  default), for a Study Tracker record, or `"manual"`, for values typed
  by hand while the Tracker was unavailable. A new `_study.yml` records
  it as `identity_source`, with `identity_verified` set to `TRUE` for
  `"tracker"` and `FALSE` for `"manual"`. An existing `_study.yml` is
  not rewritten, so adoption keeps the recorded source.

- cleanup:

  Logical. Delete the study's `tp.*` template copies and
  `binder.summaries.doc`, and remove the template folders they leave
  empty. See Details. Defaults to `adopt`: adopting a study cleans it,
  including an adoption accepted at the prompt. Pass `FALSE` to adopt
  without cleaning.

- renv:

  Logical. Initialize and snapshot the study's `renv` environment. See
  Details. Defaults to `TRUE`; test suites that build temporary studies
  should pass `FALSE`.

- template_dir:

  Character(1). The template corpus studies were copied from, read when
  `cleanup = TRUE`. Setup stops with an error when it does not exist.

- r_upgrade:

  Logical(1). Leave `FALSE`. The renv snapshot is refused from an R
  whose major.minor differs from the R recorded in the study's
  `renv.lock` (see
  [`guard_snapshot`](https://ehrlinger.github.io/hvtiRutilities/reference/guard_snapshot.md)),
  because it would rewrite the lock's R and drop packages. Set `TRUE`
  only when you are deliberately moving the study to this session's R.

## Value

An object of class `"study_status"`, returned visibly. With
`cleanup = TRUE` it carries a `"cleanup"` attribute, a list of the
`deleted` files and `removed_dirs` folders, relative to the root. With
`renv = TRUE` it carries a `"renv"` attribute, `"initialized"` or
`"retained"`.

## See also

[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)

## Examples

``` r
root <- file.path(tempdir(), "study-setup-example")
study_setup(root, study = "Example", study_tracker_id = 1L, renv = FALSE)
#> Study: /tmp/RtmpYUuDxz/study-setup-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
list.files(root)
#> [1] "00_datasets"               "10_descriptive"           
#> [3] "20_distributions"          "30_analyses"              
#> [5] "40_graphs"                 "50_documents"             
#> [7] "90_estimates"              "_study.yml"               
#> [9] "study-setup-example.Rproj"

# Running it again on an existing study needs adopt = TRUE; nothing that
# exists is overwritten.
invisible(study_setup(root, study = "Example", study_tracker_id = 1L,
                      adopt = TRUE, renv = FALSE, cleanup = FALSE))

# cleanup = TRUE deletes the template copies a legacy study carries: tp.*
# files, and files identical to one in the template corpus.
corpus <- file.path(tempdir(), "template-corpus")
dir.create(corpus)
writeLines("# template", file.path(corpus, "readme.R"))
invisible(file.copy(file.path(corpus, "readme.R"),
                    file.path(root, "30_analyses")))
writeLines("# template", file.path(root, "30_analyses", "tp.hazard.R"))
done <- study_setup(root, study = "Example", study_tracker_id = 1L,
                    adopt = TRUE, cleanup = TRUE, renv = FALSE,
                    template_dir = corpus)
attr(done, "cleanup")
#> $deleted
#> [1] "30_analyses/readme.R"    "30_analyses/tp.hazard.R"
#> 
#> $removed_dirs
#> character(0)
#> 

unlink(c(root, corpus), recursive = TRUE)
```
