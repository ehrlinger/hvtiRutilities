# Second fields that are not analysis prefixes

Some file names lead with a utility name rather than an analysis prefix
— `plots`, `PPTs`. They are listed here so the test suite can tell "not
a prefix" apart from "a prefix nobody documented". Without this
distinction the taxonomy either fills with non-prefixes or stops
catching real omissions.

## Usage

``` r
hvti_non_prefixes()
```

## Value

A character vector.

## Examples

``` r
hvti_non_prefixes()
#> [1] "plots" "ppt"   "PPTs"  "test"  "pp"    "ref"   "refs" 
```
