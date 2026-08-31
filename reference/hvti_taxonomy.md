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

**Both folder order and row order within a folder are still
load-bearing. Coordinate any change with `hvtiRtemplates`.**

A template's ordinal takes its major from a hardcoded folder map, so
adding or reordering a *folder* renumbers templates.

The minor is subtler than it was. It is no longer *derived* from row
position: as of `hvtiRtemplates` v1.0.15 it is assigned once, recorded
in `dev/specs/artifacts/2026-08-29-template-roadmap.json` and never
recomputed, because an ordinal is an identity rather than a position.
But that package's `tests/testthat/test-taxonomy.R` still *asserts* that
within-folder ordinal order matches the row order here, so reordering
rows turns its CI red even though no number is recomputed. The two
guards disagree; until that test is retired, treat row order as fixed.

The check compares only prefixes that have a template on disk, so
inserting a row for an untemplated prefix is safe. What is not safe is
changing the relative order of two *templated* prefixes in one folder.

Why this is worth the caution: the coupling has already failed once, in
this package's direction. Moving `hs` out of `analyses` in 1.1.6 shifted
`bh` from sixth to fifth while its shipped filename stayed `04.06`, and
nothing caught it – the ledger checks verify format, folder-major and
uniqueness, never position. `bh` was renumbered to `04.05` and `04.06`
retired rather than freed, because it shipped.

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
