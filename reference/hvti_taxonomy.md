# Analysis prefix taxonomy

The prefix system inherited from the original CORR analysis binder. The
prefix encodes both the type of analysis and the folder the job belongs
in.

## Usage

``` r
hvti_taxonomy()
```

## Value

A data frame with columns `prefix`, `name`, `folder`, `description`.
`prefix` is `NA` for the one row that names an artifact kind rather than
an analysis type.

## Details

This is data rather than documentation on purpose. The same table lived
in a README and drifted from the files it described; as a function it is
checked by the test suite against the templates actually present.

`folder` names two different things. For most rows it is the analysis
type's home folder, matched to a job prefix. One row, `estimates`, is an
artifact kind rather than a job type: it holds serialized fits and
cached results written by one job and read by a later one in the same
set, and no analysis produces it directly. That row's `prefix` is `NA`,
not a string, because there is no prefix to assign it.

## Examples

``` r
head(hvti_taxonomy())
#>   prefix              name      folder
#> 1     bd             Build    datasets
#> 2   vars         Variables    datasets
#> 3     dt        Data check    datasets
#> 4     dc       Descriptive descriptive
#> 5     lg      Logit trends descriptive
#> 6     rg Regression trends descriptive
#>                                                           description
#> 1                     assembles raw sources into the analytic dataset
#> 2 macro enhancing the dataset with temp vars, imputations, propensity
#> 3                                     initial QC of the build dataset
#> 4                       Table 1s, covariate summaries, balance tables
#> 5                        variable transformation and linearity checks
#> 6                 trend checks for continuous and polytomous outcomes
```
