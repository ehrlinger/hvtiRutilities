# The abbreviation list a study's labels use

Merges the three abbreviation lists a job's labels can draw on, and
checks the result, so that
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
shortens labels the same way in every job of a study:

1.  `extra`, the job's own entries;

2.  the study's `abbreviations:` mapping in `_study.yml`;

3.  the group default list shipped with this package.

A higher level replaces a lower level's entry for the same phrase,
compared ignoring case, and an entry of `null` (`NA` or `NULL` in
`extra`) removes it.

## Usage

``` r
study_abbreviations(cfg = study_config(), extra = NULL, defaults = TRUE)
```

## Arguments

- cfg:

  A study configuration, as returned by
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- extra:

  The job's own entries: a named character vector or list, phrase to
  abbreviation, with `NA` or `NULL` to remove a phrase a lower level
  supplies. `NULL` for none.

- defaults:

  `FALSE` leaves the group default list out.

## Value

A named character vector, phrase to abbreviation, ready for
`label_map(abbreviations = )`, with a `source` attribute of the same
length naming each entry's level: `"job"`, `"study"` or `"default"`.
Removed phrases do not appear.

## Details

Every list is checked before anything is merged, and every problem is
reported in one error: an abbreviation must be one non-empty string no
longer than its phrase, and a phrase may appear only once in a list.
After merging, two phrases may not share an abbreviation, compared
ignoring case, because the shortened label could then mean either; the
error names both phrases and the level each came from.

The list is a display input. It is never written into the stored labels.

## See also

[`add_abbreviation`](https://ehrlinger.github.io/hvtiRutilities/reference/add_abbreviation.md)
to add to a study's list,
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md),
which applies it.

## Examples

``` r
root <- file.path(tempdir(), "abbrev-example")
study_setup(root, "Abbreviation example", 1L)
#> Study: /tmp/RtmpbD6lWZ/abbrev-example
#> 
#> [x] _study.yml — study: Abbreviation example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
add_abbreviation("Surgical procedure", "SP", start = root)
study_abbreviations(study_config(root, require_data = FALSE),
                    extra = c("Left ventricular outflow tract" = "LVOT"))
#>             Surgical procedure Left ventricular outflow tract 
#>                           "SP"                         "LVOT" 
#> attr(,"source")
#> [1] "study" "job"  
unlink(root, recursive = TRUE)
```
