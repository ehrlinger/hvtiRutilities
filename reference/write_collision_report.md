# Write the macro name-collision report

Reports every macro name defined in more than one file, with its
distinct body count and defining files. In SAS, `%include`-ing two files
that define the same macro means the second silently shadows the first,
so this report is a prerequisite for building a trustworthy SAS harness.

## Usage

``` r
write_collision_report(x, path)
```

## Arguments

- x:

  A `data.frame` returned by
  [`sas_triage`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md).

- path:

  Character. Destination `.md` path.

## Value

Invisibly, `path`.

## Details

The report ends with a **Provenance** section derived from the scanned
corpus rather than from the clock: a fingerprint over every (macro,
file, body hash) triple and the excluded-directory list, the file,
definition and name counts, and the package version.

A generated-on field would defeat the byte-for-byte reproducibility that
makes the artifact reviewable, which is why neither this report nor
[`write_macro_manifest`](https://ehrlinger.github.io/hvtiRutilities/reference/write_macro_manifest.md)
carries one. An artifact with no identity at all is the opposite
failure: a committed report and a design's prose can disagree with
nothing to say which is stale. An input-derived stamp avoids both,
because it is a function of the inputs alone.

Determinism is therefore over the corpus *and* the package version, not
the corpus alone: re-running under a different version changes the
version row, by design, because that is what attributes the artifact to
a build. The fingerprint itself depends only on the corpus, so it stays
comparable across versions.

The fingerprint follows content, not location.
[`sas_triage`](https://ehrlinger.github.io/hvtiRutilities/reference/sas_triage.md)
records file basenames, so re-scanning the same corpus from a different
mount point yields the same value and a share remount does not
invalidate every committed report.

## Examples

``` r
# \donttest{
d <- system.file("extdata", "macros", package = "hvtiRutilities")
if (nzchar(d)) {
  write_collision_report(sas_triage(d), tempfile(fileext = ".md"))
}
# }
```
