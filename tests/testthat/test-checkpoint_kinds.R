test_that("the base vocabulary has the twelve API rows", {
  root <- withr::local_tempdir()
  kinds <- .cp_kinds(root)
  expect_equal(nrow(kinds), 12L)
  expect_true(all(c("workspace_created", "manuscript_submitted",
                    "manuscript_published") %in% kinds$kind))
  expect_false(kinds$numbered[kinds$kind == "workspace_created"])
  expect_equal(kinds$trigger[kinds$kind == "data_received"], "auto")
})

test_that("an unknown kind errors and lists the valid kinds", {
  root <- withr::local_tempdir()
  expect_error(.cp_kind_check(.cp_kinds(root), "manuscript", "study_checkpoint"),
               "unknown checkpoint kind 'manuscript'.*manuscript_submitted")
})

test_that("the live cache adds kinds and overrides base rows", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, ".checkpoint"))
  yaml::write_yaml(
    list(list(kind = "adhoc", trigger = "manual"),
         list(kind = "abstract_accepted", retired = TRUE)),
    file.path(root, ".checkpoint", "kinds.yml")
  )
  kinds <- .cp_kinds(root)
  expect_true("adhoc" %in% kinds$kind)
  expect_equal(nrow(.cp_kind_check(kinds, "adhoc", "f")), 1L)
  expect_error(.cp_kind_check(kinds, "abstract_accepted", "f"), "is retired")
})
