## Checks the SAS oracle output before it is committed as test fixtures:
## every required scenario produced a CSV, with the expected columns and row
## count. It does not compare values; that is the parity tests' job.
##
## Run from the package root after copying SAS's out/ directory into the kit:
##   Rscript dev/oracle/proc_univariate/check_oracle.R

kit <- file.path("dev", "oracle", "proc_univariate")
out_dir <- file.path(kit, "out")
scenarios <- utils::read.csv(file.path(kit, "scenarios.csv"),
                             stringsAsFactors = FALSE)

base_cols <- c("n", "nobs", "nmiss", "sum", "mean", "std", "var", "cv",
               "stdmean", "uss", "css", "skewness", "kurtosis", "sumwgt",
               "range", "qrange", "mode", "min", "max", "median", "q1", "q3",
               "p1", "p5", "p10", "p90", "p95", "p99",
               "pp_0", "pp_2_5", "pp_16", "pp_50", "pp_84", "pp_97_5",
               "pp_100")
t_cols <- c("t", "probt")
rank_cols <- c("msign", "probm", "signrank", "probs", "normal", "probn")

problems <- character()
notes <- character()
n_absent <- 0L

if (!file.exists(file.path(out_dir, "sas_version.txt"))) {
  problems <- c(problems, "out/sas_version.txt is missing")
}

for (i in seq_len(nrow(scenarios))) {
  sc <- scenarios[i, ]
  path <- file.path(out_dir, paste0(sc$scenario, ".csv"))
  if (!file.exists(path)) {
    msg <- paste0(sc$scenario, ": no output file")
    if (sc$optional == 1L) {
      notes <- c(notes, paste0(msg, " (optional: SAS refused the request)"))
      n_absent <- n_absent + 1L
    } else {
      problems <- c(problems, msg)
    }
    next
  }
  res <- utils::read.csv(path, stringsAsFactors = FALSE)
  names(res) <- tolower(names(res))
  expected <- c(if (sc$class == 1L) "g", base_cols,
                if (sc$ttest == 1L) t_cols,
                if (sc$ranktests == 1L) rank_cols)
  absent <- setdiff(expected, names(res))
  if (length(absent) > 0L) {
    problems <- c(problems, paste0(sc$scenario, ": missing column(s) ",
                                   paste(absent, collapse = ", ")))
  }
  want_rows <- if (sc$class == 1L) 3L else 1L
  if (nrow(res) != want_rows) {
    problems <- c(problems, paste0(sc$scenario, ": ", nrow(res),
                                   " row(s), expected ", want_rows))
  }
  all_na <- vapply(expected, function(col) {
    col %in% names(res) && all(is.na(res[[col]]))
  }, logical(1))
  if (any(all_na)) {
    cols <- expected[all_na]
    notes <- c(notes, paste0(sc$scenario, ": entirely missing column(s) ",
                             paste(cols, collapse = ", "),
                             " (check oracle.log)"))
  }
}

for (n in notes) message("NOTE  ", n)
if (length(problems) > 0L) {
  for (p in problems) message("ERROR ", p)
  quit(status = 1L)
}
message("OK    ", nrow(scenarios) - n_absent, " of ", nrow(scenarios),
        " scenario outputs present and well-formed")
