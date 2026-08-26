# Precondition helper for the parquet cache's mtime-based validity tests.
#
# .cache_valid() branches on whether a source's mtime carries a fractional
# part: fractional means the filesystem can resolve a same-tick rewrite and
# mtime is trusted directly; whole-second means it cannot, and the recorded
# sha256 is verified instead.
#
# A test that wants the FRACTIONAL branch therefore has a precondition the
# filesystem must supply, and Sys.setFileTime() does not supply it everywhere
# -- on Windows it truncates to whole seconds. A test that assumes otherwise
# does not fail because the code is wrong; it asserts against a branch that
# was never reached, which is worse than not testing at all.
#
# This is a capability check rather than skip_on_os("windows") on purpose. The
# reason to skip is "this filesystem cannot express the precondition", not
# "this is Windows" -- so it keeps running anywhere that can express it, and
# keeps skipping anywhere that cannot, including platforms nobody thought of.
#
# Returns the mtime the filesystem actually recorded, so callers derive their
# offsets from that rather than from the value they asked for.
require_subsecond_mtime <- function(path) {
  mt <- file.info(path)$mtime
  if (!is.finite(as.numeric(mt))) {
    testthat::skip(paste("cannot stat", basename(path), "to establish mtime resolution"))
  }
  if (as.numeric(mt) %% 1 == 0) {
    testthat::skip(paste("filesystem does not preserve sub-second mtime;",
                         "the fractional-mtime branch is unreachable here"))
  }
  mt
}
