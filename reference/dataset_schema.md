# Column-level schema of a dataset

One row per column: creation position, name, R class, SAS two-valued
type, `format.sas` and label. This is the durable description of a
source dataset — what a schema sidecar records, and what a later read is
compared against.

## Usage

``` r
dataset_schema(data)
```

## Arguments

- data:

  A data frame, tibble, or similar tabular object.

## Value

A data frame with columns `num` (creation position, integer),
`variable`, `class` (first R class), `type` (`"Num"`/`"Char"`), `format`
(SAS format or `NA`) and `label` (or `NA`).

## Details

`label` and `format` are read from the column attributes directly and
are `NA` when the source carries none. This is the difference from
[`proc_contents`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md),
which fills an absent label with the variable's own name: right for a
printed listing, wrong for a record that outlives the source dataset.

Nothing here describes the data, only its shape. Two reads of an
unchanged file produce an identical schema, which is what makes the
sidecar's hash meaningful.

## See also

[`proc_contents`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
for a printable listing that also summarises completeness.

## Examples

``` r
d <- data.frame(x = 1:3, y = letters[1:3])
attr(d$x, "label") <- "An identifier"
dataset_schema(d)
#>   num variable     class type format         label
#> 1   1        x   integer  Num   <NA> An identifier
#> 2   2        y character Char   <NA>          <NA>
```
