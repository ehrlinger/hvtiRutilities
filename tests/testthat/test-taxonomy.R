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

test_that("every fold leaves a dropped prefix for a taxonomy prefix", {
  # pm left the taxonomy on 2026-09-13, folded into lm. A fold whose name is
  # still in the taxonomy would count one prefix under two; a fold into a
  # prefix the taxonomy lacks would make the census call it unknown.
  folds <- hvti_prefix_folds()
  tx <- hvti_taxonomy()$prefix
  expect_identical(folds, c(pm = "lm"))
  expect_false(any(names(folds) %in% tx))
  expect_true(all(folds %in% tx))
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

test_that("the relabelled non-linear and boosting rows are pinned", {
  # A biostatistician's review of the job catalog, 2026-09-11, relabelled
  # these five: bn, nd, nm and np are non-linear, not non-parametric, and nb
  # holds boosting models, not notebooks. The shape checks above still pass
  # if one is reverted or relabelled halfway, so names and descriptions are
  # pinned here.
  tx <- hvti_taxonomy()
  want <- list(
    bn = c("Bootstrap non-linear",
           "bootstrap confidence intervals for non-linear estimates"),
    nd = c("Non-linear distributions",
           "distribution estimates stratified by group"),
    nm = c("Non-linear model", "non-linear regression models"),
    np = c("Non-linear plot", "non-linear distribution figures"),
    nb = c("Boosting", "boosting models (Boostmtree, BoostMLR)")
  )
  for (p in names(want)) {
    row <- tx[match(p, tx$prefix), ]
    expect_equal(row$name, want[[p]][[1]], label = p)
    expect_equal(row$description, want[[p]][[2]], label = p)
  }
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

test_that("the random forest family is the three outcome rows plus sid and vt", {
  # The family splits on the OUTCOME axis. Pinning the set catches the two
  # ways it can regress: a fourth outcome row appearing without a spec, and
  # `rfr`, `sid` or `vt` being dropped back out while the job catalog still
  # carries rows for them -- which would fail hvtiRtemplates' direction-one
  # guard in a different repository, far from the edit that caused it.
  tx <- hvti_taxonomy()
  forest <- tx$prefix[grepl("^(rf|sid|vt)", tx$prefix) & !is.na(tx$prefix)]
  expect_setequal(forest, c("rf", "rfsrc", "rfs", "rfc", "rfr", "sid", "vt"))
  expect_true(all(tx$folder[match(c("rfs", "rfc", "rfr", "sid", "vt"),
                                  tx$prefix)] == "analyses"))
})

test_that("the outcome rows name their outcome and the umbrellas say so", {
  # `rfc` and `rfs` described themselves as "reporting" until 2026-09-17,
  # which tangled the fit-versus-report axis into a family that splits on
  # outcome. `rf` and `rfsrc` described the same set as each other on the
  # package axis. Both are pinned because the shape checks above pass either
  # way, and a revert to the package axis is exactly the regression the
  # outcome split exists to prevent.
  tx <- hvti_taxonomy()
  want <- list(
    rfs = c("Random forest survival", "random forest, survival outcome"),
    rfc = c("Random forest classifier", "random forest, classification outcome"),
    rfr = c("Random forest regression", "random forest, regression outcome"),
    sid = c("Random forest clustering",
            "unsupervised sidClustering forest with PAM over K"),
    vt = c("Virtual twins",
           "per-arm forests, swapped-arm prediction, RMST difference")
  )
  for (p in names(want)) {
    row <- tx[match(p, tx$prefix), ]
    expect_equal(row$name, want[[p]][[1]], label = p)
    expect_equal(row$description, want[[p]][[2]], label = p)
  }

  # Both umbrella rows must SAY they are umbrellas, in the name as well as the
  # description. Marking only `rf` left `rfsrc` reading as an ordinary
  # analysis row, and `rfsrc` is the larger legacy corpus of the two.
  umbrella <- tx[match(c("rf", "rfsrc"), tx$prefix), ]
  expect_true(all(grepl("(umbrella)", umbrella$name, fixed = TRUE)))
  expect_true(all(grepl("legacy umbrella", umbrella$description, fixed = TRUE)))

  # And they must stay DISTINGUISHABLE. Identical descriptions would discard
  # the one thing the table still records about them: which spelling a legacy
  # job used. `rf` is the generic name, `rfsrc` the package's.
  expect_false(umbrella$description[1] == umbrella$description[2])
  expect_match(umbrella$description[1], "generic spelling")
  expect_match(umbrella$description[2], "package spelling")
})

test_that("the umbrella prefixes stay in the table and out of the fold map", {
  # Demotion means "never templated", not "deleted". The rows stay so a census
  # can resolve the corpus that uses them -- rfsrc alone is 131 studies. And
  # they must NOT be folded: a fold is one-to-one, rfsrc spans all three
  # outcomes, so any fold added here would silently pick one and miscount the
  # other two.
  tx <- hvti_taxonomy()
  expect_true(all(c("rf", "rfsrc") %in% tx$prefix))
  expect_false(any(c("rf", "rfsrc") %in% names(hvti_prefix_folds())))
  expect_false(any(c("rf", "rfsrc") %in% hvti_non_prefixes()))
})
