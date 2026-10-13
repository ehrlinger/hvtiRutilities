* Registered versions record how their data were produced. `manifest.yaml` gains a
  `provenance:` map, keyed by parquet name: `origin: bd` with a pointer to the build record
  when a build left a `<stem>.build.yml` describing exactly the file registered, and
  `origin: legacy` otherwise. `verify_manifest()` checks each build record.
* `read_built(working = TRUE)`, or `HVTI_DATA=working`, reads the working dataset before it is
  registered. Any read that is not of a dated version is a working read (a dataset pinned to a catalog release is exempt until the release path is removed): it is allowed in the
  console and in datasets and descriptive jobs, stops in distribution, analysis and graph jobs,
  and signals `hvtiRutilities_working_read`. **A study still on a legacy registration stops in
  those jobs until `update_manifest()` converts it.**
* New `review_built()` compares a rebuilt dataset with its registered version before
  `update_manifest()` registers it.
* The catalog release path is deprecated: `check_data_updates()`, `review_data_update()`,
  `adopt_data_update()`, `register_data(catalog_dataset =, release_id =)` and
  `read_built(allow_withdrawn =)` warn, and `study_config()` warns once on a `release:`
  contract. They will be removed in a later release.
* `update_manifest()` in a study registers a dataset that `_study.yml` names but `manifest.yaml`
  does not list (or a study with no `manifest.yaml`) as its first dated version, so a
  hand-written `built:` no longer leaves `read_built()` and `register_data()` refusing each other.
