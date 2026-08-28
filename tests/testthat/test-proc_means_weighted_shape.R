library(testthat)
library(hvtiRutilities)

cs <- function(x, stat, w = NULL) hvtiRutilities:::.compute_stat(x, stat, w)

# ---------------------------------------------------------------------------
# KNOWN VALIDATION GAP -- see dev/specs/2026-08-14-proc-means-unistats-design.md
#
# e1071 takes no weights, so the WEIGHTED forms of skewness and kurtosis have no
# independent oracle available today. The expected values below are computed
# from the SAS documented formulas -- weights raised to 3/2 for skewness and
# squared for kurtosis -- and are pinned here to catch drift, NOT to prove SAS
# agreement. Confirm them against the Phase 1 SAS oracle when it exists.
#
# The UNWEIGHTED forms are cross-validated against e1071 in
# tests/testthat/test-proc_means_shape.R and are not affected by this gap.
# ---------------------------------------------------------------------------

v <- c(1, 2, 3, 4, 8)
w <- c(1, 1, 2, 4, 2)

# The expected values below are FROZEN LITERALS, not expressions recomputed
# from the same formula the implementation uses. A test that recomputes the
# formula silently follows any edit to it and so cannot detect drift; a frozen
# number breaks loudly. These were computed once from the SAS documented
# formulas for v and w above:
#   sum(w) = 10, xbar_w = 4.1, s_w = sqrt(sum(w*(v-xbar_w)^2)/(n-1)) = 3.4241787337
# They pin the current arithmetic against accidental change. They do NOT
# establish SAS agreement -- see the gap notice at the top of this file.

test_that("weighted skewness is stable at its documented value", {
  expect_equal(cs(v, "skewness", w), 1.2967986106, tolerance = 1e-8)
})

test_that("weighted kurtosis is stable at its documented value", {
  expect_equal(cs(v, "kurtosis", w), 1.4838139488, tolerance = 1e-8)
})

test_that("weighted skewness and kurtosis actually respond to the weights", {
  # Guards the w^(3/2) and w^2 exponents. At w = 1 both collapse to 1, so an
  # equal-weights test cannot distinguish a correct weighting from none at all.
  expect_false(isTRUE(all.equal(cs(v, "skewness", w), cs(v, "skewness"))))
  expect_false(isTRUE(all.equal(cs(v, "kurtosis", w), cs(v, "kurtosis"))))
})

test_that("weighted skewness and kurtosis honour the minimum-n rules", {
  expect_true(is.na(cs(c(1, 2), "skewness", c(1, 2))))
  expect_true(is.na(cs(c(1, 2, 3), "kurtosis", c(1, 2, 3))))
})

test_that("weighted skewness and kurtosis are NA for a constant column", {
  k <- rep(4, 8)
  kw <- c(1, 2, 1, 2, 1, 2, 1, 2)
  expect_true(is.na(cs(k, "skewness", kw)))
  expect_true(is.na(cs(k, "kurtosis", kw)))
  expect_false(is.nan(cs(k, "skewness", kw)))
  expect_false(is.nan(cs(k, "kurtosis", kw)))
})
