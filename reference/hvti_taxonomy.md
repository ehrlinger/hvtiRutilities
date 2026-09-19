# Analysis prefix taxonomy

The prefix system inherited from the original CORR analysis binder. The
prefix encodes both the type of analysis and the folder the job belongs
in.

## Usage

``` r
hvti_taxonomy()
```

## Value

A data frame with columns `prefix`, `name`, `folder`, `description` and
`umbrella`. `prefix` is `NA` for the one row that names an artifact kind
rather than an analysis type. `umbrella` is logical: `TRUE` for the
legacy umbrella prefixes `rf` and `rfsrc`, for which no template is
owed; `FALSE` for every other prefix; `NA` for the artifact row.

## Details

This is data rather than documentation on purpose. The same table lived
in a README and drifted from the files it described; as a function it is
checked by the test suite against the templates actually present.

**Folder names are load-bearing. Row order is not, folder order
included, as of 2026-09-03.**

A template directory and a numbered study directory are both spelled
`<NN>_<folder>`, as in `20_distributions`; a legacy study keeps the bare
name, as in `distributions`, and
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)
resolves either. The name after the digits, or the bare name, must be a
`folder` in this table. `hvtiRtemplates` tests that every template
directory names one, so renaming or removing a folder that holds a
template turns its CI red. The digits are *assigned*, not derived from
this table. They are hardcoded in
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)'s
layout map here and in the template directory names there, and
`estimates` is `90` though it is the table's fifth folder, because it
holds saved output rather than jobs. Reordering rows, or folders,
changes nothing downstream.

*Adding or renaming* a folder is not free on the study side.
[`study_dir`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)
knows only the folders in its own layout map, and no test compares that
map's names with `unique(hvti_taxonomy()$folder)`, so a folder added
here and not there is one
[`study_dir()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_dir.md)
refuses as unknown.

Templates carry no ordinal. They were once named `<NN>.<MM>-<prefix>`,
with `NN` taken from this table's folder order through a hardcoded map
in `hvtiRtemplates`; the ordinal and that map were both retired on
2026-09-03
(`hvtiRtemplates:dev/specs/2026-09-03-template-identity-design.md`). A
template is now `<prefix>[-<qualifier>].qmd`, and the catalog that lists
them is `hvtiRtemplates`' own `inst/extdata/templates.json`.

History, kept because it is why the digits are assigned: moving `hs` out
of `analyses` in 1.1.6 shifted `bh` from sixth to fifth while its
shipped filename stayed `04.06`, and nothing caught it. `bh` was
renumbered `04.05`. Identity derived from a row position breaks when an
upstream row moves. A job named `04.06-bh`, from `hvtiRtemplates` before
its 1.1.0, is the same template as `04.05-bh`.

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
*never templated*, and since 2026-09-18 it is machine-readable as well
as worded: the `umbrella` column is `TRUE` on exactly these two rows, so
a consumer can exempt them without hard-coding a list. The two rows keep
distinct descriptions so a census hit on a legacy job can still say
which spelling it used.

**The demotion is recorded here, and only here.** Until 2026-09-19
`hvtiR`'s job catalog also marked `rf` and `rfsrc` with a `retire`
disposition, which coincided with this demotion by decision. That
catalog has moved to `hvtiRtemplates` as its template catalog, read by
`hvtiRtemplates::template_catalog()`, where every row is a template owed
in that package. It has no `retire` disposition, and `rf` and `rfsrc`
have no row at all; its guard that every taxonomy prefix has a catalog
row exempts them by reading the `umbrella` column above. `hvtiR::jobs()`
was removed in `hvtiR` 1.2.0.

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
#>                                                           description umbrella
#> 1                     assembles raw sources into the analytic dataset    FALSE
#> 2 macro enhancing the dataset with temp vars, imputations, propensity    FALSE
#> 3                                     initial QC of the build dataset    FALSE
#> 4        mean imputation of missing covariates; one completed dataset    FALSE
#> 5       m completed datasets for pooled analysis; not a variant of si    FALSE
#> 6                       Table 1s, covariate summaries, balance tables    FALSE
```
