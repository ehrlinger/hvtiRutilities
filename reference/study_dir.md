# Resolve a directory in the study layout

Maps a logical study directory such as `"datasets"` to the numbered
spelling used by new studies or the bare spelling retained by legacy
studies. A root containing both layouts is an error. A root containing
neither – a new or empty study – resolves to the numbered spelling, as
[`study_setup()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.md)
lays one out.

## Usage

``` r
study_dir(folder, root = study_root())
```

## Arguments

- folder:

  Character. One logical study directory name.

- root:

  Character. Study root. Defaults to
  [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md).

## Value

Character(1). The resolved directory path. Its existence is not
required.

## See also

[`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md),
[`sas_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_path.md)

## Examples

``` r
root <- file.path(tempdir(), "numbered-study-layout")
dir.create(file.path(root, "00_datasets"), recursive = TRUE,
           showWarnings = FALSE)
study_dir("datasets", root)
#> [1] "/tmp/RtmpWaWeM8/numbered-study-layout/00_datasets"
unlink(root, recursive = TRUE)
```
