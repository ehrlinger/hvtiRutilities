# Write the canonical macro manifest

Serialises a
[`sas_triage()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md)
decision table to YAML, one entry per macro name, recording its status
and every file that defines it.

## Usage

``` r
write_macro_manifest(x, path)
```

## Arguments

- x:

  A `data.frame` returned by
  [`sas_triage`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md).

- path:

  Character. Destination \`.yaml\` path.

## Value

Invisibly, `path`.

## Details

The manifest deliberately contains **no timestamp**. It describes a
frozen 2019 corpus, and a generated-on field would defeat the
byte-for-byte reproducibility that makes the manifest trustworthy as a
reviewed artifact. Run metadata belongs in the report, not here. This
diverges from
[`update_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md),
whose `extract_date` is meaningful because the datasets it tracks
genuinely change over time.

## Examples

``` r
# \donttest{
d <- system.file("extdata", "macros", package = "hvtiRutilities")
if (nzchar(d)) {
  write_macro_manifest(sas_triage(d), tempfile(fileext = ".yaml"))
}
# }
```
