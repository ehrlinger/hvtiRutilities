# Report top-level executable code in an R directory

Parses every `.R` file in `dir` and reports any top-level expression
that is not an assignment. Function definitions and constants pass;
calls do not.

Use this on any directory that is sourced wholesale, where a stray call
would execute on every render.

## Usage

``` r
r_dir_impurities(dir)
```

## Arguments

- dir:

  Character(1). Directory to check.

## Value

A character vector of complaints, one per offending expression, empty
when the directory is clean. The caller decides whether to warn or to
fail.

## Examples

``` r
d <- file.path(tempdir(), "purity-example")
dir.create(d, showWarnings = FALSE)
writeLines(c("f <- function(x) x + 1", "print(f(1))"),
           file.path(d, "example.R"))
r_dir_impurities(d)
#> [1] "example.R: top-level expression is not an assignment: print(f(1))"
unlink(d, recursive = TRUE)
```
