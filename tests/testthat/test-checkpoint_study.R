test_that("st_id falls back to study_tracker_id", {
  root <- withr::local_tempdir()
  yaml::write_yaml(list(study = "S", study_tracker_id = 1267L),
                   file.path(root, "_study.yml"))
  s <- .cp_study(root, "f")
  expect_identical(s$st_id, 1267L)
  expect_null(s$workspace_id)
  expect_true(s$verified)
  expect_null(s$remote)
  expect_identical(s$include, character(0))
})

test_that("st_id wins, and checkpoint keys and verification are read", {
  root <- withr::local_tempdir()
  yaml::write_yaml(
    list(st_id = 42L, study_tracker_id = 1L, workspace_id = "ws-1",
         identity_verified = FALSE,
         checkpoint = list(remote = "https://example.org/r.git",
                           include = list("*.txt", "30_analyses/**/*.inc"))),
    file.path(root, "_study.yml")
  )
  s <- .cp_study(root, "f")
  expect_identical(s$st_id, 42L)
  expect_equal(s$workspace_id, "ws-1")
  expect_false(s$verified)
  expect_equal(s$remote, "https://example.org/r.git")
  expect_equal(s$include, c("*.txt", "30_analyses/**/*.inc"))
})

test_that("a missing _study.yml or ST number is an error", {
  root <- withr::local_tempdir()
  expect_error(.cp_study(root, "study_checkpoint"), "no _study.yml")
  yaml::write_yaml(list(study = "S"), file.path(root, "_study.yml"))
  expect_error(.cp_study(root, "study_checkpoint"), "no valid st_id")
})

test_that("an include pattern that leaves the study root is an error", {
  root <- withr::local_tempdir()
  for (bad in c("../x.R", "30_analyses/../../x.R", "/etc/passwd", "~/x.R",
                "C:/x.R", "..\\x.R")) {
    yaml::write_yaml(list(st_id = 1L, checkpoint = list(include = list(bad))),
                     file.path(root, "_study.yml"))
    expect_error(.cp_study(root, "study_checkpoint"),
                 paste0("include pattern '", bad, "'"), fixed = TRUE)
  }
})

test_that("a remote URL carrying a password is an error that does not echo it", {
  root <- withr::local_tempdir()
  for (bad in c("https://analyst:s3cret@dev.azure.com/org/p/_git/r",
                "ssh://git:s3cret@host.example.org:22/r.git",
                "http://:s3cret@host/r.git")) {
    yaml::write_yaml(list(st_id = 1L, checkpoint = list(remote = bad)),
                     file.path(root, "_study.yml"))
    err <- expect_error(.cp_study(root, "study_checkpoint"),
                        "remote URL must not carry a password")
    expect_no_match(conditionMessage(err), "s3cret")
  }
  for (good in c("git@ssh.dev.azure.com:v3/org/p/r",
                 "https://dev.azure.com/org/p/_git/r",
                 "https://analyst@dev.azure.com/org/p/_git/r",
                 "ssh://git@host.example.org:22/r.git")) {
    yaml::write_yaml(list(st_id = 1L, checkpoint = list(remote = good)),
                     file.path(root, "_study.yml"))
    expect_equal(.cp_study(root, "study_checkpoint")$remote, good)
  }
})
