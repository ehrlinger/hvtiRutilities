# A disposable corpus for the sweep tests. Every file here exists to pin one
# behaviour the spec calls out; if you add a file, say which.
#
#   alpha/distributions/hz.dead.lst        canonical placed legacy job
#   alpha/distributions/hz.dead.sas        same stem, second artifact
#   alpha/distributions/hz.dead.log        same stem, third artifact
#   alpha/distributions/hz.dead.sas~       editor backup: inflates n_files,
#                                          NOT n_jobs -- it shares the stem
#   alpha/distributions/tp.hz.dead.lst     template, counted separately
#   alpha/graphs/Training/hp.curve.pdf     nested one level below the folder
#   alpha/analyses/hz.misfiled.sas         hz outside its taxonomy folder
#   alpha/distributions/pp.notes.pdf       documented non-prefix
#   alpha/distributions/zz.mystery.sas     genuinely unknown prefix
#   alpha/README.md                        unplaced, and prefix "README"
#   beta/distributions/ac.dead.lst         a SECOND study -- the template gate
#                                          counts distinct studies, so one
#                                          study cannot exercise it
#   gamma/sub/distributions/ac.dead.lst    a MULTI-LEVEL study path. Real
#                                          studies are cardiac/rhythm/maze/
#                                          atricure/gender, not one component;
#                                          without this the path join is only
#                                          ever exercised in its degenerate
#                                          single-element case
#
# The four below carry the R side. The fixture shipped holding twelve
# SAS-shaped files and not one R file, which is why an extension filter
# dropping exactly R/qmd/rda -- the regression design spec section 4.4 exists
# to prevent -- passed the entire suite. They also give the sweep one file per
# naming convention in section 4.2, as section 7 promised: `set`, `template`
# and `r_transitional` were previously exercised only as bare basenames in
# test-job-names.R, so the seam between the parser and the sweep was untested
# for three of the four conventions.
#
#   alpha/analyses/R_hazard/qmd/dead_pa-hz-03.01-ac.qmd
#                                          the `set` convention, nested two
#                                          levels below analyses/ the way
#                                          preserve_root's R jobs are
#   alpha/analyses/R_hazard/qmd/02-hz-dead_pa.qmd
#                                          the `r_transitional` convention,
#                                          same nesting
#   alpha/analyses/R_hazard/qmd/03.01-ac.qmd
#                                          the `template` convention -- the
#                                          fourth, without which the
#                                          fixture-completeness test cannot
#                                          hold
#   alpha/analyses/boost.model.rda         a .rda artifact under an unknown
#                                          prefix: the extension an allowlist
#                                          would drop, on a prefix that must
#                                          surface as a finding
make_corpus_fixture <- function(dir) {
  files <- c(
    "alpha/distributions/hz.dead.lst",
    "alpha/distributions/hz.dead.sas",
    "alpha/distributions/hz.dead.log",
    "alpha/distributions/hz.dead.sas~",
    "alpha/distributions/tp.hz.dead.lst",
    "alpha/graphs/Training/hp.curve.pdf",
    "alpha/analyses/hz.misfiled.sas",
    "alpha/distributions/pp.notes.pdf",
    "alpha/distributions/zz.mystery.sas",
    "alpha/README.md",
    "beta/distributions/ac.dead.lst",
    "gamma/sub/distributions/ac.dead.lst",
    "alpha/analyses/R_hazard/qmd/dead_pa-hz-03.01-ac.qmd",
    "alpha/analyses/R_hazard/qmd/02-hz-dead_pa.qmd",
    "alpha/analyses/R_hazard/qmd/03.01-ac.qmd",
    "alpha/analyses/boost.model.rda"
  )
  for (f in files) {
    p <- file.path(dir, f)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    file.create(p)
  }
  dir
}
