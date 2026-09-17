test_that("code text ignores formatting and comments", {
  a <- parse(text = "{\n  # a comment\n  sum( x,y )\n}",
             keep.source = TRUE)[[1]]
  b <- quote({
    sum(x, y)
  })
  expect_identical(hvtiRutilities:::.cache_code_text(a),
                   hvtiRutilities:::.cache_code_text(b))
})

test_that("call heads separate namespaced and bare functions", {
  heads <- hvtiRutilities:::.cache_heads(
    quote(randomForestSRC::rfsrc(f(x), data = d))
  )
  expect_identical(heads$ns, "randomForestSRC")
  expect_identical(heads$ns_fn, "rfsrc")
  expect_setequal(heads$bare, "f")
  expect_identical(
    hvtiRutilities:::.cache_heads(quote(pkg::fn(x)))$bare, character(0)
  )
})

test_that("inputs digest free variables, skipping locals/functions/unknowns", {
  d <- data.frame(x = 1:3)
  helper <- function(z) z
  code <- quote({
    local_copy <- d
    helper(nrow(local_copy) + not_a_variable)
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, environment())
  expect_identical(names(inputs), "d")
  expect_type(inputs$d, "character")
})

test_that("changing a value or a column type changes the input digest", {
  env <- new.env()
  env$d <- data.frame(x = 1:3)
  code <- quote(sum(d$x))
  k1 <- hvtiRutilities:::.cache_inputs(code, env)$d
  env$d$x[2] <- 9L
  k2 <- hvtiRutilities:::.cache_inputs(code, env)$d
  env$d$x <- as.numeric(env$d$x)
  k3 <- hvtiRutilities:::.cache_inputs(code, env)$d
  expect_false(identical(k1, k2))
  expect_false(identical(k2, k3))
})

test_that("a formula input digests the same whatever its environment", {
  e1 <- new.env()
  e2 <- new.env()
  e1$fml <- local(y ~ x, envir = new.env())
  e2$fml <- local(y ~ x, envir = new.env())
  code <- quote(lm(fml))
  expect_identical(hvtiRutilities:::.cache_inputs(code, e1)$fml,
                   hvtiRutilities:::.cache_inputs(code, e2)$fml)
})

test_that("packages come from :: and bare functions, base excluded", {
  f <- digest::digest
  pk <- hvtiRutilities:::.cache_packages(
    quote(f(stats::median(x))), environment()
  )
  expect_identical(names(pk), "digest")
  expect_identical(pk$digest, as.character(utils::packageVersion("digest")))

  pk2 <- hvtiRutilities:::.cache_packages(
    quote(jsonlite::toJSON(sum(x))), environment()
  )
  expect_identical(names(pk2), "jsonlite")
})

test_that("pkg::fn used as a function value (not a call head) still versions its package", {
  pk <- hvtiRutilities:::.cache_packages(
    quote(lapply(x, digest::digest)), environment()
  )
  expect_identical(names(pk), "digest")

  # Existing head behavior is unchanged.
  heads1 <- hvtiRutilities:::.cache_heads(quote(digest::digest(x)))
  expect_identical(heads1$ns, "digest")
  expect_identical(heads1$ns_fn, "digest")

  heads2 <- hvtiRutilities:::.cache_heads(quote(f(x)(y)))
  expect_identical(heads2$bare, "f")
})

test_that("identical inputs give identical keys; the seed is part of the key", {
  d <- 1:5
  k1 <- hvtiRutilities:::.cache_key(quote(sum(d)), environment(), NULL)
  k2 <- hvtiRutilities:::.cache_key(quote(sum(d)), environment(), NULL)
  k3 <- hvtiRutilities:::.cache_key(quote(sum(d)), environment(), 1L)
  expect_identical(k1, k2)
  expect_length(hvtiRutilities:::.cache_key_diff(k1, k2), 0L)
  expect_match(hvtiRutilities:::.cache_key_diff(k1, k3), "seed")
})

test_that("an upstream value's cache key controls its digest across reload", {
  dta <- data.frame(y = c(1, 2, 3, 4, 6), x = c(1, 2, 3, 5, 7))
  fit <- lm(y ~ x, data = dta)
  key <- list(code = "lm(y ~ x)", inputs = list(), packages = list(),
              seed = NULL)
  live <- structure(fit, hvtiRutilities_cache_key = key)

  env <- new.env()
  env$up <- live
  code <- quote(predict(up))
  before <- hvtiRutilities:::.cache_inputs(code, env)$up

  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  saveRDS(live, tmp)
  env$up <- readRDS(tmp)
  after <- hvtiRutilities:::.cache_inputs(code, env)$up

  expect_identical(before, after)
})

test_that("editing a global helper's body changes the key", {
  # A function literal's environment() is where it was *evaluated*, not
  # merely where its name is later bound; eval(..., envir = globalenv())
  # makes it a genuine global-environment closure (the _common.R shape).
  eval(quote(cache_test_helper <- function(z) z * 1), envir = globalenv())
  on.exit(rm("cache_test_helper", envir = globalenv()), add = TRUE)
  env <- new.env()
  env$z <- 5
  code <- quote(cache_test_helper(z))
  k1 <- hvtiRutilities:::.cache_inputs(code, env)

  eval(quote(cache_test_helper <- function(z) z * 1000), envir = globalenv())
  k2 <- hvtiRutilities:::.cache_inputs(code, env)

  expect_false(identical(k1, k2))
})

test_that("a closure factory's captured value changes the key, not just its body", {
  # As in "editing a global helper's body changes the key" above, the
  # factory must be *evaluated* in globalenv() so the closures it returns
  # have environment() chains rooted there (the real _common.R shape),
  # rather than in the test's own local scope.
  eval(quote(cache_test_make <- function(a) function(x) x + a),
       envir = globalenv())
  on.exit(rm("cache_test_make", envir = globalenv()), add = TRUE)
  h1 <- eval(quote(cache_test_make(1)), envir = globalenv())
  h2 <- eval(quote(cache_test_make(2)), envir = globalenv())
  env <- new.env()
  env$h <- h1
  env$x <- 5
  code <- quote(h(x))
  k1 <- hvtiRutilities:::.cache_inputs(code, env)

  env$h <- h2
  k2 <- hvtiRutilities:::.cache_inputs(code, env)

  expect_false(identical(k1, k2))
})

test_that("a plain global helper still keys by body alone", {
  eval(quote(cache_test_plain_helper <- function(z) z * 1), envir = globalenv())
  on.exit(rm("cache_test_plain_helper", envir = globalenv()), add = TRUE)
  env <- new.env()
  env$h <- get("cache_test_plain_helper", envir = globalenv())
  env$x <- 5
  inputs <- hvtiRutilities:::.cache_inputs(quote(h(x)), env)
  expect_identical(inputs$h,
    hvtiRutilities:::.cache_digest(
      hvtiRutilities:::.cache_global_closure_text(env$h)))
})

test_that("a package function still contributes nothing to inputs", {
  env <- new.env()
  env$h <- median
  env$x <- 1:3
  inputs <- hvtiRutilities:::.cache_inputs(quote(h(x)), env)
  expect_null(inputs[["h"]])
})

test_that("a global helper is keyed even when its name is shadowed elsewhere in the code", {
  eval(quote(prep <- function(x) x + 1), envir = globalenv())
  on.exit(rm("prep", envir = globalenv()), add = TRUE)
  env <- new.env()
  env$z <- 5
  code <- quote({
    sapply(1:2, function(prep) prep)
    prep(z)
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_true("prep" %in% names(inputs))
})

test_that("a global helper is keyed even when assigned later in the same expression", {
  eval(quote(prep <- function(x) x + 1), envir = globalenv())
  on.exit(rm("prep", envir = globalenv()), add = TRUE)
  env <- new.env()
  env$z <- 5
  code <- quote(prep <- prep(z))
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_true("prep" %in% names(inputs))
})

test_that("a genuinely local function does not shadow in a global of the same name", {
  eval(quote(f <- function(x) x * 100), envir = globalenv())
  on.exit(rm("f", envir = globalenv()), add = TRUE)
  env <- new.env()
  env$d <- 5
  code <- quote({
    f <- function(x) x
    f(d)
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_false("f" %in% names(inputs))
})

test_that("a helper called inside a lambda body is keyed", {
  eval(quote(prep <- function(x) x + 1), envir = globalenv())
  on.exit(rm("prep", envir = globalenv()), add = TRUE)
  env <- new.env()
  env$v <- 1:3
  code <- quote(sapply(v, function(x) prep(x)))
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_true("prep" %in% names(inputs))
})

test_that("the right side of $ is not treated as a free variable", {
  env <- new.env()
  env$df <- data.frame(col = 1)
  env$col <- 999
  inputs <- hvtiRutilities:::.cache_inputs(quote(df$col), env)
  expect_identical(names(inputs), "df")
})

test_that("both symbols of a namespaced call are excluded outside head position", {
  env <- new.env()
  env$x <- 1:3
  env$stats <- "not the package"
  env$sd <- "not the function"
  inputs <- hvtiRutilities:::.cache_inputs(quote(sapply(x, stats::sd)), env)
  expect_identical(names(inputs), "x")
})

test_that("a package function used bare does not become an input", {
  out <- hvtiRutilities:::.cache_inputs(quote(median(x)), environment())
  expect_null(out[["median"]])
})

test_that("lambda formals are bound, not free inputs", {
  env <- new.env()
  env$v <- 1:3
  env$x <- 999
  inputs <- hvtiRutilities:::.cache_inputs(
    quote(sapply(v, function(x) x ^ 2)), env
  )
  expect_identical(names(inputs), "v")
})

test_that("for-loop index variables are bound, not free inputs", {
  env <- new.env()
  env$v <- 1:3
  env$i <- 999
  code <- quote({
    s <- 0
    for (i in v) s <- s + i
    s
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_identical(names(inputs), "v")
})

test_that("a shadowed lambda formal still leaves a genuine free use as input", {
  env <- new.env()
  env$d <- 1:3
  inputs <- hvtiRutilities:::.cache_inputs(
    quote(sapply(1:2, function(d) d) + sum(d)), env
  )
  expect_true("d" %in% names(inputs))
})

test_that("a shadowed loop index still leaves a genuine free use as input", {
  env <- new.env()
  env$d <- 1:3
  code <- quote({
    for (d in 1:2) print(d)
    sum(d)
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_true("d" %in% names(inputs))
})

test_that("a nested function's formal does not shadow the outer scope", {
  env <- new.env()
  env$x <- 1:3
  code <- quote({
    inner <- function(x) x + 1
    x + inner(2)
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_identical(names(inputs), "x")
})

test_that("a formal default expression's free variable is an input; the formal is not", {
  env <- new.env()
  env$m <- 5
  env$k <- 999
  inputs <- hvtiRutilities:::.cache_inputs(quote(function(k = m) k), env)
  expect_identical(names(inputs), "m")
})

test_that("a read before its assignment in the same block is a free input", {
  env <- new.env()
  env$d <- 1:3
  code <- quote({
    sum(d)
    d <- 1
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_true("d" %in% names(inputs))
})

test_that("assign-then-use in the same block leaves no free input", {
  env <- new.env()
  env$d <- 1:3
  code <- quote({
    d <- 1
    sum(d)
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_length(inputs, 0L)
})

test_that("digesting an upstream key ignores r_version and reproducible", {
  key1 <- list(code = "sum(d)", inputs = list(d = "aaa"), packages = list(),
              seed = NULL, reproducible = TRUE,
              r_version = "R version 4.4.0 (2024-04-24)")
  key2 <- key1
  key2$r_version <- "R version 4.5.0 (2025-04-01)"
  key2$reproducible <- FALSE

  env <- new.env()
  code <- quote(sum(up))

  env$up <- structure(1:3, hvtiRutilities_cache_key = key1)
  d1 <- hvtiRutilities:::.cache_inputs(code, env)$up
  env$up <- structure(1:3, hvtiRutilities_cache_key = key2)
  d2 <- hvtiRutilities:::.cache_inputs(code, env)$up
  expect_identical(d1, d2)

  key3 <- key1
  key3$inputs$d <- "zzz"
  env$up <- structure(1:3, hvtiRutilities_cache_key = key3)
  d3 <- hvtiRutilities:::.cache_inputs(code, env)$up
  expect_false(identical(d1, d3))

  key4 <- key1
  key4$code <- "sum(d) + 1"
  env$up <- structure(1:3, hvtiRutilities_cache_key = key4)
  d4 <- hvtiRutilities:::.cache_inputs(code, env)$up
  expect_false(identical(d1, d4))
})

test_that(".cache_digest ignores a session serializeVersion option", {
  value <- list(a = 1, b = "x")
  d1 <- hvtiRutilities:::.cache_digest(value)
  d2 <- withr::with_options(list(serializeVersion = 3L),
                            hvtiRutilities:::.cache_digest(value))
  expect_identical(d1, d2)
})

test_that("the diff names each changed input/package, ignoring r_version", {
  old <- list(code = "sum(d)", inputs = list(d = "aaa", e = "bbb"),
              packages = list(randomForestSRC = "3.4.5"), seed = NULL,
              reproducible = TRUE, r_version = "R 4.5.0")
  new <- old
  new$inputs$d <- "ccc"
  new$inputs$e <- NULL
  new$packages$randomForestSRC <- "3.5.0"
  new$r_version <- "R 4.5.1"
  diff <- hvtiRutilities:::.cache_key_diff(old, new)
  expect_length(diff, 3L)
  expect_match(diff, "inputs\\$d +aaa +-> +ccc", all = FALSE)
  expect_match(diff, "inputs\\$e +bbb +-> +\\(absent\\)", all = FALSE)
  expect_match(diff, "packages\\$randomForestSRC +3.4.5 +-> +3.5.0",
               all = FALSE)
})

test_that("the diff reports a changed code body, not its full text", {
  old <- list(code = "sum(d)", inputs = list(), packages = list(),
              seed = NULL)
  new <- old
  new$code <- "sum(d) + 1"
  diff <- hvtiRutilities:::.cache_key_diff(old, new)
  expect_identical(diff, "  code  (changed)")
})

test_that("an empty argument (as in d[, 1]) is skipped by the free-variable and head walks", {
  env <- new.env()
  env$d <- data.frame(x = 1, y = 2)
  code <- quote(d[, 1])
  expect_identical(hvtiRutilities:::.cache_free_vars(code), "d")
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_identical(names(inputs), "d")
  heads <- hvtiRutilities:::.cache_heads(code)
  expect_identical(heads$bare, "[")
})

test_that("a call-valued head with an empty argument is walked without erroring", {
  # g(1)(x, ) : the head "g(1)" is itself a call, and the second argument to
  # the outer call is empty, exercising both the call-valued-head branch and
  # the empty-argument skip inside it, for both the variable and head walks.
  env <- new.env()
  env$g <- function(a) function(x, y) x
  env$x <- 5
  code <- quote(g(1)(x, ))
  # "g" names the call head of g(1), not a data read, so .cache_free_vars()
  # excludes it (mirroring all.vars()); .cache_free_heads() is what picks up
  # a bare call head like this one, for the global-helper/package checks.
  expect_identical(hvtiRutilities:::.cache_free_vars(code), "x")
  expect_identical(hvtiRutilities:::.cache_free_heads(code), "g")
})

test_that("a call-valued statement contributes nothing to what a block binds afterward", {
  stmt <- quote((function(z) z)(1))
  expect_identical(hvtiRutilities:::.cache_bound_after(stmt), character(0))
})

test_that("a nested block's assignment is bound for what follows it in the enclosing block", {
  env <- new.env()
  env$a <- 999
  code <- quote({
    { a <- 1 }
    a
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_length(inputs, 0L)
})

test_that("a factory closure's captures are skipped, not fabricated, when none resolve to data", {
  # All of a closure's free variables can fail to contribute a capture: one
  # names another function (skipped, not digested, to avoid recursing into a
  # further closure), and one does not resolve at all. Either way the key
  # falls back to the closure's body text alone, still by way of the
  # non-globalenv() branch (fn_env is a factory call frame, not globalenv()
  # itself).
  eval(quote(cache_test_make_fnonly <- function() {
    helper <- function(z) z * 2
    function(x) if (FALSE) helper else x
  }), envir = globalenv())
  on.exit(rm("cache_test_make_fnonly", envir = globalenv()), add = TRUE)
  h1 <- eval(quote(cache_test_make_fnonly()), envir = globalenv())
  expect_false(identical(environment(h1), globalenv()))
  txt1 <- hvtiRutilities:::.cache_global_closure_text(h1)
  # No capture line was appended: the text is exactly the deparsed closure,
  # a single "function (x) \n..." value with no extra "name=digest" line.
  expect_identical(lengths(regmatches(txt1, gregexpr("\n", txt1))), 1L)
  expect_false(grepl("helper=", txt1, fixed = TRUE))

  eval(quote(cache_test_make_unresolved <- function() {
    function(x) if (FALSE) totallyUndefinedVar123 else x
  }), envir = globalenv())
  on.exit(rm("cache_test_make_unresolved", envir = globalenv()), add = TRUE)
  h2 <- eval(quote(cache_test_make_unresolved()), envir = globalenv())
  txt2 <- hvtiRutilities:::.cache_global_closure_text(h2)
  expect_identical(lengths(regmatches(txt2, gregexpr("\n", txt2))), 1L)
  expect_false(grepl("totallyUndefinedVar123=", txt2, fixed = TRUE))
})

test_that("a global function referenced as a value (not called) is keyed by its body", {
  eval(quote(cache_test_asvalue <- function(z) z * 3), envir = globalenv())
  on.exit(rm("cache_test_asvalue", envir = globalenv()), add = TRUE)
  env <- new.env()
  code <- quote({
    picked <- cache_test_asvalue
    picked
  })
  inputs <- hvtiRutilities:::.cache_inputs(code, env)
  expect_identical(
    inputs$cache_test_asvalue,
    hvtiRutilities:::.cache_digest(
      hvtiRutilities:::.cache_global_closure_text(get("cache_test_asvalue",
                                                       envir = globalenv())))
  )
})

test_that("a bare call head bound to a non-function value contributes nothing", {
  env <- new.env()
  env$x <- 5
  inputs <- hvtiRutilities:::.cache_inputs(quote(x(1)), env)
  expect_length(inputs, 0L)
})

test_that(".cache_show truncates a long value to 60 characters", {
  short <- hvtiRutilities:::.cache_show("abc")
  expect_identical(short, "abc")
  long <- paste(rep("a", 80), collapse = "")
  shown <- hvtiRutilities:::.cache_show(long)
  expect_identical(nchar(shown), 60L)
  expect_identical(shown, paste0(strrep("a", 57L), "..."))
})
