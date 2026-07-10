# SAS macro name-collision report

Macro names defined in more than one file. In SAS, `%include`-ing two
such files means the second definition silently shadows the first.

| Macro | Files | Distinct bodies | Visibility | Status |
|---|---|---|---|---|
| `blord` | 3 | 3 | private | **ambiguous** |
| `bnprev` | 5 | 5 | private | **ambiguous** |
| `bootreg` | 5 | 4 | private | **ambiguous** |
| `botregwt` | 2 | 2 | private | **ambiguous** |
| `break` | 6 | 2 | private | **ambiguous** |
| `callfreq` | 1 | 2 | private | canonical |
| `cdfs1` | 1 | 2 | private | canonical |
| `cind_haz` | 2 | 1 | private | canonical |
| `combo` | 1 | 2 | private | canonical |
| `dcom` | 3 | 1 | private | canonical |
| `dcom1` | 3 | 1 | private | canonical |
| `dcom2` | 3 | 1 | private | canonical |
| `decompos` | 2 | 2 | private | **ambiguous** |
| `edt` | 1 | 3 | private | canonical |
| `edt1` | 1 | 1 | private | canonical |
| `edt2` | 1 | 2 | private | canonical |
| `edt3` | 1 | 1 | private | canonical |
| `edt3a` | 1 | 1 | private | canonical |
| `edt4` | 1 | 1 | private | canonical |
| `f` | 3 | 1 | private | canonical |
| `freq` | 1 | 2 | private | canonical |
| `freq1` | 1 | 2 | private | canonical |
| `g` | 3 | 1 | private | canonical |
| `greedmtch` | 2 | 2 | private | **ambiguous** |
| `hazboot` | 7 | 7 | private | **ambiguous** |
| `hazbtcp` | 5 | 4 | private | **ambiguous** |
| `initcc` | 2 | 1 | private | canonical |
| `kap_tvc` | 2 | 2 | private | **ambiguous** |
| `kaplan` | 2 | 2 | private | **ambiguous** |
| `linregm` | 2 | 2 | private | **ambiguous** |
| `logistc` | 3 | 3 | private | **ambiguous** |
| `match` | 2 | 2 | private | **ambiguous** |
| `mrg` | 13 | 4 | private | **ambiguous** |
| `mrg0` | 2 | 1 | private | canonical |
| `mrg1` | 3 | 2 | private | **ambiguous** |
| `mrg2` | 3 | 2 | private | **ambiguous** |
| `mrg3` | 2 | 2 | private | **ambiguous** |
| `mw_var` | 2 | 2 | public | **ambiguous** |
| `np_ice` | 2 | 2 | public | **ambiguous** |
| `numobs` | 5 | 1 | private | canonical |
| `probest` | 3 | 1 | private | canonical |
| `reorder` | 1 | 2 | private | canonical |
| `reorder2` | 1 | 2 | private | canonical |
| `reorder3` | 1 | 2 | private | canonical |
| `reorder4` | 1 | 1 | private | canonical |
| `repeat` | 2 | 2 | public | **ambiguous** |
| `sans` | 1 | 1 | private | canonical |
| `skip` | 10 | 7 | private | **ambiguous** |
| `skkip` | 5 | 1 | private | canonical |
| `sortcc` | 2 | 1 | private | canonical |
| `std_cof` | 3 | 2 | private | **ambiguous** |
| `std_dif` | 5 | 5 | public? | **ambiguous** |
| `stdz` | 1 | 2 | private | canonical |
| `stspred` | 3 | 3 | private | **ambiguous** |
| `trunc` | 1 | 4 | private | canonical |
| `tx` | 1 | 2 | private | canonical |
| `usmatchd` | 3 | 3 | public | **ambiguous** |

Total colliding names: 57

## Excluded subdirectories

Not triaged. Counts recorded so the omission is visible.

| Directory | `.sas` files |
|---|---|
| `archive` | 20 |
| `CVS` | 0 |
| `logis_reclassi` | 4 |
| `macros_to_test` | 2 |
| `readin_samples` | 17 |
| `repeat_test` | 2 |
| `table_mac` | 17 |
| `tests` | 17 |
