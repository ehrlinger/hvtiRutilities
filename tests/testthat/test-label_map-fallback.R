# The variable-name fallback, and its exemption from label_max. See
# dev/specs/2026-09-02-label-length-and-fallback-design.md sections 2.1
# and 4.1.
#
# The fallback is deliberate: a bare variable name on a draft figure is the
# signal that a label is missing, and it fails visibly. These tests exist to
# stop a well-meant change from prettifying it, and to stop label_max from
# truncating it into something that is neither a label nor a name.

test_that("an unlabelled variable falls back to its own name, verbatim", {
  dta <- data.frame(preop_creatinine_clearance = 1, hgb_bs = 2)

  result <- suppressWarnings(label_map(dta))

  expect_equal(result$label,
               c("preop_creatinine_clearance", "hgb_bs"))
})

test_that("the fallback does not prettify the variable name", {
  dta <- data.frame(hgb_bs = 1, age_at_op = 2, LVEFvs_b = 3)

  labels <- suppressWarnings(label_map(dta))$label

  # No title casing, no underscore expansion, no acronym rewriting.
  expect_false(any(grepl(" ", labels, fixed = TRUE)))
  expect_equal(labels, names(dta))
})

test_that("a variable name longer than label_max is not truncated", {
  nm <- "preop_creatinine_clearance_calculated"
  dta <- data.frame(x = 1)
  names(dta) <- nm

  result <- suppressWarnings(label_map(dta, label_max = 40))

  expect_gt(nchar(nm), 35)
  expect_equal(result$label, nm)
  expect_equal(result$label_full, nm)
  expect_false(result$truncated)
})

test_that("a filled name is exempt even when far over the cap", {
  nm <- paste(rep("verylongsegment", 4), collapse = "_")
  dta <- data.frame(x = 1)
  names(dta) <- nm

  result <- suppressWarnings(label_map(dta, label_max = 10))

  expect_equal(result$label, nm)
  expect_false(result$truncated)
})

test_that("a real label at the same length is truncated", {
  # The pair that makes the exemption observable: identical text, capped
  # when it is a label and passed through when it stands in for one.
  txt <- "preop_creatinine_clearance_calculated"

  as_name <- data.frame(x = 1)
  names(as_name) <- txt

  as_label <- data.frame(v = 1)
  labelled::var_label(as_label$v) <- txt

  expect_false(suppressWarnings(label_map(as_name, label_max = 20))$truncated)
  expect_true(label_map(as_label, label_max = 20)$truncated)
})
