* `study_need()` now records a package that is already installed but absent from
  `renv.lock`. It used to declare the package and stop there, so the study looked
  reproducible and `renv::restore()` would not bring the package back. An interactive
  session is asked once and snapshots. A batch session, a declined question or a
  refusal from `guard_snapshot()` warns instead and writes no lock; none of them stops
  the caller, which already has the package. A package the lock holds, or a base
  package, changes nothing and is not asked about.
