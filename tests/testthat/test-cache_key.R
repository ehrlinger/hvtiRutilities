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
