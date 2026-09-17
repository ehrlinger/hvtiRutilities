test_that("code text ignores formatting and comments", {
  a <- parse(text = "{\n  # a comment\n  sum( x,y )\n}",
             keep.source = TRUE)[[1]]
  b <- quote({
    sum(x, y)
  })
  expect_identical(hvtiRutilities:::.cache_code_text(a),
                   hvtiRutilities:::.cache_code_text(b))
})

test_that("assigned names are found, including inside nested calls", {
  code <- quote({
    fml <- y ~ x
    dta = subset(d, x > 1)
    f(g(h <- 1), d[, 1])
  })
  expect_setequal(hvtiRutilities:::.cache_assigned(code), c("fml", "dta", "h"))
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
