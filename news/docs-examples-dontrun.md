* Seven help pages lose their `\dontrun{}` examples for ones that run:
  `update_manifest()` and `verify_manifest()` register and check a CSV under
  `tempdir()`, `data_dictionary()` writes its CSV to a temporary file, the
  deprecated `check_data_updates()`, `review_data_update()` and
  `adopt_data_update()` show their deprecation on a throwaway study, and
  `hvtiRutilities.news()` runs only in an interactive session.
