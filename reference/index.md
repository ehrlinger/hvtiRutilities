# Package index

## Data Import

Read clinical data files as stored. Type conversion is opt-in via
convert_types, because coercing a two-valued numeric to logical breaks
0/1 event and censoring flags.

- [`read_clinical_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md)
  : Read and prepare a clinical dataset in one step

## Data Type Conversion

Automatically infer and convert column types

- [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  : Automatically infer and convert data types

## Variable Labels

Extract, look up, register, and override variable labels

- [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  : Build a lookup map of data labels
- [`get_label()`](https://ehrlinger.github.io/hvtiRutilities/reference/get_label.md)
  : Look up the label for a single variable
- [`get_labels()`](https://ehrlinger.github.io/hvtiRutilities/reference/get_labels.md)
  : Look up labels for multiple variables at once
- [`add_labels()`](https://ehrlinger.github.io/hvtiRutilities/reference/add_labels.md)
  : Add or update labels in a label map
- [`apply_label_overrides()`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)
  : Apply label overrides from a YAML file
- [`clean_labels()`](https://ehrlinger.github.io/hvtiRutilities/reference/clean_labels.md)
  : Apply label overrides from a YAML file (deprecated)

## Data Documentation

Build data dictionaries, summarise variables, and compare dataset
versions

- [`data_dictionary()`](https://ehrlinger.github.io/hvtiRutilities/reference/data_dictionary.md)
  : Build a data dictionary from a labeled dataset
- [`dataset_schema()`](https://ehrlinger.github.io/hvtiRutilities/reference/dataset_schema.md)
  : Column-level schema of a dataset
- [`proc_contents()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
  : Describe a dataset's variables, in the style of SAS PROC CONTENTS
- [`proc_means()`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_means.md)
  : Summarise numeric variables, in the style of SAS PROC MEANS
- [`compare_datasets()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_datasets.md)
  : Compare two versions of a dataset

## Dataset Versioning

Track and verify dataset integrity with SHA-256 checksums

- [`update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.md)
  : Create or update a dataset manifest file
- [`verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.md)
  : Verify all datasets listed in a manifest

## Data Generation

Generate labeled sample and synthetic datasets

- [`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
  : Generate Synthetic Cardiac Surgery Survival Data
- [`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)
  : Generate a sample dataset for testing

## SAS Macro Canonicalization

Inventory a legacy SAS macro library and resolve name collisions

- [`sas_triage()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md)
  : Triage a directory of legacy SAS macro files
- [`sas_macro_defs()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_macro_defs.md)
  : Extract every macro definition from a SAS file
- [`sas_macro_signature()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_macro_signature.md)
  : Parse the documentation header of a legacy SAS macro file
- [`write_macro_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_macro_manifest.md)
  : Write the canonical macro manifest
- [`write_collision_report()`](https://ehrlinger.github.io/hvtiRutilities/reference/write_collision_report.md)
  : Write the macro name-collision report

## SAS Parity

Compare an R result against its SAS reference under derived tolerances

- [`parity_tolerance()`](https://ehrlinger.github.io/hvtiRutilities/reference/parity_tolerance.md)
  : Tolerance classes for SAS parity comparison
- [`compare_parity()`](https://ehrlinger.github.io/hvtiRutilities/reference/compare_parity.md)
  : Compare one R quantity against its SAS reference
- [`parity_headline()`](https://ehrlinger.github.io/hvtiRutilities/reference/parity_headline.md)
  : Summarise a parity table as one reviewer-facing claim

## Study Setup

Initialize a study for reproducible analysis, and audit whether it is
ready

- [`study_init()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_init.md)
  : Initialize a study for reproducible analysis
- [`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.md)
  : Audit a study's reproducibility readiness
- [`study_checklist()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_checklist.md)
  : Render a study audit as a markdown checklist
- [`preflight_report()`](https://ehrlinger.github.io/hvtiRutilities/reference/preflight_report.md)
  : Audit the analysis environment before running an analysis

## Study Manifest and Data Contract

Locate a study from its `_study.yml`, resolve its paths, and read and
reconcile its built dataset

- [`study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md)
  : Read the study manifest
- [`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.md)
  : Locate the study root
- [`sas_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_path.md)
  : Build a path under the study root
- [`built_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_path.md)
  : Path to the study's built dataset
- [`built_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/built_manifest.md)
  : Record the state of the built dataset
- [`read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.md)
  : Read the study's built dataset
- [`cohort_counts()`](https://ehrlinger.github.io/hvtiRutilities/reference/cohort_counts.md)
  : Count the analysable cohort
- [`assert_cohort()`](https://ehrlinger.github.io/hvtiRutilities/reference/assert_cohort.md)
  : Assert the cohort matches the study manifest

## Provenance

Record what produced a filed result, in a JSON sidecar beside it

- [`record_provenance()`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)
  : Write the provenance record for a rendered output
- [`provenance_path()`](https://ehrlinger.github.io/hvtiRutilities/reference/provenance_path.md)
  : Name the provenance sidecar for an output

## Package Utilities

- [`hvtiRutilities-package`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities-package.md)
  : hvtiRutilities: Utilities to work with SAS data in R.
- [`hvtiRutilities.news()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities.news.md)
  : Display the NEWS file
- [`r_dir_impurities()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_dir_impurities.md)
  : Report top-level executable code in an R directory
