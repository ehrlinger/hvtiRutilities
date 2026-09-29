# study_abbreviations(), add_abbreviation() and the abbreviations: block of
# _study.yml. Design: dev/specs/2026-09-25-study-abbreviations-design.md.

# A study fixture whose _study.yml carries `abbreviations`, as YAML would
# write it: NULL stands for `~`.
abbrev_study <- function(abbreviations = NULL, .env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = .env)
  # make_study_fixture() is defined in helper-study.R, which lintr does not load.
  make_study_fixture(dir) # nolint: object_usage_linter.
  if (!is.null(abbreviations)) {
    raw <- yaml::read_yaml(file.path(dir, "_study.yml"))
    raw$abbreviations <- abbreviations
    yaml::write_yaml(raw, file.path(dir, "_study.yml"))
  }
  dir
}
defaults <- c("Left ventricular" = "LV", "Ejection fraction" = "EF")
local_defaults <- function(value = defaults, .env = parent.frame()) {
  testthat::local_mocked_bindings(.abbreviation_defaults = function() value, .env = .env)
}

test_that("the shipped default list passes the list rules", {
  path <- system.file("extdata", "abbreviations.yml", package = "hvtiRutilities")
  expect_true(nzchar(path))
  raw <- yaml::read_yaml(path)
  expect_true(is.list(raw) || is.null(raw))
  expect_silent(defaults <- .abbreviation_defaults())
  expect_type(defaults, "list")
  expect_length(.abbreviation_problems(defaults, "default", allow_null = FALSE), 0L)
})

test_that("a malformed default entry is reported, not coerced", {
  bad <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("Aortic valve: [AV, A]", "Year of operation: 2020"), bad)
  problems <- .abbreviation_problems(.abbreviation_defaults(bad), "default", allow_null = FALSE)
  expect_length(problems, 2L)
  expect_match(problems[1], "Aortic valve' \\(default\\)")
  expect_match(problems[2], "Year of operation' \\(default\\)")
})

test_that("a study with no abbreviations key gets the default list", {
  local_defaults()
  cfg <- study_config(abbrev_study())
  out <- study_abbreviations(cfg)
  expect_identical(as.vector(out), unname(defaults))
  expect_identical(names(out), names(defaults))
  expect_identical(attr(out, "source"), c("default", "default"))
})

test_that("a study adds to, overrides and removes defaults, phrases compared ignoring case", {
  local_defaults()
  cfg <- study_config(abbrev_study(list(`Surgical procedure` = "SP", `left ventricular` = "LVent",
                                        `Ejection fraction` = NULL)))
  out <- study_abbreviations(cfg)
  expect_identical(out[["Surgical procedure"]], "SP")
  expect_identical(out[["left ventricular"]], "LVent")
  expect_false(any(tolower(names(out)) == "ejection fraction"))
  expect_false("Left ventricular" %in% names(out))
  expect_identical(attr(out, "source")[match("Surgical procedure", names(out))], "study")
})

test_that("extra, the job's own list, beats the study and can remove", {
  local_defaults()
  cfg <- study_config(abbrev_study(list(`Surgical procedure` = "SP")))
  out <- study_abbreviations(cfg, extra = c("surgical procedure" = "Proc", "Left ventricular" = NA))
  expect_identical(out[["surgical procedure"]], "Proc")
  expect_identical(attr(out, "source")[match("surgical procedure", names(out))], "job")
  expect_false("Left ventricular" %in% names(out))
  out <- study_abbreviations(cfg, extra = list("Left ventricular" = NULL))
  expect_false("Left ventricular" %in% names(out))
  # NA in a list is a removal too, as the help page says.
  out <- study_abbreviations(cfg, extra = list("Left ventricular" = NA, "Aortic valve" = "AV"))
  expect_false("Left ventricular" %in% names(out))
  expect_identical(out[["Aortic valve"]], "AV")
})

test_that("defaults = FALSE leaves the group list out", {
  local_defaults()
  cfg <- study_config(abbrev_study(list(`Surgical procedure` = "SP")))
  out <- study_abbreviations(cfg, defaults = FALSE)
  expect_identical(names(out), "Surgical procedure")
  expect_identical(attr(out, "source"), "study")
})

test_that("two phrases sharing an abbreviation are an error naming both and their levels", {
  local_defaults()
  cfg <- study_config(abbrev_study(list(`Surgical procedure` = "SP")))
  err <- expect_error(study_abbreviations(cfg, extra = c("Systolic pressure" = "SP")))
  expect_match(conditionMessage(err), "Systolic pressure \\(job\\)")
  expect_match(conditionMessage(err), "Surgical procedure \\(study\\)")
})

test_that("an invalid study list stops study_config naming every bad entry at once", {
  local_defaults()
  dir <- abbrev_study(list(`Surgical procedure` = "", `Left atrium` = c("LA", "L"), `Mitral` = "MitralValve"))
  err <- expect_error(study_config(dir))
  msg <- conditionMessage(err)
  expect_match(msg, "abbreviations")
  expect_match(msg, "Surgical procedure")
  expect_match(msg, "Left atrium")
  expect_match(msg, "Mitral")
})

test_that("a phrase listed twice in one list, ignoring case, is an error", {
  local_defaults()
  expect_error(study_config(abbrev_study(list(`Surgical procedure` = "SP", `surgical procedure` = "S"))),
               "more than once")
})

test_that("the default list may not remove, and is checked like any other", {
  local_defaults(c("Left ventricular" = NA))
  cfg <- study_config(abbrev_study())
  expect_error(study_abbreviations(cfg), "default")
})

test_that("add_abbreviation() writes the study list, and a NULL writes a removal", {
  local_defaults()
  dir <- abbrev_study()
  add_abbreviation("Surgical procedure", "SP", start = dir)
  add_abbreviation("Ejection fraction", NULL, start = dir)
  raw <- yaml::read_yaml(file.path(dir, "_study.yml"))
  expect_identical(raw$abbreviations[["Surgical procedure"]], "SP")
  expect_true("Ejection fraction" %in% names(raw$abbreviations))
  expect_null(raw$abbreviations[["Ejection fraction"]])
  out <- study_abbreviations(study_config(dir))
  expect_identical(out[["Surgical procedure"]], "SP")
  expect_false("Ejection fraction" %in% names(out))
  # The rest of the file survives the rewrite.
  expect_identical(raw$study, "Test study for hvtiRutilities")
})

test_that("add_abbreviation() replaces a phrase given in another case", {
  local_defaults()
  dir <- abbrev_study(list(`Surgical procedure` = "SP"))
  add_abbreviation("surgical procedure", "Proc", start = dir)
  raw <- yaml::read_yaml(file.path(dir, "_study.yml"))
  expect_identical(names(raw$abbreviations), "surgical procedure")
  expect_identical(raw$abbreviations[["surgical procedure"]], "Proc")
})

test_that("add_abbreviation() refuses an entry that would break the merged list, and writes nothing", {
  local_defaults()
  dir <- abbrev_study(list(`Surgical procedure` = "SP"))
  before <- readLines(file.path(dir, "_study.yml"))
  expect_error(add_abbreviation("Systolic pressure", "SP", start = dir), "Surgical procedure")
  expect_error(add_abbreviation("AV", "Aortic valve", start = dir), "longer")
  expect_error(add_abbreviation(c("a", "b"), "A", start = dir), "phrase")
  expect_identical(readLines(file.path(dir, "_study.yml")), before)
})

test_that("abbreviations differing only in case coexist; an exact repeat is still an error", {
  # The house style: R for replacement, r for repair.
  local_defaults(c("Aortic valve replacement" = "AVR", "Aortic valve repair" = "AVr"))
  cfg <- study_config(abbrev_study())
  out <- study_abbreviations(cfg)
  expect_identical(unname(out[c("Aortic valve replacement", "Aortic valve repair")]), c("AVR", "AVr"))
  expect_error(study_abbreviations(cfg, extra = c("Aortic valve reconstruction" = "AVr")),
               "Aortic valve repair \\(default\\)")
})

test_that("the shipped default list merges cleanly and shortens labels in the house style", {
  cfg <- study_config(abbrev_study())
  out <- study_abbreviations(cfg)
  expect_gt(length(out), 0L)
  expect_true(all(attr(out, "source") == "default"))
  expect_identical(out[["Aortic valve replacement"]], "AVR")
  expect_identical(out[["Aortic valve repair"]], "AVr")
  d <- data.frame(a = 1, b = 1)
  attr(d$a, "label") <- "Aortic valve replacement performed at the index operation"
  attr(d$b, "label") <- "Aortic valve repair performed at the index operation"
  lmap <- suppressWarnings(label_map(d, abbreviations = out))
  expect_identical(lmap$label, c("AVR performed at the index operation", "AVr performed at the index operation"))
})

test_that("one entry may list spellings, which share its abbreviation and its expansion", {
  local_defaults(list("Coronary artery bypass graft | Coronary artery bypass grafting" = "CABG"))
  cfg <- study_config(abbrev_study())
  out <- study_abbreviations(cfg)
  expect_identical(names(out), c("Coronary artery bypass graft", "Coronary artery bypass grafting"))
  expect_identical(as.vector(out), c("CABG", "CABG"))
  expect_identical(attr(out, "expansion"), rep("Coronary artery bypass graft", 2L))
  expect_identical(attr(out, "source"), c("default", "default"))
  # Separate entries still may not share one.
  expect_error(study_abbreviations(cfg, extra = c("Coronary artery bypass" = "CABG")), "share an abbreviation")
  # A blank spelling is an entry problem.
  expect_error(study_abbreviations(cfg, extra = c("Aortic valve | " = "AV")), "blank spelling")
})

test_that("abbreviations differing only in case clash, except a trailing R against r", {
  local_defaults(c("Aortic valve replacement" = "AVR", "Aortic valve repair" = "AVr", "Pulmonary valve" = "PV"))
  cfg <- study_config(abbrev_study())
  expect_silent(study_abbreviations(cfg))
  err <- expect_error(study_abbreviations(cfg, extra = c("Pulmonary vein" = "Pv")))
  expect_match(conditionMessage(err), "Pulmonary valve \\(default\\)")
  expect_match(conditionMessage(err), "Pulmonary vein \\(job\\)")
  expect_error(study_abbreviations(cfg, extra = c("Atrioventricular" = "avr")), "share an abbreviation")
})

test_that("the shipped list leaves PVR free and knows the common spellings", {
  out <- study_abbreviations(study_config(abbrev_study()))
  expect_false("PVR" %in% out)
  expect_silent(study_abbreviations(study_config(abbrev_study()), extra = c("Pulmonary vascular resistance" = "PVR")))
  d <- data.frame(a = 1, b = 1, c = 1, e = 1)
  attr(d$a, "label") <- "Coronary artery bypass grafting performed at the index operation"
  attr(d$b, "label") <- "Packed red blood cells transfused intraoperatively in units"
  attr(d$c, "label") <- "Cerebrovascular accident within thirty days of the operation"
  attr(d$e, "label") <- "Days from preoperative echocardiogram to the index operation"
  lmap <- suppressWarnings(label_map(d, abbreviations = out))
  expect_match(lmap$label[1], "^CABG performed")
  expect_match(lmap$label[2], "^Packed RBC transfused")
  expect_match(lmap$label[3], "^CVA within")
  expect_match(lmap$label[4], "^Days from preop echo")
  key <- attr(lmap, "abbreviations")
  expect_identical(key$expansion[key$abbreviation == "CABG"], "Coronary artery bypass graft")
})

test_that("naming one spelling overrides or removes the whole entry", {
  local_defaults(list("Red blood cell | Red blood cells" = "RBC"))
  cfg <- study_config(abbrev_study(list(`Red blood cell` = NULL)))
  expect_false(any(c("Red blood cell", "Red blood cells") %in% names(study_abbreviations(cfg))))
  cfg <- study_config(abbrev_study(list(`red blood cells` = "Erythrocyte")))
  out <- study_abbreviations(cfg)
  expect_identical(names(out), "red blood cells")
  expect_identical(unname(as.vector(out)), "Erythrocyte")
})

test_that("a heading shortened from a spelling keys the entry's expansion", {
  ab <- structure(c("Red blood cell" = "RBC", "Red blood cells" = "RBC"),
                  expansion = c("Red blood cell", "Red blood cell"))
  d <- data.frame(a = 1, b = 1, c = 1)
  attr(d$a, "label") <- "Red blood cells: units transfused during the index operation"
  attr(d$b, "label") <- "Red blood cells: units transfused in intensive care"
  attr(d$c, "label") <- "Red blood cell count measured at the first postoperative visit"
  key <- attr(suppressWarnings(label_map(d, abbreviations = ab)), "abbreviations")
  expect_identical(unique(key$expansion[key$abbreviation == "RBC"]), "Red blood cell")
})
