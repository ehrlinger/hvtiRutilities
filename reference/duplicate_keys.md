# Find rows that repeat a key, and choose which to keep

Lists the rows of `data` that share a value of `key`, such as a patient
with two operations on the same day under the key
`c("ccfid", "dt_surg")`. Given `order_by`, it also marks the first row
of each repeated key to keep, which is how the SAS jobs resolve them:
the first operation is kept and the second is treated as a complication
of it.

## Usage

``` r
duplicate_keys(data, key, order_by = NULL, show_key = FALSE)
```

## Arguments

- data:

  A data frame.

- key:

  Names of the columns that should make each row unique.

- order_by:

  `NULL` (the default), or names of the columns that order the rows of a
  repeated key. Required for `keep`.

- show_key:

  Include the key columns in `rows`? Default `FALSE`.

## Value

An object of class `duplicate_keys`, a list of three:

- `summary`:

  One row: `rows`, `keys` (distinct key values), `repeated_keys`,
  `rows_in_repeats` and `missing_keys` (rows missing any key column).

- `rows`:

  One row per row of `data` in a repeated key, in data order: `row`, its
  row number in `data`; `.group`, numbering the repeated keys in order
  of appearance; `.rank`, its place within the key by `order_by` (`NA`
  without `order_by`); then the key columns when `show_key = TRUE`.

- `keep`:

  A logical vector, one per row of `data`: `TRUE` for every row outside
  a repeated key and for the first row of each repeated key. `NULL`
  without `order_by`.

## Details

`data` is never changed. Subset it with `keep`: `data[dk$keep, ]` is
unique on `key`, and `data[!dk$keep, ]` holds the rows set aside, to
record or to carry as complications. Drop rows in the build, where
corrections belong, not in a study job.

"First" means first when the rows of a repeated key are sorted by the
`order_by` columns, in ascending order. When the first two rows of a
repeated key tie on `order_by`, or a row in a repeated key is missing an
`order_by` value, there is no first row to keep, and the function stops
rather than pick one. Add a column that separates them, such as the time
of the operation.

A missing key value is treated as a value, as
[`duplicated`](https://rdrr.io/r/base/duplicated.html) treats it, so two
rows missing the key repeat it. Missing keys are also counted in
`summary`.

Key values are left out of `rows` unless `show_key = TRUE`, because a
key is usually a patient identifier. Use `rows$row` to look at the rows
in `data`.

## See also

[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md),
whose `key` argument refuses a dataset that repeats it.

## Examples

``` r
ops <- data.frame(
  id = c(1, 2, 2, 3),
  dt_surg = as.Date(c("2010-01-05", "2012-03-01", "2012-03-01", "2011-06-01")),
  op_time = c(8, 14, 9, 10)
)
dk <- duplicate_keys(ops, c("id", "dt_surg"), order_by = "op_time")
dk
#> Key: id, dt_surg
#> 4 rows, 3 distinct keys. 1 key repeats, over 2 rows.
#> Keeping the first by op_time: 1 rows set aside.
dk$rows
#>   row .group .rank
#> 1   2      1     2
#> 2   3      1     1
ops[dk$keep, ]
#>   id    dt_surg op_time
#> 1  1 2010-01-05       8
#> 3  2 2012-03-01       9
#> 4  3 2011-06-01      10
ops[!dk$keep, ]
#>   id    dt_surg op_time
#> 2  2 2012-03-01      14
```
