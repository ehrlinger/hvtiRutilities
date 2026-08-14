library(testthat)
library(hvtiRutilities)

fx_dir <- function() testthat::test_path("fixtures")

# ---------------------------------------------------------------------------
# Visibility classification
# ---------------------------------------------------------------------------

test_that(".classify_visibility marks an exact basename match public", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_dif.sas"),
    "public"
  )
})

test_that(".classify_visibility marks a variant-suffixed file public?", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_dif_wt.sas"),
    "public?"
  )
  expect_equal(
    hvtiRutilities:::.classify_visibility("std_dif", "std_difma.sas"),
    "public?"
  )
})

test_that(".classify_visibility marks an inline helper private", {
  expect_equal(
    hvtiRutilities:::.classify_visibility("skip", "readin.sas"),
    "private"
  )
  expect_equal(
    hvtiRutilities:::.classify_visibility("numobs", "lgtphcurv9.sas"),
    "private"
  )
})

test_that(".strip_variant_suffix removes known variant markers", {
  expect_equal(hvtiRutilities:::.strip_variant_suffix("std_dif_wt"), "std_dif")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("std_difma"), "std_dif")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("cr_compare_cp_old"), "cr_compare_cp")
  expect_equal(hvtiRutilities:::.strip_variant_suffix("epsilon"), "epsilon")
})

# ---------------------------------------------------------------------------
# sas_triage — file-level rules 1-3
# ---------------------------------------------------------------------------

# A "Copy of *" file cannot be committed as a fixture: the space makes it a
# non-portable file name that R CMD check flags. So build it at runtime.
test_that("rule 1 drops 'Copy of' files", {
  d <- withr::local_tempdir()
  body <- c("%macro keep;", "  proc print; run;", "%mend keep;")
  writeLines(body, file.path(d, "keep.sas"))
  writeLines(body, file.path(d, "Copy of keep.sas"))

  res <- sas_triage(d)
  row <- res[res$file == "Copy of keep.sas", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 1L)
  expect_match(row$evidence, "filename-prefix duplicate")
})

# A "*.sas~" backup cannot be committed as a fixture: R CMD build strips
# tilde-suffixed files from the tarball, so it would be absent under
# R CMD check. Build it at runtime instead.
test_that("rule 2 drops editor backups", {
  d <- withr::local_tempdir()
  body <- c("%macro keep;", "  proc print; run;", "%mend keep;")
  writeLines(body, file.path(d, "keep.sas"))
  writeLines(body, file.path(d, "keep.sas~"))

  res <- sas_triage(d)
  row <- res[res$file == "keep.sas~", ]

  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 2L)
  expect_match(row$evidence, "editor backup")
})

test_that("rule 3 drops files failing lint, citing the failure", {
  res <- sas_triage(fx_dir())
  row <- res[res$file == "gamma_broken.sas", ]

  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 3L)
  expect_match(row$evidence, "unterminated string literal")
})

test_that("rule 3 drops nomend.sas without erroring the whole run", {
  res <- sas_triage(fx_dir())
  row <- res[res$file == "nomend.sas", ]

  expect_equal(row$decision, "drop")
  expect_equal(row$rule, 3L)
  expect_match(row$evidence, "%macro/%mend")
})

# ---------------------------------------------------------------------------
# sas_triage — definition-level rules 4-6
# ---------------------------------------------------------------------------

test_that("rule 4 marks a singly-defined macro canonical", {
  res <- sas_triage(fx_dir())
  row <- res[res$macro == "epsilon", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$decision, "canonical")
  expect_equal(row$rule, 4L)
})

test_that("rule 5 marks identical redefinitions canonical", {
  res <- sas_triage(fx_dir())
  rows <- res[res$macro == "delta", ]

  expect_equal(nrow(rows), 2L)
  expect_true(all(rows$decision == "canonical"))
  expect_true(all(rows$rule == 5L))
  expect_match(rows$evidence[1], "2 identical copies")
})

test_that("rule 6 REFUSES to decide on divergent redefinitions", {
  res <- sas_triage(fx_dir())
  rows <- res[res$macro == "zeta", ]

  expect_equal(nrow(rows), 2L)
  expect_true(all(rows$decision == "ambiguous"))
  expect_true(all(rows$rule == 6L))
  expect_false(any(rows$decision == "canonical"))
  expect_match(rows$evidence[1], "2 distinct bodies")
})

test_that("multi-macro files contribute one row per definition", {
  res <- sas_triage(fx_dir())
  rows <- res[res$file == "multi.sas", ]

  expect_equal(nrow(rows), 3L)
  expect_setequal(rows$macro, c("helper_one", "helper_two", "multi"))
})

test_that("uppercase %MACRO is triaged, not skipped", {
  res <- sas_triage(fx_dir())
  expect_true("upper" %in% res$macro)
})

test_that("sas_triage errors on a directory with no SAS source files", {
  d <- withr::local_tempdir()
  expect_error(sas_triage(d), "no SAS source files")
})

test_that("sas_triage errors if any definition is unclassified", {
  expect_error(
    hvtiRutilities:::.assert_no_unclassified(
      data.frame(macro = "x", decision = "unclassified",
                 stringsAsFactors = FALSE)
    ),
    "1 definition\\(s\\) unclassified"
  )
})

# ---------------------------------------------------------------------------
# sas_triage — overrides and idempotence
# ---------------------------------------------------------------------------

test_that("an override resolves an ambiguous macro", {
  ov <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(list(
    macro          = "zeta",
    canonical_file = "zeta.sas",
    rationale      = "zeta.sas uses the _FREQ_ automatic variable.",
    decided_by     = "JE",
    decided_on     = "2026-07-10"
  )), ov)

  res <- sas_triage(fx_dir(), overrides = ov)
  rows <- res[res$macro == "zeta", ]

  expect_equal(rows$decision[rows$file == "zeta.sas"], "canonical")
  expect_equal(rows$decision[rows$file == "zeta_old.sas"], "drop")
  expect_match(rows$evidence[rows$file == "zeta.sas"], "override")
})

test_that("sas_triage is idempotent", {
  a <- sas_triage(fx_dir())
  b <- sas_triage(fx_dir())

  expect_identical(a, b)
})

test_that("an override naming an unknown macro errors", {
  ov <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(list(
    macro = "does_not_exist", canonical_file = "nope.sas",
    rationale = "x", decided_by = "JE", decided_on = "2026-07-10"
  )), ov)

  expect_error(sas_triage(fx_dir(), overrides = ov), "does_not_exist")
})

# ---------------------------------------------------------------------------
# Subdirectory exclusions are recorded, not silently dropped
# ---------------------------------------------------------------------------

test_that(".scan_excluded_dirs counts .sas files in each subdirectory", {
  d <- withr::local_tempdir()
  writeLines("%macro top; %mend top;", file.path(d, "top.sas"))
  dir.create(file.path(d, "archive"))
  writeLines("%macro a; %mend a;", file.path(d, "archive", "a.sas"))
  writeLines("%macro b; %mend b;", file.path(d, "archive", "b.sas"))

  res <- hvtiRutilities:::.scan_excluded_dirs(d)

  expect_equal(nrow(res), 1L)
  expect_equal(res$directory, "archive")
  expect_equal(res$n_sas, 2L)
})

test_that("sas_triage attaches excluded directories as an attribute", {
  res <- sas_triage(fx_dir())
  ex <- attr(res, "excluded_dirs")

  expect_s3_class(ex, "data.frame")
  expect_true(all(c("directory", "n_sas") %in% names(ex)))
})
