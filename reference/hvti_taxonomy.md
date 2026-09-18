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

**`si` and `mi` are two prefixes, not one, and that is the point.** 223
studies call single mean imputation, 326 call multiple imputation, and
18 call both. They are different methods with different inferential
properties, and 18 studies running both means one prefix could not label
them unambiguously. `mi` is safe here only because it is *paired*:
standing alone it reads as multiple imputation to a statistician, so
using it for the single-imputation job would misname exactly the thing
the split exists to distinguish.

**Neither replaces `vars`, whose description still says "imputations" on
purpose.** `vars` is the job that enhances a dataset with temporary
variables, imputations and propensity terms together – porting
`vars.sas` found mean imputation across 394 variables inside it. `si`
and `mi` name jobs whose *whole purpose* is imputation. A job that
imputes as one step among several is `vars`; a job that exists to impute
is `si` or `mi`.

`folder` names two different things. For most rows it is the analysis
type's home folder, matched to a job prefix. One row, `estimates`, is an
artifact kind rather than a job type: it holds serialized fits and
cached results written by one job and read by a later one in the same
set, and no analysis produces it directly. That row's `prefix` is `NA`,
not a string, because there is no prefix to assign it.

**The random forest family splits on the OUTCOME axis, not the package
axis.** `rfs`, `rfc` and `rfr` name the survival, classification and
regression outcomes, which is the split `bh`/`bl`/`bc`/`bn`/`bq`/`br`
and `pm`/`rm`/`cm` already use. It is a rename of a distinction the
corpus draws already, not a new one imposed: the jobs carry the outcome
in field two today, as `tp.rfsrc.survival.R` and its siblings.

**`rf` and `rfsrc` are retained as legacy umbrella rows.** They named
the same set as each other, on the package axis, and neither is
templated. They stay in the table so a census can still resolve the
corpus that uses them, which is not small: `rfsrc` measures 131 studies
and 2,295 jobs, more than `rf` (47), `rfs` (25) and `rfc` (19) combined,
twice over. Deleting the rows was rejected on two grounds.
[`hvti_prefix_folds`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_prefix_folds.md)
cannot express the demotion, because a fold is one-to-one and `rfsrc`
spans all three outcomes, so there is no single prefix to fold it into.
And an absent prefix reads to the census as one nobody documented, which
is the opposite of what a superseded name means. Demoted here means
*never templated*, and the two rows keep distinct descriptions so a
census hit on a legacy job can still say which spelling it used.

**The job catalog's `disposition: retire` is not the demotion marker,
though it now coincides with it.** In that catalog `retire` means the
work is a function that already exists, so no template is owed;
`hvtiR::jobs()` documents it. Since 2026-09-18 exactly `rf` and `rfsrc`
carry it, because `rfs`, `rfc` and `rfr` moved to `scaffold`, their
templates owed in `hvtiRtemplates` (`ehrlinger/hvtiR` PR \#88, John's
decision of 2026-09-18). The demotion itself is recorded here, in this
table. The two agree today by decision, not by construction, so check
both rather than inferring one.

**`sid` and `vt` are filed under `analyses` with the rest of the
family**, and compose on the `rf*` jobs rather than replacing them. The
`rfc`/`rfs` folder contradiction is deliberately NOT settled here: the
taxonomy says `analyses` while the SAS library files them under `graphs`
and `documents`, and the 2026-08-27 census found the same contradiction
corpus-wide for `ac`/`hz`. It is a systemic open question with its own
spec owed, and the ML batch is not blocked waiting on it. See
`hvtiRtemplates:dev/specs/2026-09-17-ml-family-roadmap-design.md`.

## Examples

``` r
head(hvti_taxonomy())
#>   prefix                name      folder
#> 1     bd               Build    datasets
#> 2   vars           Variables    datasets
#> 3     dt          Data check    datasets
#> 4     si   Single imputation    datasets
#> 5     mi Multiple imputation    datasets
#> 6     dc         Descriptive descriptive
#>                                                           description
#> 1                     assembles raw sources into the analytic dataset
#> 2 macro enhancing the dataset with temp vars, imputations, propensity
#> 3                                     initial QC of the build dataset
#> 4        mean imputation of missing covariates; one completed dataset
#> 5       m completed datasets for pooled analysis; not a variant of si
#> 6                       Table 1s, covariate summaries, balance tables
```
