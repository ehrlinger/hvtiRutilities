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

**Folder order is load-bearing. Row order within a folder is not, as of
2026-08-31.**

A template's ordinal takes its major from a hardcoded `FOLDER_ORDINAL`
map in `hvtiRtemplates`, whose authority is this table's folder order.
Adding or reordering a folder therefore renumbers template majors. That
is now *checked* rather than merely documented: since `hvtiRtemplates`
v1.0.16 its `test-roadmap.R` parses that map out of the Python source
and compares it against `unique(hvti_taxonomy()$folder)`, so a folder
change here turns its CI red naming the drift, instead of silently
validating every ordinal's major against the wrong folder.

Row order within a folder is free. An ordinal is assigned once and
recorded in `hvtiRtemplates`'s template ledger, never recomputed from
position, and the test that asserted alignment with row order was
retired in v1.0.16.

Both guards exist because the coupling failed here first. Moving `hs`
out of `analyses` in 1.1.6 shifted `bh` from sixth to fifth while its
shipped filename stayed `04.06`, and nothing caught it. `bh` was
renumbered to `04.05` and `04.06` retired rather than freed, because it
had shipped. An ordinal is an identity, not a position.

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
