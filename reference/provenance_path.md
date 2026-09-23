# Name the provenance sidecar for an output

Returns the path of the sidecar belonging to a rendered output: the
output path with its extension replaced by `.provenance.json`.

## Usage

``` r
provenance_path(path)
```

## Arguments

- path:

  Character(1). Path to a rendered output.

## Value

Character(1). The sidecar path.

## See also

[`publish_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/publish_provenance.md),
[`record_provenance`](https://ehrlinger.github.io/hvtiRutilities/reference/record_provenance.md)

## Examples

``` r
provenance_path("_output/death-hz-ac.html")
#> [1] "_output/death-hz-ac.provenance.json"
```
