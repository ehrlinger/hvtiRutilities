# Package index

## Data Import

Read clinical data files with automatic type conversion

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

Build data dictionaries and compare dataset versions

- [`data_dictionary()`](https://ehrlinger.github.io/hvtiRutilities/reference/data_dictionary.md)
  : Build a data dictionary from a labeled dataset
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

## Package Utilities

- [`hvtiRutilities-package`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities-package.md)
  : hvtiRutilities: Utilities to work with SAS data in R.
- [`hvtiRutilities.news()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities.news.md)
  : Display the NEWS file
