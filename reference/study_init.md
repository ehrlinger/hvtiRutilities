# Initialize a study for reproducible analysis

Writes a study's `_study.yml` identity manifest and seeds a
`manifest.yaml` pinning the built dataset's SHA-256, so that a result
filed years later can name what produced it.

The cohort counts are **derived** from the dataset rather than accepted
as arguments. Only the study's identity – its title, its dataset
filename, and the columns that define the event and the follow-up time –
has to be supplied, because none of that can be inferred.

`renv` is not touched. A missing `renv.lock` is reported as an open item
by
[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md);
creating one is `renv::init()`'s job, and it restarts the R session.

## Usage

``` r
study_init(
  root,
  study,
  built,
  event,
  time,
  population = NULL,
  source = NULL,
  extract_date = NULL
)
```

## Arguments

- root:

  Character. The study root to initialize. Must exist and be writable,
  and must not already contain a `_study.yml`.

- study:

  Character(1). The study title, recorded verbatim.

- built:

  Character(1). Filename of the built dataset within `<root>/datasets`,
  **with** its extension – the reader dispatches on it.

- event:

  Character(1). Name of the event-indicator column.

- time:

  Character(1). Name of the follow-up-time column.

- population:

  Character(1) or `NULL`. Free-text description of the cohort. Optional.

- source:

  Character(1) or `NULL`. Free-text description of where the dataset
  came from, passed to
  [`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md).

- extract_date:

  Character, `Date`, or `NULL`. The date the data were pulled. When
  `NULL` the dataset file's modification date is used, because recording
  today's date for a dataset built years ago would write a false fact
  into the manifest.

## Value

An object of class `"study_status"`, returned visibly, so the remaining
open items are shown at the console.

## See also

[`study_status`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md),
[`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md),
[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)

## Examples

``` r
root <- file.path(tempdir(), "study-init-example")
dir.create(file.path(root, "datasets"), recursive = TRUE,
           showWarnings = FALSE)
write.csv(data.frame(dead = c(1, 0, 0), iv_dead = 1:3),
          file.path(root, "datasets", "example.csv"), row.names = FALSE)
st <- study_init(root, study = "Example", built = "example.csv",
                 event = "dead", time = "iv_dead")
study_config(root)$cohort$n
#> [1] 3
unlink(root, recursive = TRUE)
```
