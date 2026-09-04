# Strip a leading code prefix from level text

Removes a leading integer code and its separator from the text of a
variable's levels, so `"1. Yes"` prints as `"Yes"`. It is a display
helper: it returns new text and **never** rewrites the levels of the
object it was given.

## Usage

``` r
strip_level_prefix(x)
```

## Arguments

- x:

  A character vector of level text, or a factor. Given a factor, the
  function reads `levels(x)` and returns one element per level - it does
  not return one element per observation, and it does not modify `x`.

## Value

A character vector of display text: one element per input element, or
one per level when `x` is a factor. `NA` is returned as `NA`.

## Details

**A separator is required.** A leading integer is removed only when one
of `.` `:` `=` `)` `-` follows it, with optional whitespace either side.
A bare digit followed by a space is left alone.

That restraint is the point. A rule general enough to turn `"0 No"` into
`"No"` also turns `"1 vessel disease"`, `"2 vessel"` and `"3 vessel"`
into `"vessel disease"`, `"vessel"` and `"vessel"` - three distinct
levels becoming two identical strings. Nothing errors; a downstream
[`table()`](https://rdrr.io/r/base/table.html) or model merges them and
the level count silently stops matching the data dictionary. The failure
presents as data rather than as a bug.

So the rule is biased: **a missed strip is visible in the output and
fixable by declaring the level text in `value_labels.yml` (see
[`apply_value_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_value_labels.md));
a wrong strip is silent and corrupts the level set.** Two consequences
follow.

- Unpunctuated `"0 No"` and `"1 Yes"` are **not** stripped and still
  print with their prefix.

- Text whose remainder begins with a digit is not stripped either,
  because `"1-2 vessels"` matches leading-integer-then-hyphen and would
  otherwise become `"2 vessels"`, colliding with a real `"2 vessels"`
  level. Ranges are ordinary in this domain.

**Collisions revert rather than merge.** If stripping would bring two
*different* texts together - two codes carrying the same words, or a
stripped entry landing on one that was already bare - every entry
involved keeps its original text and a warning names the text they
collided on. The level set is preserved whatever the input, which is the
guarantee this function is worth having for.

Repeated copies of the same text are not a collision. Two occurrences of
`"1. Yes"` both become `"Yes"` without complaint, because the level set
had one member before and has one after. That is what makes the function
usable on a raw character column, where repeats are ordinary.

Stripping never produces an empty string: `"1."` is returned unchanged.

## See also

[`level_map`](https://ehrlinger.github.io/hvtiRutilities/reference/level_map.md)
to see what stripping would do across a dataset,
[`apply_value_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_value_labels.md)
for declaring level text outright rather than tidying it afterwards.

## Examples

``` r
strip_level_prefix(c("1. Yes", "0 = No", "01 - home"))
#> [1] "Yes"  "No"   "home"

# A separator is required, so these survive intact
strip_level_prefix(c("1 vessel disease", "2 vessel", "3 vessel"))
#> [1] "1 vessel disease" "2 vessel"         "3 vessel"        

# And so does a range, whose remainder begins with a digit
strip_level_prefix("1-2 vessels")
#> [1] "1-2 vessels"

# A factor is read through its levels, and is not modified
f <- factor(c("1. Yes", "0. No"))
strip_level_prefix(f)
#> [1] "No"  "Yes"
levels(f)
#> [1] "0. No"  "1. Yes"
```
