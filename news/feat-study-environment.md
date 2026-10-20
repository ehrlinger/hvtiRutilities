* `study_setup()` now cleans up template copies whenever it adopts a study (`cleanup` defaults to `adopt`,
  including an adoption accepted at the prompt) and sets up renv by default (`renv = TRUE`). Adopting a study
  where the template corpus is absent now stops unless `template_dir` is given or `cleanup = FALSE`.
* renv environments are created in explicit mode: `renv.lock` is built from the study's `DESCRIPTION`, never by
  scanning its code, so stale template copies cannot add packages to it. `.renvignore` also covers `tp.*` and
  `old_RF_templates*/` for studies set up before.
* New `study_declare()` records the packages a study needs in its `DESCRIPTION`, and keeps every other field and
  the existing entries as written.
* `study_setup(renv = TRUE)` now stops before writing anything when renv is not installed or the root has a
  package `DESCRIPTION`; `renv = FALSE` is the way out.
* New `study_need()` installs a missing package such as arrow into the study's library and records it, instead
  of stopping with an `install.packages()` line. Outside a renv study it names `hvtiR::setup()`.
