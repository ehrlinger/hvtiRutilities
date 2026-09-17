# SAS oracle for `proc_univariate()`

Real SAS output that `proc_univariate()` is tested against. Design:
`dev/specs/2026-09-17-proc-univariate-design.md`. Everything here is under
`dev/`, so none of it ships in the package.

| file | role |
|---|---|
| `make_fixtures.R` | writes `fixtures/*.csv` and `scenarios.csv`. Deterministic: no random numbers |
| `fixtures/` | small synthetic inputs, each aimed at one behaviour. No study data |
| `scenarios.csv` | one row per SAS run: fixture, `WEIGHT`, `VARDEF=`, `MU0=`, `CLASS`, which tests to request |
| `oracle.sas` | runs `PROC UNIVARIATE ... OUTPUT OUT=` for every scenario and writes `out/` |
| `check_oracle.R` | checks `out/` is complete and well formed before it is committed |

## Running it

1. If `scenarios.csv` or a fixture needs to change, edit `make_fixtures.R`
   and run it from the package root:
   `Rscript dev/oracle/proc_univariate/make_fixtures.R`.
   Commit the regenerated files; never edit them by hand.
2. In SAS, set `%let root =` at the top of `oracle.sas` to this directory and
   submit the whole file. It writes `out/<scenario>.csv`,
   `out/sas_version.txt` and `out/oracle.log`.
3. Copy `out/` back into this directory if SAS ran elsewhere, then from the
   package root run:
   `Rscript dev/oracle/proc_univariate/check_oracle.R`.
   It exits 0 when every required scenario is present with the expected
   columns and rows. A `NOTE` for an `optional` scenario means SAS refused a
   request the design expects it to refuse; read `out/oracle.log` to confirm
   why. Also search `out/oracle.log` for `ERROR` and `Invalid data`; an
   `Invalid data` line means a fixture was read wrongly (for example with
   Windows line endings), and the run must be repeated.
4. Commit `out/` on the branch. The implementation work moves the outputs
   and fixtures under `tests/testthat/fixtures/proc_univariate/`.

## Scenarios that are expected to fail

`wt_frac_alltests` requests the sign, signed-rank and normality tests under
`WEIGHT`, and `vardef_n_alltests` requests the t test under `VARDEF=N`. The
design assumes SAS does not compute these and returns `NA` for them. Whether
SAS writes missing values, or refuses and writes no file, is the result being
recorded.
