# Changelog

## hvtiRutilities 0.1.3

### Bug Fixes

- Fixed critical bug in
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  where
  [`dplyr::na_if()`](https://dplyr.tidyverse.org/reference/na_if.html)
  was called with a vector instead of scalar values
- Fixed bug where character columns with 2 unique values were
  incorrectly converted to logical (returning all NAs)
- Fixed bug in
  [`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)
  where [`sample.int()`](https://rdrr.io/r/base/sample.html) parameters
  were reversed, causing errors for small sample sizes
- Fixed column order preservation bug in
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  when using `skip_vars` - columns now maintain original order
- Fixed silent parameter mutation bug where `factor_size > 50` was
  changed to 20 without user consent - now errors instead

### Improvements

- Removed unused `lubridate` dependency that was never actually used in
  the package
- Removed inappropriate use of
  [`invisible()`](https://rdrr.io/r/base/invisible.html) from
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  and
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  functions
- Implemented
  [`hvtiRutilities.news()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvtiRutilities.news.md)
  function that was referenced but didn’t exist
- Completely rewrote test suite with modern testthat 3 syntax (removed
  deprecated `context()` calls)
- Expanded test coverage from 24 tests to 75 comprehensive tests
- Added proper examples to
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  documentation with `@examples` tag
- Improved error messages for better clarity and consistency
- Changed `== TRUE` comparisons to simpler boolean checks

### Documentation

- Complete rewrite of README.md with actual package description and
  usage examples
- Fixed
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  documentation (was incomplete sentence, wrong return type)
- Improved
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
  documentation with clearer parameter descriptions
- Added comprehensive usage examples for all main functions

## hvtiRutilities 0.1.2

- Internal development version

## hvtiRutilities 0.1.1

- Internal development version

## hvtiRutilities 0.1.0

- Initial release
- Core functions:
  [`r_data_types()`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md),
  [`label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md),
  [`sample_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/sample_data.md)
