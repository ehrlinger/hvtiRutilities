# Copilot Instructions for hvtiRutilities

## Project Overview
- **hvtiRutilities** is an R package providing utility functions for data labeling, type mapping, and sample data workflows. The codebase follows standard R package structure.
- Key directories:
  - `R/`: Main source code (functions, helpers)
  - `man/`: Documentation for exported functions
  - `tests/`: Test suite using `testthat`
  - Root files: `DESCRIPTION`, `NAMESPACE`, `.Rproj`, `README.md`

## Developer Workflows
- **Build & Check:**
  - Use RStudio or run `devtools::check()` for package validation.
  - Run `R CMD check .` in terminal for full checks.
- **Testing:**
  - Tests are in `tests/testthat/`. Run all tests with `devtools::test()` or `testthat::test_dir("tests/testthat")`.
- **Documentation:**
  - Update `.Rd` files in `man/` using `devtools::document()`.
- **Installation:**
  - Install with `pak::pak("ehrlinger/hvtiRutilities")` or `devtools::install()`.

## Project-Specific Patterns
- **Label Mapping:**
  - See `R/label_map.R` and `man/label_map.Rd` for conventions on mapping labels to values.
- **Data Types:**
  - Type mapping logic is in `R/r_data_types.R` and documented in `man/r_data_types.Rd`.
- **Sample Data:**
  - Example datasets and usage in `R/sample_data.R` and `man/sample_data.Rd`.
- **Helpers:**
  - Utility functions are in `R/help.R`.
- **Initialization:**
  - Package startup logic in `R/zzz.R`.

## Conventions
- All exported functions are documented in `man/` and listed in `NAMESPACE`.
- Tests use `testthat` and are organized by feature (see `test-label_map.R`, `test-r_data_types.R`, etc).
- Follow R package best practices for function naming, documentation, and testing.

## Integration Points
- No external APIs or non-standard dependencies; relies on CRAN packages (`pak`, `devtools`, `testthat`).
- GitHub Actions for CI (`.github/workflows/R-CMD-check.yaml`).
- Code coverage via Codecov (`codecov.yml`).

## Example: Adding a Utility
- Add function to `R/` (e.g., `R/new_util.R`).
- Document in `man/` (e.g., `man/new_util.Rd`).
- Export in `NAMESPACE`.
- Add tests in `tests/testthat/test-new_util.R`.

---
For questions about unclear conventions or missing documentation, ask for clarification or review the relevant source file.
