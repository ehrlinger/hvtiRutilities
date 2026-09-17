library(testthat)
library(hvtiRutilities)

# Parity with SAS 9.4 M8 PROC UNIVARIATE (oracle run 2026-09-17). Each
# scenario's fixture is analysed with the scenario's WEIGHT, VARDEF=, MU0= and
# CLASS, requesting exactly the columns SAS wrote, and every value is compared.

# Kept out of fixtures/: that directory is the sas_triage() corpus, and a
# subdirectory there changes its fingerprint.
uni_dir <- function(...) test_path("fixtures-proc_univariate", ...)

read_fixture <- function(name) {
  utils::read.csv(uni_dir("fixtures", paste0(name, ".csv")),
                  na.strings = c("", "NA"),
                  colClasses = c(id = "integer", g = "character",
                                 x = "numeric", w = "numeric"))
}

read_sas <- function(name) {
  d <- utils::read.csv(uni_dir("out", paste0(name, ".csv")),
                       na.strings = c("", "NA"))
  names(d) <- tolower(names(d))
  d
}

pp_points <- c(pp_0 = 0, pp_2_5 = 2.5, pp_16 = 16, pp_50 = 50, pp_84 = 84,
               pp_97_5 = 97.5, pp_100 = 100)

# Shapiro-Wilk: R's shapiro.test() implements Royston (1995), SAS Royston
# (1992). W agrees to about 1e-8, so normal uses 1e-7 rather than 1e-10. The
# p-value magnifies the difference: 4.5e-7 relative was observed at n = 12
# (the basic fixture), so probn uses 1e-6.
tolerance_for <- function(col) {
  switch(col, normal = 1e-7, probn = 1e-6, 1e-10)
}

scenarios <- utils::read.csv(uni_dir("scenarios.csv"))

for (i in seq_len(nrow(scenarios))) {
  sc <- scenarios[i, ]
  test_that(paste("proc_univariate matches SAS:", sc$scenario), {
    dta <- read_fixture(sc$fixture)
    sas <- read_sas(sc$scenario)
    class_col <- if (sc$class == 1) "g" else NULL
    cols <- setdiff(names(sas), class_col)
    pp_cols <- cols[startsWith(cols, "pp_")]
    kw <- setdiff(cols, pp_cols)
    expect_setequal(pp_cols, names(pp_points))

    run <- function() {
      proc_univariate(dta, vars = "x", class = class_col, stats = kw,
                      weights = if (sc$weight == 1) "w" else NULL,
                      pctlpts = unname(pp_points[pp_cols]),
                      pctlpre = "pp_", mu0 = sc$mu0,
                      vardef = tolower(sc$vardef))
    }
    if (sc$scenario == "n2001") {
      expect_warning(res <- run(), "Kolmogorov D")
      # Deliberate divergence: SAS writes a Kolmogorov D statistic above 2000
      # observations; proc_univariate() returns NA.
      sas$normal <- NA_real_
      sas$probn <- NA_real_
    } else {
      expect_no_warning(res <- run())
    }

    expect_equal(nrow(res), nrow(sas))
    if (!is.null(class_col)) {
      expect_equal(res$g, sas$g)
    }
    for (col in cols) {
      r <- as.numeric(res[[col]])
      s <- as.numeric(sas[[col]])
      expect_identical(is.na(r), is.na(s),
                       label = paste(sc$scenario, col, "NA pattern"))
      ok <- !is.na(s)
      expect_equal(r[ok], s[ok], tolerance = tolerance_for(col),
                   label = paste(sc$scenario, col))
    }
  })
}
