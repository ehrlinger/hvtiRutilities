library(testthat)
library(hvtiRutilities)

test_that("hvti_taxonomy() has the expected shape", {
  tx <- hvti_taxonomy()
  expect_s3_class(tx, "data.frame")
  expect_named(tx, c("prefix", "name", "folder", "description"))
  expect_gt(nrow(tx), 25)
  expect_false(any(duplicated(tx$prefix)))
  expect_true(all(nzchar(tx$description)))
})

test_that("the taxonomy and the non-prefix list are disjoint", {
  expect_equal(intersect(hvti_taxonomy()$prefix, hvti_non_prefixes()),
               character(0))
})

test_that("exactly the artifact-kind rows have an NA prefix", {
  # `folder` names two things: for most rows it is an analysis type's home
  # folder, matched to a real prefix; `estimates` is an artifact kind with no
  # analysis that produces it, so its prefix is NA. This pins that mapping
  # down explicitly -- without it, a future row could pick up an NA prefix by
  # typo, or a real prefix could silently go missing, and nothing here would
  # notice.
  tx <- hvti_taxonomy()
  artifact_kind_folders <- c("estimates")
  expect_equal(is.na(tx$prefix), tx$folder %in% artifact_kind_folders)
})
