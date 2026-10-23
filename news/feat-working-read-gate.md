* The working-read gate keys on draft or final, not on the job's folder. A draft render of a job in any stage folder may read the working file; a final render (`HVTI_TEMPLATE_STRICT` set, as `render_job(final = TRUE)` sets it) and a script run with `Rscript` read registered data only, in every folder. A final descriptive render on an unregistered build now stops and names `update_manifest()`.

* New `declare_data()` names a study's working dataset in `_study.yml` without registering a version, so a new study's first build can be read by a draft. It also writes an empty `manifest.yaml` when the study has none, so `verify_manifest()` has a file to read. Until the dataset is registered, every read of it is a working read, allowed in the console and in a draft render.

* `provenance_data(working = TRUE)` records `working = TRUE`; a registered read's record is unchanged.
