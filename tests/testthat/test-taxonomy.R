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

test_that("the imputation prefixes are pinned by prefix, name and folder", {
  # The general checks above -- shape, uniqueness, nonempty descriptions --
  # all still pass if `si` or `mi` is removed, renamed, or refiled under the
  # wrong folder. So they are pinned here explicitly.
  #
  # Two prefixes and not one is the decision being pinned, not an accident of
  # how the table was written: 223 studies call single mean imputation, 326
  # call multiple imputation, and 18 call both, so one prefix could not label
  # those 18 unambiguously. `mi` is acceptable only PAIRED with `si` -- alone
  # it reads as multiple imputation to a statistician and would misname the
  # single-imputation job. A future edit that collapses the two, or that keeps
  # `mi` and drops `si`, is exactly what this test exists to stop.
  #
  # Renaming either also needs a permanent legacy alias map, since these
  # prefixes classify 423,269 legacy SAS files. Failing here is the prompt to
  # go and write it, not to update the expectation.
  tx <- hvti_taxonomy()

  expect_true(all(c("si", "mi") %in% tx$prefix))

  si <- tx[match("si", tx$prefix), ]
  expect_equal(si$name, "Single imputation")
  expect_equal(si$folder, "datasets")
  expect_true(nzchar(si$description))

  mi <- tx[match("mi", tx$prefix), ]
  expect_equal(mi$name, "Multiple imputation")
  expect_equal(mi$folder, "datasets")
  expect_true(nzchar(mi$description))
})

test_that("`si` and `mi` are two rows, not one prefix wearing two names", {
  # Guards the failure the pairing exists to prevent: a single imputation
  # prefix serving both methods.
  tx <- hvti_taxonomy()
  imputation <- tx[tx$prefix %in% c("si", "mi"), ]

  expect_equal(nrow(imputation), 2L)
  expect_equal(sort(imputation$prefix), c("mi", "si"))
  expect_false(imputation$name[1] == imputation$name[2])
})

test_that("the datasets folder holds the prefixes it is expected to", {
  # `vars` keeps its imputation wording on purpose -- it is the job that
  # enhances a dataset with temp vars, imputations and propensity terms
  # together, and porting vars.sas found mean imputation across 394 variables
  # inside it. `si` and `mi` name jobs whose whole purpose is imputation. This
  # pins the set so a later cleanup cannot quietly move one out.
  tx <- hvti_taxonomy()
  expect_setequal(tx$prefix[tx$folder == "datasets"],
                  c("bd", "vars", "dt", "si", "mi"))
})
