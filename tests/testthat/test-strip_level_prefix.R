# Leading-code prefixes on level text. See
# dev/specs/2026-09-02-label-length-and-fallback-design.md sections 6 and 6.1.
#
# The rule requires a separator. A bare digit-then-space rule turns "1 vessel
# disease", "2 vessel" and "3 vessel" into two identical strings; nothing
# errors, a downstream table() merges them, and the failure presents as data
# rather than as a bug. A missed strip is visible in the output; a wrong strip
# is silent. The rule is biased accordingly.

test_that("a separator-delimited prefix is stripped", {
  expect_equal(strip_level_prefix("1. Yes"), "Yes")
  expect_equal(strip_level_prefix("0 = No"), "No")
  expect_equal(strip_level_prefix("01 - home"), "home")
  expect_equal(strip_level_prefix("2) Rehab"), "Rehab")
  expect_equal(strip_level_prefix("3: SNF"), "SNF")
})

test_that("a bare digit-then-space is left alone", {
  vessels <- c("1 vessel disease", "2 vessel", "3 vessel")

  expect_equal(strip_level_prefix(vessels), vessels)
})

test_that("the documented cost: unpunctuated 0 No / 1 Yes survive", {
  expect_equal(strip_level_prefix(c("0 No", "1 Yes")), c("0 No", "1 Yes"))
})

test_that("a range is not mistaken for a prefix and a separator", {
  # "1-2 vessels" matches leading-integer-then-hyphen, and stripping it
  # yields "2 vessels" -- silently colliding with a real "2 vessels" level.
  # The remainder starting with a digit is the tell.
  ranges <- c("1-2 vessels", "0-1 day", "2 - 3 units")

  expect_equal(strip_level_prefix(ranges), ranges)
})

test_that("stripping never produces an empty string", {
  expect_equal(strip_level_prefix(c("1.", "0 =", "12 -")),
               c("1.", "0 =", "12 -"))
})

test_that("text with no leading integer is untouched", {
  x <- c("Home", "Rehab", "-1 = Unknown", "N/A", "")

  expect_equal(strip_level_prefix(x), x)
})

test_that("a factor is read through its levels", {
  f <- factor(c("1. Yes", "0. No", "1. Yes"))

  expect_equal(strip_level_prefix(f), c("No", "Yes"))
})

test_that("NA level text survives as NA", {
  expect_equal(strip_level_prefix(c("1. Yes", NA)), c("Yes", NA))
})

test_that("a collision reverts both members rather than merging them", {
  # This is the failure the separator rule exists to prevent, arriving by a
  # different door: two distinct codes with the same text.
  x <- c("1. Yes", "2. Yes", "3. No")

  expect_warning(out <- strip_level_prefix(x), "collide|collision")
  expect_equal(out, c("1. Yes", "2. Yes", "No"))
  expect_equal(length(unique(out)), 3L)
})

test_that("a collision with an already-unprefixed level also reverts", {
  x <- c("Yes", "1. Yes")

  expect_warning(out <- strip_level_prefix(x), "Yes")
  expect_equal(out, c("Yes", "1. Yes"))
})

test_that("the warning names the colliding text", {
  expect_warning(strip_level_prefix(c("1. Yes", "2. Yes")), "Yes")
})

test_that("stripping is elementwise and length-preserving for characters", {
  x <- c("1. A", "B", "2 = C")

  expect_equal(length(strip_level_prefix(x)), 3L)
  expect_equal(strip_level_prefix(x), c("A", "B", "C"))
})

test_that("input is validated", {
  expect_error(strip_level_prefix(list(1)), "character")
  expect_error(strip_level_prefix(NULL), "character")
})

test_that("it does not mutate the factor it was given", {
  # Section 6.1: stripping is a display operation and never rewrites stored
  # level text, which is what keeps the ordinal note's order-in-the-level-name
  # option available.
  f <- factor(c("01 home", "02 rehab"))
  before <- levels(f)

  strip_level_prefix(f)

  expect_equal(levels(f), before)
})
