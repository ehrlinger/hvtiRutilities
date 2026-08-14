# Write the macro name-collision report

Reports every macro name defined in more than one file, with its
distinct body count and defining files. In SAS, \` the same macro means
the second silently shadows the first, so this report is a prerequisite
for building a trustworthy SAS harness.

## Usage

``` r
write_collision_report(x, path)
```

## Arguments

- x:

  A `data.frame` returned by
  [`sas_triage`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md).

- path:

  Character. Destination \`.md\` path.

## Value

Invisibly, `path`.

## Examples

``` r
# \donttest{
d <- system.file("extdata", "macros", package = "hvtiRutilities")
if (nzchar(d)) {
  write_collision_report(sas_triage(d), tempfile(fileext = ".md"))
}
# }
```
