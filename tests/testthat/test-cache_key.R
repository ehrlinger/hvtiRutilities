test_that("code text ignores formatting and comments", {
  a <- parse(text = "{\n  # a comment\n  sum( x,y )\n}", keep.source = TRUE)[[1]]
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
  heads <- hvtiRutilities:::.cache_heads(quote(randomForestSRC::rfsrc(f(x), data = d)))
  expect_identical(heads$ns, "randomForestSRC")
  expect_identical(heads$ns_fn, "rfsrc")
  expect_true("f" %in% heads$bare)
})

test_that("inputs digest free variables and skip locals, functions and unknown names", {
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
  e1 <- new.env(); e2 <- new.env()
  e1$fml <- local(y ~ x, envir = new.env())
  e2$fml <- local(y ~ x, envir = new.env())
  code <- quote(lm(fml))
  expect_identical(hvtiRutilities:::.cache_inputs(code, e1)$fml,
                   hvtiRutilities:::.cache_inputs(code, e2)$fml)
})

test_that("packages come from :: and from the namespace of bare functions, base excluded", {
  f <- digest::digest
  pk <- hvtiRutilities:::.cache_packages(quote(f(stats::median(x))), environment())
  expect_identical(names(pk), "digest")
  expect_identical(pk$digest, as.character(utils::packageVersion("digest")))

  pk2 <- hvtiRutilities:::.cache_packages(quote(jsonlite::toJSON(sum(x))), environment())
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

test_that("the diff names each changed input and package, and ignores r_version", {
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
  expect_match(diff, "packages\\$randomForestSRC +3.4.5 +-> +3.5.0", all = FALSE)
})
