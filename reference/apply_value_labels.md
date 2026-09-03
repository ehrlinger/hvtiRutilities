# Declare value labels for coded variables from a YAML file

Reads a study's `value_labels.yml` and attaches the declared
code-to-text mappings to the matching columns as value labels, via
[`labelled::val_labels()`](https://larmarange.github.io/labelled/reference/val_labels.html).
It declares; it does not convert. Pass the result to
[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
with `use_value_labels = TRUE` to turn the declarations into factors
with text levels.

A `.sas7bdat` file stores a format's *name* (`YESNOF.`); the
code-to-text mapping lives in a `.sas7bcat` catalogue. The study corpus
has no catalogues, so this file is not a supplement to one - it is the
only place the mapping can come from. Because the declaration is written
into the same slot a catalogue would have filled, everything downstream
reads it without a second code path.

The function is safe to call unconditionally: a study with no
`value_labels.yml` gets its data back unchanged.

## Usage

``` r
apply_value_labels(data, value_labels_file = "value_labels.yml")
```

## Arguments

- data:

  A data frame whose coded columns should be declared.

- value_labels_file:

  Path to a YAML file of value-label declarations. Defaults to
  `"value_labels.yml"` in the current working directory. A path that
  does not exist is not an error.

## Value

`data`, with value labels attached to the declared columns via
[`labelled::val_labels()`](https://larmarange.github.io/labelled/reference/val_labels.html).
Columns not named in the file, and columns that already carry value
labels, are returned unchanged.

## Details

The file maps each variable to its codes, and each code to the text that
code means:


    disp:
      1: Home
      2: Rehab
      3: SNF
    approach:
      1: Ascending aorta only
      2: Ascending aorta plus arch

This is the home for enumerated level definitions, and it is
deliberately **not** the display label. Level definitions crammed into a
variable label are what forced them to be reconstructed by hand in every
table, and a label carrying eight mutually exclusive options cannot
survive `label_max` (see
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)).
Declaring them here keeps the two jobs apart: the converter reads this
file, and a table renderer reads the label.

Two rules worth knowing before relying on the result:

- **Value labels already on the column win.** A column that arrives
  labelled - from a catalogue, or from an earlier call - is left alone
  and the variable is named in a warning, so a declaration can never
  silently overwrite a mapping read from the source.

- **A variable named in the file but absent from the data is reported.**
  A typo that quietly declares nothing is the failure this file is least
  able to notice.

The `ordered` key is reserved for the ordinal declaration and is
**refused** rather than partly honoured. Ordinality is blocked on a
statistical decision; reserving the key now keeps one home for both
declarations without pre-empting it.

## See also

[`r_data_types`](https://ehrlinger.github.io/hvtiRutilities/reference/r_data_types.md)
for converting declarations to factors,
[`apply_label_overrides`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)
for the same pattern one level up - declaring *variable* labels rather
than value labels,
[`read_clinical_data`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.md)
for the `catalog_file` argument that would supply these mappings if a
catalogue existed.

## Examples

``` r
tmp <- tempfile(fileext = ".yml")
writeLines(c("disp:", "  1: Home", "  2: Rehab", "  3: SNF"), tmp)

dta <- data.frame(disp = c(1, 2, 1, 3))
dta <- apply_value_labels(dta, tmp)
labelled::val_labels(dta$disp)
#>  Home Rehab   SNF 
#>     1     2     3 

# Declare, then convert
r_data_types(dta, use_value_labels = TRUE)$disp
#> [1] Home  Rehab Home  SNF  
#> attr(,"label")
#> [1] disp
#> Levels: Home Rehab SNF

unlink(tmp)
```
