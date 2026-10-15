# Display the NEWS file

Display the NEWS.md file for the hvtiRutilities package showing release
notes and change history.

## Usage

``` r
hvtiRutilities.news()
```

## Value

Invisibly returns NULL. Called for side effect of displaying NEWS.

## Examples

``` r
# Opens a pager, so only in an interactive session.
if (interactive()) hvtiRutilities.news()
```
