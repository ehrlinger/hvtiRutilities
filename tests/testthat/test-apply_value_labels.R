# The enumerated-levels declaration. See
# dev/specs/2026-09-02-label-length-and-fallback-design.md section 5, input 2,
# and 2026-09-02-ordinal-representation-design.md section 8.
#
# There are no .sas7bcat catalogues in the study corpus (data managers,
# 2026-09-03), so this file is not a supplement to the catalogue -- it is the
# only source of code-to-text mappings. The declaration is written into
# labelled::val_labels(), the same slot a catalogue would have filled, so
# r_data_types(use_value_labels = TRUE) consumes it without a second path.

yml <- function(...) {
  tmp <- tempfile(fileext = ".yml")
  writeLines(c(...), tmp)
  tmp
}

test_that("a declaration lands in val_labels", {
  f <- yml("disp:", "  1: Home", "  2: Rehab", "  3: SNF")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(disp = c(1, 2, 1, 3))

  out <- apply_value_labels(d, f)

  expect_equal(labelled::val_labels(out$disp),
               c(Home = 1, Rehab = 2, SNF = 3))
})

test_that("the declaration reaches r_data_types(use_value_labels = TRUE)", {
  f <- yml("disp:", "  1: Home", "  2: Rehab", "  3: SNF")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(disp = c(1, 2, 1, 3))

  out <- r_data_types(apply_value_labels(d, f), use_value_labels = TRUE)

  expect_s3_class(out$disp, "factor")
  expect_equal(as.character(out$disp), c("Home", "Rehab", "Home", "SNF"))
})

test_that("eight enumerated options survive that a 40-char label cannot", {
  f <- yml(
    "approach:",
    "  1: Ascending aorta only",
    "  2: Ascending aorta plus arch",
    "  3: Ascending aorta plus hemiarch"
  )
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(approach = c(1, 3, 2))

  out <- apply_value_labels(d, f)

  expect_equal(names(labelled::val_labels(out$approach)),
               c("Ascending aorta only",
                 "Ascending aorta plus arch",
                 "Ascending aorta plus hemiarch"))
})

test_that("the declaration does not touch the display label", {
  f <- yml("disp:", "  1: Home", "  2: Rehab")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(disp = c(1, 2))
  labelled::var_label(d$disp) <- "Discharge disposition"

  out <- apply_value_labels(d, f)

  expect_equal(labelled::var_label(out$disp), "Discharge disposition")
  expect_equal(label_map(out)$label, "Discharge disposition")
})

test_that("a missing file returns the data unchanged", {
  d <- data.frame(disp = c(1, 2))

  expect_equal(apply_value_labels(d, tempfile(fileext = ".yml")), d)
})

test_that("an empty file returns the data unchanged", {
  f <- yml("")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(disp = c(1, 2))

  expect_equal(apply_value_labels(d, f), d)
})

test_that("character codes label a character column", {
  f <- yml("sex:", "  M: Male", "  F: Female")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(sex = c("M", "F", "M"), stringsAsFactors = FALSE)

  out <- apply_value_labels(d, f)

  expect_equal(labelled::val_labels(out$sex), c(Male = "M", Female = "F"))
})

test_that("a variable not in the data is reported, not ignored", {
  f <- yml("disp:", "  1: Home", "typo_var:", "  1: Yes")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(disp = 1)

  expect_warning(apply_value_labels(d, f), "typo_var")
})

test_that("an existing val_labels wins and the override is reported", {
  # Priority order from section 5: value labels on the column first, the
  # declaration second. A catalogue is not silently overwritten by a file.
  f <- yml("disp:", "  1: House", "  2: Rehabilitation")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(disp = haven::labelled(c(1, 2), c(Home = 1, Rehab = 2)))

  expect_warning(out <- apply_value_labels(d, f), "disp")
  expect_equal(labelled::val_labels(out$disp), c(Home = 1, Rehab = 2))
})

test_that("ordered is reserved and refused rather than half-implemented", {
  f <- yml("severity:", "  levels:", "    1: Mild", "  ordered: true")
  on.exit(unlink(f), add = TRUE)
  d <- data.frame(severity = 1)

  expect_error(apply_value_labels(d, f), "ordered")
})

test_that("value_labels_file must be a single path", {
  d <- data.frame(disp = 1)

  expect_error(apply_value_labels(d, c("a.yml", "b.yml")),
               "value_labels_file")
  expect_error(apply_value_labels(d, 42), "value_labels_file")
})

test_that("data must be a data frame", {
  expect_error(apply_value_labels(1:3), "data frame")
})
