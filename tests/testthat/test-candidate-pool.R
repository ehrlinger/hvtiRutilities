# Helpers ported from a study's local R/ in hvtiRutilities#47. The tests below
# are written against the failures that motivated each function, not against
# its happy path: every one of them was a real defect in a real screen.

test_that("every ported helper is actually exported", {
  # A package's own tests pass whether or not a function is exported, because
  # they run inside the namespace. The export list has to be asked for.
  ns <- getNamespaceExports("hvtiRutilities")
  expect_true(all(c("sas_variable_block", "imputed_levels", "covariate_audit",
                    "covariates_to_numeric", "pool_collinear_pairs",
                    "concept_of", "concept_map", "prune_to_one_form",
                    "selection_crowding", "POOL_AFFIXES", "POOL_PLAIN_SUFFIX",
                    "POOL_MIN_STEM") %in% ns))
})

# ---- sas_variable_block ----------------------------------------------------

test_that("a banner comment does not swallow the next line's first variable", {
  # /***** Patient Variables *****/ contains `*`, so it does not match a
  # [^*]* body and line-by-line stripping leaves it intact. The banner text
  # then glues onto the FIRST name on the next line and that name vanishes:
  # female, afib_pr, plvidd and size were all lost this way on a real screen.
  x <- c("early", "/***** Patient Variables *****/", "female, afib_pr", ";")
  expect_equal(sas_variable_block(x, "^early$"), c("female", "afib_pr"))
})

test_that("a comment spanning two lines is stripped, not read as live", {
  # Unstripped, a commented-OUT variable is read as a candidate: avet_con
  # entered a screen that way.
  x <- c("early", "age, /* dropped for now", "   avet_con */ bsa", ";")
  expect_equal(sas_variable_block(x, "^early$"), c("age", "bsa"))
})

test_that("name=value keeps only the name, and name/I drops the option", {
  # A job's converged values are its answer for ITS study and must not be
  # inherited by a copy of it. `/I` marks a forced variable; leaving the suffix
  # attached would silently drop exactly the variables the job selected.
  x <- c("early", "bsa=0.31, forced/I, age", ";")
  expect_equal(sas_variable_block(x, "^early$"), c("bsa", "forced", "age"))
})

test_that("names are lowercased, because SAS is case-insensitive", {
  x <- c("early", "AGE, Bsa", ";")
  expect_equal(sas_variable_block(x, "^early$"), c("age", "bsa"))
})

test_that("`after` scopes the search to one macro", {
  x <- c("%macro model;", "early", "wrong_one", ";", "%mend;",
         "%macro final;", "early", "right_one", ";", "%mend;")
  expect_equal(sas_variable_block(x, "^early$", after = "%macro\\s+final"),
               "right_one")
})

test_that("sas_variable_block refuses rather than returning an empty list", {
  # An empty variable list would be read as a result.
  expect_error(sas_variable_block(c("late", "x", ";"), "^early$"),
               "no line matching")
  expect_error(sas_variable_block(c("early", "age"), "^early$"),
               "not terminated")
  expect_error(sas_variable_block(c("early", "/* all gone */", ";"), "^early$"),
               "zero variables")
  expect_error(sas_variable_block(c("early", "age", ";"), "^early$",
                                  after = "%macro nope"),
               "cannot be located")
})

# ---- covariate_audit -------------------------------------------------------

test_that("a mean-imputed binary reports its imputed level and count", {
  # hx_htn's third value is the prevalence of hypertension, not any
  # patient's hypertension status.
  d <- data.frame(
    hx_htn = factor(c("0", "1", "0.714047", "0.714047", "1"))
  )
  a <- covariate_audit(d, "hx_htn")
  expect_equal(a$n_levels, 3L)
  expect_match(a$noninteger_levels, "0.714047 \\(2\\)")
  expect_equal(a$action, "factor -> numeric, enters linearly")
})

test_that("a clean 0/1 indicator reports no non-integer level", {
  d <- data.frame(male = factor(c("0", "1", "1")))
  expect_equal(covariate_audit(d, "male")$noninteger_levels, "")
})

test_that("a continuous column reports NA: not knowable, not none", {
  # Mean imputation is invisible by construction in a continuous column: an
  # imputed mean looks exactly like a measured value. 0 would assert something
  # this cannot establish.
  d <- data.frame(crcl = seq(0.5, 30.5, by = 1))
  expect_true(is.na(covariate_audit(d, "crcl")$noninteger_levels))
})

test_that("an absent or non-numeric-factor covariate is an ERROR action", {
  d <- data.frame(sex = factor(c("male", "female")))
  a <- covariate_audit(d, c("sex", "nope"))
  expect_true(all(grepl("^ERROR", a$action)))
  expect_equal(a$storage[a$variable == "nope"], "absent")
})

test_that("covariates_to_numeric converts numeric levels, keeps categoricals", {
  d <- data.frame(hx_htn = factor(c("0", "1", "0.714047")),
                  sex    = factor(c("male", "female", "male")))
  out <- covariates_to_numeric(d, c("hx_htn", "sex"))
  expect_true(is.numeric(out$hx_htn))
  expect_true(is.factor(out$sex))     # dummy-coded on purpose
})

# ---- pool_collinear_pairs --------------------------------------------------

test_that("exact complements are flagged as complements", {
  # male/female: both offered to a screen, and a design holding both is
  # singular with a free log_mu.
  d <- data.frame(male = c(1, 0, 1, 0), female = c(0, 1, 0, 1),
                  age = c(60, 71, 55, 68))
  p <- pool_collinear_pairs(d, c("male", "female", "age"))
  expect_equal(nrow(p), 1L)
  expect_true(p$complement)
  expect_equal(sort(c(p$var1, p$var2)), c("female", "male"))
})

test_that("a clean pool returns an empty frame with the right columns", {
  d <- data.frame(a = c(1, 2, 3, 4), b = c(4, 1, 3, 2))
  p <- pool_collinear_pairs(d, c("a", "b"))
  expect_equal(nrow(p), 0L)
  expect_named(p, c("var1", "var2", "r", "complement"))
})

test_that("a constant column is skipped rather than yielding NA", {
  d <- data.frame(a = c(1, 2, 3), k = c(5, 5, 5))
  expect_equal(nrow(pool_collinear_pairs(d, c("a", "k"))), 0L)
})

# ---- concepts --------------------------------------------------------------

test_that("transformations group under a parent that is itself in the pool", {
  pool <- c("age", "ln_age", "age2")
  got <- unname(vapply(pool, concept_of, character(1), pool = pool))
  expect_equal(got, c("age", "age", "age"))
})

test_that("a name whose stem is absent stays its own concept", {
  # `agee` does not join `age`: no rule strips a trailing `e`, and grouping too
  # much silently merges two clinical concepts.
  pool <- c("age", "agee")
  expect_equal(concept_of("agee", pool), "agee")
})

test_that("the plain suffix is found when the bare stem is not in the pool", {
  pool <- c("crcl_pr", "ln_crcl")
  expect_equal(concept_of("ln_crcl", pool), "crcl_pr")
})

test_that("a truncated stem groups via the prefix rule", {
  # vars.sas truncates when naming a derivative: effic -> ln_effi.
  pool <- c("effic", "ln_effi", "in_effi")
  expect_equal(concept_of("ln_effi", pool), "effic")
})

test_that("an ambiguous truncated stem declines rather than guessing", {
  pool <- c("effic", "effigy", "ln_effi")
  expect_equal(concept_of("ln_effi", pool), "ln_effi")
})

test_that("a sibling is not elected the concept its siblings group under", {
  # effi2 is itself a derived form, so the prefix rule must not pick it.
  pool <- c("effi2", "ln_effi")
  expect_equal(concept_of("ln_effi", pool), "ln_effi")
})

test_that("an alias reaches a contraction no rule can find", {
  # arin is not a prefix of area_int.
  pool <- c("area_int", "in_arin", "ln_arin")
  al <- c(in_arin = "area_int", ln_arin = "area_int")
  m <- concept_map(pool, aliases = al)
  expect_equal(sort(unique(m$concept)), "area_int")
})

test_that("concept_map refuses an alias pointing outside the pool", {
  expect_error(concept_map(c("age", "ln_age"), aliases = c(ln_age = "nope")),
               "not in the pool")
})

test_that("concept_map refuses a prefer that names a non-member", {
  expect_error(concept_map(c("age", "ln_age"), prefer = c(age = "bsa")),
               "contains only")
  expect_error(concept_map(c("age", "ln_age"), prefer = c(nope = "age")),
               "no candidate belongs to")
})

test_that("prefer changes which form represents the concept", {
  m <- concept_map(c("age", "ln_age"), prefer = c(age = "ln_age"))
  expect_equal(m$variable[m$representative], "ln_age")
})

test_that("prune_to_one_form keeps the pool's original order", {
  pool <- c("bsa", "ln_age", "age", "age2")
  expect_equal(prune_to_one_form(pool), c("bsa", "age"))
})

test_that("selection_crowding counts phases separately", {
  # One form of age in each phase is two slots but not a crowded concept.
  expect_equal(nrow(selection_crowding(c("early.age", "late.age"))), 0L)
  cr <- selection_crowding(c("early.age", "early.ln_age", "late.bsa"))
  expect_equal(nrow(cr), 1L)
  expect_equal(cr$phase, "early")
  expect_equal(cr$n_forms, 2L)
})

test_that("selection_crowding forwards only the applicable aliases", {
  # concept_map() refuses an alias pointing outside its pool, which is right for
  # a CANDIDATE pool. Here the pool is the SELECTED subset, where a parent form
  # may legitimately be absent -- in_arin selected while area_int is not.
  expect_silent(
    cr <- selection_crowding(c("early.in_arin", "early.bsa"),
                             aliases = c(in_arin = "area_int"))
  )
  expect_equal(nrow(cr), 0L)
})

test_that("selection_crowding on nothing gives an empty frame, not error", {
  e <- selection_crowding(character(0))
  expect_equal(nrow(e), 0L)
  expect_named(e, c("phase", "concept", "n_forms", "forms"))
})

test_that("the unterminated-block error reports a file line, not a slice", {
  # With `after` given the search runs over a slice of the file, so a
  # slice-relative index sends the reader to the wrong line. A diagnostic that
  # is confidently wrong is worse than one that omits the number.
  x <- c("%macro model;", "early", "decoy", ";", "%mend;",   # lines 1-5
         "%macro final;", "early", "age")                    # `early` is line 7
  expect_error(
    sas_variable_block(x, "^early$", after = "%macro\\s+final"),
    "at line 7"
  )
})
