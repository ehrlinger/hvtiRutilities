# Has a registered dataset been rebuilt since it was registered?

Says whether a study dataset's source file has changed since its current
version was registered with
[`register_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md)
or
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md).
Jobs keep reading the registered version until
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
registers the rebuild, so a report can use this to say, before it reads
any data, that a newer build is waiting.

It reads no data, but it hashes the source file and compares the SHA-256
with the one recorded at registration, so the answer is about the bytes:
a touch that changed nothing is not reported, and a same-size
replacement that kept the old modification time (a copy or restore that
preserves dates) is. The cost is one pass over the source file.
[`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
and
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
make the same comparison, so every read of a registered dataset hashes
its source once.

## Usage

``` r
source_changed(cfg = study_config(), dataset = "study")
```

## Arguments

- cfg:

  List. A study manifest from
  [`study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- dataset:

  Character(1). Logical dataset name. Defaults to `"study"`. `"built"`
  is a second name for `"study"`.

## Value

`TRUE` when the source differs from the registered version. `FALSE` when
it matches, when the dataset has no registered dated version, or when
the source file is missing, since jobs then keep reading the registered
version and there is nothing newer to register.

## See also

[`review_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/review_built.md)
to compare the rebuild with the registered version,
[`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
to register it.

## Examples

``` r
if (requireNamespace("arrow", quietly = TRUE)) {
  root <- file.path(tempdir(), "source-changed-example")
  suppressMessages(study_setup(root, "Example", 1L, renv = FALSE))
  path <- file.path(study_dir("datasets", root), "example.csv")
  write.csv(data.frame(DEAD = c(1, 0, 0), IV_DEAD = 1:3), path, row.names = FALSE)
  suppressMessages(register_data("example.csv", root = root))
  source_changed(study_config(root))
  write.csv(data.frame(DEAD = c(1, 0, 0, 1), IV_DEAD = 1:4), path, row.names = FALSE)
  source_changed(study_config(root))
  unlink(root, recursive = TRUE)
}
```
