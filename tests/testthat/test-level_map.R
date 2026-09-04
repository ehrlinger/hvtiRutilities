# What stripping would do, across a dataset. See
# dev/specs/2026-09-02-label-length-and-fallback-design.md section 6.1.
#
# Deliberately mirrors label_map()'s shape: level / level_full / stripped
# reads the same way as label / label_full / truncated, one level down.

test_that("level_map returns the documented shape", {
  d <- data.frame(disp = factor(c("1. Home", "2. Rehab")))

  result <- level_map(d)

  expect_s3_class(result, "data.frame")
  expect_named(result, c("key", "code", "level", "level_full", "stripped"))
})

test_that("a factor contributes one row per level, in level order", {
  d <- data.frame(disp = factor(c("1. Home", "2. Rehab", "1. Home")))

  result <- level_map(d)

  expect_equal(nrow(result), 2L)
  expect_equal(result$key, c("disp", "disp"))
  expect_equal(result$level_full, c("1. Home", "2. Rehab"))
  expect_equal(result$level, c("Home", "Rehab"))
  expect_true(all(result$stripped))
})

test_that("codes come from value labels when the column carries them", {
  d <- data.frame(
    disp = haven::labelled(c(1, 2), c(`1. Home` = 1, `2. Rehab` = 2))
  )

  result <- level_map(d)

  expect_equal(result$code, c("1", "2"))
  expect_equal(result$level, c("Home", "Rehab"))
})

test_that("a factor's codes are its integer level positions", {
  d <- data.frame(g = factor(c("1. A", "2. B")))

  expect_equal(level_map(d)$code, c("1", "2"))
})

test_that("a character column has no codes", {
  d <- data.frame(g = c("1. A", "2. B"), stringsAsFactors = FALSE)

  result <- level_map(d)

  expect_true(all(is.na(result$code)))
  expect_equal(result$level, c("A", "B"))
})

test_that("an unstripped level is reported with stripped FALSE", {
  d <- data.frame(v = factor(c("1 vessel", "2 vessel disease")))

  result <- level_map(d)

  expect_equal(result$level, result$level_full)
  expect_false(any(result$stripped))
})

test_that("plain numeric and logical columns contribute no rows", {
  d <- data.frame(age = c(51, 63), flag = c(TRUE, FALSE))

  expect_equal(nrow(level_map(d)), 0L)
})

test_that("a frame with nothing discrete still returns the columns", {
  result <- level_map(data.frame(age = c(51, 63)))

  expect_named(result, c("key", "code", "level", "level_full", "stripped"))
  expect_equal(nrow(result), 0L)
})

test_that("vars selects the columns to report", {
  d <- data.frame(a = factor(c("1. x", "2. y")), b = factor("3. z"))

  expect_equal(unique(level_map(d, vars = "a")$key), "a")
})

test_that("an unknown variable is an error, not a silent empty result", {
  d <- data.frame(a = factor("1. x"))

  expect_error(level_map(d, vars = "nope"), "nope")
})

test_that("a high-cardinality column is skipped and named", {
  d <- data.frame(id = as.character(1:50), stringsAsFactors = FALSE)

  expect_warning(result <- level_map(d, max_levels = 20L), "id")
  expect_equal(nrow(result), 0L)
})

test_that("max_levels is validated", {
  d <- data.frame(a = factor("1. x"))

  expect_error(level_map(d, max_levels = 0), "max_levels")
  expect_error(level_map(d, max_levels = "20"), "max_levels")
})

test_that("a collision is reported and the levels keep their prefixes", {
  d <- data.frame(g = factor(c("1. Yes", "2. Yes")))

  expect_warning(result <- level_map(d), "collide|collision")
  expect_equal(result$level, c("1. Yes", "2. Yes"))
  expect_false(any(result$stripped))
})

test_that("level_map does not modify the data it was given", {
  d <- data.frame(g = factor(c("01 home", "02 rehab")))
  before <- levels(d$g)

  level_map(d)

  expect_equal(levels(d$g), before)
})

test_that("it composes with apply_value_labels", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c("disp:", "  1: 1. Home", "  2: 2. Rehab"), tmp)
  d <- apply_value_labels(data.frame(disp = c(1, 2)), tmp)

  result <- level_map(d)

  expect_equal(result$code, c("1", "2"))
  expect_equal(result$level, c("Home", "Rehab"))
  expect_equal(result$level_full, c("1. Home", "2. Rehab"))
})

test_that("data must be a data frame", {
  expect_error(level_map(1:3), "data frame")
})
