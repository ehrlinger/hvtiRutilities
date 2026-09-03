# label_max on the display seam. See
# dev/specs/2026-09-02-label-length-and-fallback-design.md section 4.
#
# Truncation is a view, not a change to the data: label_map() caps the label
# it prints and keeps the source text in label_full, so a caller that wants
# the whole thing can still have it. dataset_schema() never gains this
# parameter -- it records the label as the source carried it.

lab <- function(text, var = "v") {
  d <- data.frame(v = 1)
  names(d) <- var
  labelled::var_label(d[[var]]) <- text
  d
}

test_that("label_map reports the cap and the source text", {
  result <- label_map(lab("Age at operation (years)"))

  expect_named(result, c("key", "label", "label_full", "truncated"))
})

test_that("a label inside the cap is returned unchanged", {
  txt <- "Age at operation (years)"

  result <- label_map(lab(txt), label_max = 40)

  expect_equal(result$label, txt)
  expect_equal(result$label_full, txt)
  expect_false(result$truncated)
})

test_that("a label exactly at the cap is not truncated", {
  txt <- strrep("a", 40)

  result <- label_map(lab(txt), label_max = 40)

  expect_equal(result$label, txt)
  expect_false(result$truncated)
})

test_that("an over-long label breaks on a word boundary and is marked", {
  txt <- "Ascending aorta only versus ascending plus arch"

  result <- label_map(lab(txt), label_max = 40)

  expect_equal(result$label, "Ascending aorta only versus ascending...")
  expect_equal(nchar(result$label), 40)
  expect_equal(result$label_full, txt)
  expect_true(result$truncated)
})

test_that("the cut never exceeds label_max", {
  txt <- "Ascending aorta only versus ascending plus arch"

  for (n in 8:46) {
    got <- label_map(lab(txt), label_max = n)$label
    expect_lte(nchar(got), n)
  }
})

test_that("a word longer than the cap is hard-broken", {
  txt <- strrep("z", 60)

  result <- label_map(lab(txt), label_max = 40)

  expect_equal(result$label, paste0(strrep("z", 37), "..."))
  expect_true(result$truncated)
})

test_that("the marker is not left dangling on a separator", {
  txt <- "Ascending aorta only, versus ascending plus arch"

  result <- label_map(lab(txt), label_max = 30)

  expect_false(grepl("[[:space:]]\\.\\.\\.$", result$label))
  expect_lte(nchar(result$label), 30)
})

test_that("Inf and NA disable truncation", {
  txt <- strrep("a", 200)

  for (off in list(Inf, NA, NA_real_)) {
    result <- label_map(lab(txt), label_max = off)
    expect_equal(result$label, txt)
    expect_equal(result$label_full, txt)
    expect_false(result$truncated)
  }
})

test_that("label_max is validated", {
  expect_error(label_map(lab("x"), label_max = 0), "label_max")
  expect_error(label_map(lab("x"), label_max = -1), "label_max")
  expect_error(label_map(lab("x"), label_max = "40"), "label_max")
  expect_error(label_map(lab("x"), label_max = c(10, 20)), "label_max")
})

test_that("truncated labels are discoverable by filtering the map", {
  d <- data.frame(age = 1, approach = 2)
  labelled::var_label(d$age) <- "Age at operation (years)"
  labelled::var_label(d$approach) <-
    "Ascending aorta only versus ascending plus arch"

  cut <- subset(label_map(d, label_max = 40), truncated)

  expect_equal(cut$key, "approach")
  expect_equal(nrow(cut), 1)
})

test_that("dataset_schema does not truncate and takes no label_max", {
  txt <- "Ascending aorta only versus ascending plus arch"

  expect_error(dataset_schema(lab(txt), label_max = 40), "label_max")
  expect_equal(dataset_schema(lab(txt))$label, txt)
})

test_that("an override on a label map keeps label_full honest", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(
    "approach: 'Ascending aorta only versus ascending plus arch'", tmp
  )

  lmap <- label_map(lab("Approach", var = "approach"), label_max = 40)
  lmap <- apply_label_overrides(lmap, overrides_file = tmp)

  expect_equal(lmap$label_full,
               "Ascending aorta only versus ascending plus arch")
  expect_equal(lmap$label, "Ascending aorta only versus ascending...")
  expect_true(lmap$truncated)
})
