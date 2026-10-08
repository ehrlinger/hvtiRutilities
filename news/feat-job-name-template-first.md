* `job_census()` and `job_files()` read hvtiRtemplates' template-first job
  names, `<prefix>[.<qualifier>].<subject>.<type>.qmd` and their
  `.runner.R`, as scaffolded jobs. Before, the SAS-legacy parser claimed any
  dotted name and counted them as SAS-era jobs.
  Existing dotted job names of this shape are now read as scaffolded, and no
  longer carry legacy qualifiers.
