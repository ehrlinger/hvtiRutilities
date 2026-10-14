* Recording provenance no longer aborts when a loaded package has left the
  library path, as it can while another process reinstalls packages.
  `packageDescription()` returns `NA` for such a package rather than failing,
  and the package entry then failed on `$`, so `cache_fit()` discarded its
  computed result. The entry now records `NA` for the package's source and
  version and no commit.
