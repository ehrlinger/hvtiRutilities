# Add a phrase to a study's abbreviation list

Writes one entry to the `abbreviations:` mapping in the study's
`_study.yml`, replacing any entry for the same phrase, compared ignoring
case. `abbreviation = NULL` writes a removal: the study then drops that
phrase from the group default list.

## Usage

``` r
add_abbreviation(phrase, abbreviation, start = getwd())
```

## Arguments

- phrase:

  The phrase, as it appears in labels.

- abbreviation:

  Its abbreviation, or `NULL` to remove a default.

- start:

  A directory inside the study; the study is found as
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md)
  finds it.

## Value

The study's abbreviation list after the change, invisibly, as a named
list.

## Details

The entry is checked against the whole merged list, as
[`study_abbreviations`](https://ehrlinger.github.io/hvtiRutilities/reference/study_abbreviations.md)
would check it, before anything is written; a refused entry leaves the
file as it was. The file is rewritten whole, as
[`register_data`](https://ehrlinger.github.io/hvtiRutilities/reference/register_data.md)
rewrites it, so comments in `_study.yml` are not kept.

## See also

[`study_abbreviations`](https://ehrlinger.github.io/hvtiRutilities/reference/study_abbreviations.md).

## Examples

``` r
root <- file.path(tempdir(), "add-abbrev-example")
study_setup(root, "Abbreviation example", 1L)
#> Study: /tmp/RtmpFC8aEE/add-abbrev-example
#> 
#> [x] _study.yml — study: Abbreviation example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
add_abbreviation("Surgical procedure", "SP", start = root)
add_abbreviation("Ejection fraction", NULL, start = root)
unlink(root, recursive = TRUE)
```
