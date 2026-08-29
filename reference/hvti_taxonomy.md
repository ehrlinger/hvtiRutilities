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

**Row order within a folder is load-bearing, not cosmetic.**
`hvtiRtemplates` derives a template's ordinal from this table: the major
field is the folder's position and the minor is the row's position
within that folder, and its test suite asserts both. So inserting a row
renumbers every row below it in the same folder. That is free while a
folder is mostly untemplated and expensive afterwards, because the
ordinal is in the filename of every job a study has scaffolded.

**`hs` is filed under `graphs`, which reads oddly for a job named
"setup".** It was moved there from `analyses` on 2026-08-29 on the
corpus rather than on the name: all ten `tp.hs.*` templates in the SAS
library and ten of the eleven R `hs` jobs in `/studies` sit in
`graphs/`. It computes patient-level predictions that the plotting jobs
beside it consume, in the `setup` / `uses_setup` pairing the corpus uses
throughout. See
`hvtiRtemplates:dev/specs/2026-08-29-hs-template-design.md`.

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
