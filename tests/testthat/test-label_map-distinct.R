# Distinct labels stay distinct: dev/specs/2026-09-02-label-length-and-fallback-design.md
# section 4.2. Within one label_map() call, labels that differ in label_full
# differ in label.

labelled_frame <- function(labels) {
  d <- as.data.frame(stats::setNames(rep(list(1:2), length(labels)), names(labels)))
  for (k in names(labels)) {
    if (!is.na(labels[[k]])) labelled::var_label(d[[k]]) <- labels[[k]]
  }
  d
}
quiet_map <- function(...) suppressWarnings(label_map(...))

test_that("the map carries over_cap and the abbreviations used", {
  lmap <- quiet_map(labelled_frame(c(a = "Age at operation")))
  expect_named(lmap, c("key", "label", "label_full", "truncated", "over_cap"))
  expect_false(lmap$over_cap)
  abbr <- attr(lmap, "abbreviations")
  expect_s3_class(abbr, "data.frame")
  expect_named(abbr, c("abbreviation", "expansion"))
  expect_equal(nrow(abbr), 0L)
})

test_that("a shared heading is abbreviated in every label that carries it", {
  lmap <- quiet_map(labelled_frame(c(
    p1 = "Surgical procedure: aortic valve replacement with root enlargement",
    p2 = "Surgical procedure: mitral repair",
    other = "Age at operation"
  )), label_max = 40)
  expect_equal(lmap$label[1:2], c("SP: aortic valve replacement with...", "SP: mitral repair"))
  expect_equal(lmap$label[3], "Age at operation")
  expect_equal(attr(lmap, "abbreviations"),
               data.frame(abbreviation = "SP", expansion = "Surgical procedure"))
})

test_that("a heading group that all fits is left alone", {
  lmap <- quiet_map(labelled_frame(c(p1 = "Surgical procedure: AVR", p2 = "Surgical procedure: MVR")))
  expect_equal(lmap$label, lmap$label_full)
  expect_equal(nrow(attr(lmap, "abbreviations")), 0L)
})

test_that("initials skip small words, count a hyphenated word once, and spare a one-word heading", {
  lmap <- quiet_map(labelled_frame(c(
    h1 = "History of left-sided heart failure: before the index operation",
    h2 = "History of left-sided heart failure: after discharge",
    q1 = "Procedure: aortic valve replacement with root enlargement today",
    q2 = "Procedure: mitral"
  )), label_max = 40)
  expect_equal(lmap$label[1:2], c("HLHF: before the index operation", "HLHF: after discharge"))
  expect_match(lmap$label[3], "^Procedure: ")
  expect_equal(lmap$label[4], "Procedure: mitral")
})

test_that("two headings with the same initials are neither abbreviated", {
  lmap <- quiet_map(labelled_frame(c(
    s1 = "Surgical procedure: aortic valve replacement with root enlargement",
    s2 = "Surgical procedure: mitral",
    y1 = "Systolic pressure: measured at the first outpatient clinic visit",
    y2 = "Systolic pressure: at discharge"
  )), label_max = 40)
  expect_false(any(grepl("^SP:", lmap$label)))
  expect_equal(nrow(attr(lmap, "abbreviations")), 0L)
  expect_false(anyDuplicated(lmap$label) > 0L)
})

test_that("a supplied abbreviation beats the initials for a heading", {
  lmap <- quiet_map(labelled_frame(c(
    p1 = "Surgical procedure: aortic valve replacement with root enlargement",
    p2 = "Surgical procedure: mitral repair"
  )), label_max = 40, abbreviations = c("surgical procedure" = "Proc"))
  expect_equal(lmap$label[2], "Proc: mitral repair")
  expect_equal(attr(lmap, "abbreviations")$abbreviation, "Proc")
})

test_that("a supplied phrase shortens an over-long label, whole words only, and never one that fits", {
  lmap <- quiet_map(labelled_frame(c(
    a = "Left ventricular ejection fraction before operation",
    b = "Left ventricular mass",
    c = "Cleft ventricular anomaly recorded at the first clinic visit"
  )), label_max = 40, abbreviations = c("Left ventricular" = "LV"))
  expect_equal(lmap$label[1], "LV ejection fraction before operation")
  expect_equal(lmap$label[2], "Left ventricular mass")
  expect_false(grepl("CLV|LV anomaly", lmap$label[3]))
  expect_equal(attr(lmap, "abbreviations"),
               data.frame(abbreviation = "LV", expansion = "Left ventricular"))
})

test_that("cut labels that collide keep both ends", {
  lmap <- quiet_map(labelled_frame(c(
    a = "Ascending aorta only versus ascending plus arch",
    b = "Ascending aorta only versus ascending plus root"
  )), label_max = 40)
  expect_true(all(nchar(lmap$label) <= 40))
  expect_match(lmap$label[1], "^Ascending.* \\.\\.\\. .*arch$")
  expect_match(lmap$label[2], "root$")
  expect_true(all(lmap$truncated))
  expect_false(any(lmap$over_cap))
})

test_that("labels that differ only in the middle give up the cap and say so", {
  lmap <- quiet_map(labelled_frame(c(
    a = "Aaaaa bbbbb ccccc ddddd X eeeee fffff ggggg hhhhh",
    b = "Aaaaa bbbbb ccccc ddddd Y eeeee fffff ggggg hhhhh"
  )), label_max = 20)
  expect_equal(lmap$label, lmap$label_full)
  expect_true(all(lmap$over_cap))
  expect_false(any(lmap$truncated))
})

test_that("a variable name standing in for a label is never cut or abbreviated", {
  long <- "surgical_procedure_detail_recorded_at_the_index_operation"
  d <- labelled_frame(stats::setNames(c(NA, "Surgical procedure: a very long description of the operation"),
                                      c(long, "p")))
  lmap <- quiet_map(d, label_max = 20)
  expect_equal(lmap$label[1], long)
  expect_false(lmap$truncated[1])
  expect_false(lmap$over_cap[1])
})

test_that("a label never comes out equal to a variable name standing in for another", {
  d <- labelled_frame(c(age = NA, x = "age at some point"))
  names(d)[1] <- "age at..."
  lmap <- quiet_map(d, label_max = 10)
  expect_false(anyDuplicated(lmap$label) > 0L)
})

test_that("distinct full labels always give distinct labels", {
  set.seed(20260928)
  stems <- c("Surgical procedure: ", "Systolic pressure: ", "Ascending aorta only versus ", "History of ")
  words <- c("aortic", "mitral", "valve", "repair", "replacement", "root", "arch", "plus", "with", "before")
  for (rep in 1:40) {
    n <- sample(3:12, 1)
    labels <- unique(vapply(seq_len(n), function(i) {
      paste0(sample(stems, 1), paste(sample(words, sample(2:7, 1), replace = TRUE), collapse = " "))
    }, character(1)))
    d <- labelled_frame(stats::setNames(labels, paste0("v", seq_along(labels))))
    for (cap in c(12, 20, 40)) {
      lmap <- quiet_map(d, label_max = cap)
      expect_false(anyDuplicated(lmap$label) > 0L, info = paste(cap, paste(labels, collapse = " | ")))
      # Every label fits the cap unless over_cap says it does not.
      expect_true(all(nchar(lmap$label[!lmap$over_cap]) <= cap))
    }
  }
})

test_that("abbreviations is validated", {
  d <- labelled_frame(c(a = "Age"))
  expect_error(label_map(d, abbreviations = "LV"), "abbreviations")
  expect_error(label_map(d, abbreviations = c("Left ventricular" = NA)), "abbreviations")
  expect_error(label_map(d, abbreviations = stats::setNames("LV", "")), "abbreviations")
  expect_error(label_map(d, abbreviations = c(a = "X", A = "Y")), "abbreviations")
})

test_that("an added label is kept distinct from the rest of the map", {
  lmap <- quiet_map(labelled_frame(c(a = "Ascending aorta only versus ascending plus arch", b = "Age")),
                    label_max = 40)
  lmap <- add_labels(lmap, c(b = "Ascending aorta only versus ascending plus root"))
  expect_false(anyDuplicated(lmap$label) > 0L)
  expect_match(lmap$label[2], "root$")
})

test_that("an added label that joins a heading group abbreviates the labels already there", {
  # Collisions and heading groups depend on every label, so an override must
  # rebuild the whole map, not only the row it changed.
  lmap <- quiet_map(labelled_frame(c(
    a = "Surgical procedure: aortic valve replacement with root enlargement",
    b = "Age"
  )), label_max = 40)
  expect_match(lmap$label[1], "^Surgical procedure: ")
  lmap <- add_labels(lmap, c(b = "Surgical procedure: mitral repair"))
  expect_match(lmap$label, "^SP: ")
  expect_equal(attr(lmap, "abbreviations")$abbreviation, "SP")
})

test_that("keeping both ends keeps the heading abbreviated", {
  lmap <- quiet_map(labelled_frame(c(
    p1 = "Surgical procedure: aortic valve replacement plus arch",
    p2 = "Surgical procedure: aortic valve replacement plus root",
    p3 = "Surgical procedure: mitral"
  )), label_max = 30)
  expect_match(lmap$label, "^SP: ")
  expect_match(lmap$label[1], "arch$")
  expect_match(lmap$label[2], "root$")
  expect_false(anyDuplicated(lmap$label) > 0L)
})

test_that("supplied phrases stop once the label fits", {
  # Phrases go longest first. The longer one alone brings this label under the
  # cap, so the shorter "before operation" must not be applied as well.
  lmap <- quiet_map(labelled_frame(c(a = "Left ventricular ejection fraction measured before operation")),
                    label_max = 40,
                    abbreviations = c("Left ventricular ejection fraction" = "LVEF", "before operation" = "preop"))
  expect_equal(lmap$label, "LVEF measured before operation")
  expect_equal(attr(lmap, "abbreviations")$abbreviation, "LVEF")
})

test_that("overlapping phrases are read left to right", {
  # Longest-first alone gave "Right CABG": the shorter phrase starting earlier
  # wins the overlap.
  ab <- c("Right coronary artery" = "RCA", "Coronary artery bypass graft" = "CABG", "Coronary artery disease" = "CAD")
  lmap <- quiet_map(labelled_frame(c(
    a = "Right coronary artery bypass graft patency at follow-up",
    b = "Right coronary artery disease severity at catheterization",
    c = "Coronary artery bypass graft performed with vein conduits only"
  )), label_max = 40, abbreviations = ab)
  expect_equal(lmap$label[1:2], c("RCA bypass graft patency at follow-up", "RCA disease severity at catheterization"))
  expect_match(lmap$label[3], "^CABG performed")
})

test_that("heading initials never reuse an abbreviation the list gives another phrase", {
  # "Aortic valve reoperation" has the initials AVR, which the list gives to
  # aortic valve replacement; one key must not say AVR twice.
  lmap <- quiet_map(labelled_frame(c(
    a = "Aortic valve reoperation: time to event in years from index",
    b = "Aortic valve reoperation: indication recorded by the surgeon",
    c = "Aortic valve replacement performed at the index operation date"
  )), label_max = 40, abbreviations = c("Aortic valve replacement" = "AVR"))
  key <- attr(lmap, "abbreviations")
  expect_false(anyDuplicated(key$abbreviation) > 0L)
  expect_false(any(grepl("^AVR:", lmap$label)))
  expect_match(lmap$label[3], "^AVR performed")
})
