# Build a lookup map of data labels

Extracts variable labels from a labeled dataset and returns them as a
data frame with variable names (keys) and their corresponding labels.
This is particularly useful when working with SAS datasets that include
variable labels, or any dataset labeled with the `labelled` package.

A warning is issued when more than 50% of columns carry no label at all.
This typically indicates the data was imported from a source without
labels (e.g., plain CSV) and labels should be supplied via
[`add_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/add_labels.md)
or a `labels_overrides.yml` file (see
[`apply_label_overrides`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)).
A variable whose real label happens to equal its own name does **not**
count towards the threshold: the absent label is read as `NA` rather
than filled, so the two cases are distinguishable here even though
[`proc_contents`](https://ehrlinger.github.io/hvtiRutilities/reference/proc_contents.md)
cannot tell them apart.

Labels longer than `label_max` are cut for display. The cut breaks on a
word boundary and is marked with `...`, and the source text is kept in
`label_full` - truncation is a view, not a change to the data.
[`dataset_schema`](https://ehrlinger.github.io/hvtiRutilities/reference/dataset_schema.md)
deliberately has no such parameter: it records the label as the source
carried it, because a schema sidecar outlives the source dataset.

The variable-name fallback is **exempt** from the cap. A name standing
in for a missing label passes through whole, however long, and
`truncated` is `FALSE`. A truncated name would match nothing in the data
and would read as a deliberately short label rather than as a missing
one, destroying the signal the fallback exists to give.

**Labels that differ stay different.** Cutting each label on its own can
make two labels identical once their distinguishing ends are cut off.
Within one map, labels that differ in `label_full` always differ in
`label`. Each step below runs only on labels still over the cap or still
colliding:

1.  A heading, the text before the first `": "`, `" - "` or `"; "`,
    shared by two or more labels, one of them over the cap, is
    abbreviated in every label that carries it: to its entry in
    `abbreviations`, or else to the initials of its words, skipping
    small words such as "of" and "and". `"Surgical procedure"` becomes
    `"SP"`. A one-word heading is left alone, and two headings with the
    same initials are neither abbreviated.

2.  Any phrase in `abbreviations` is applied, whole words and ignoring
    case, to a label still over the cap. A label that fits is never
    abbreviated this way.

3.  The label is cut on a word boundary and marked.

4.  Cut labels that still collide keep both ends,
    `"Ascending aorta ... plus arch"`.

5.  A label that still collides is shown whole, over the cap, and
    `over_cap` marks it: a long label is a layout problem a reader can
    see, two identical labels a wrong figure nobody can.

The abbreviations actually shown come back as the `abbreviations`
attribute, to print as a key beneath a figure or table, and per variable
as the `abbreviations_by_key` attribute (`key`, `abbreviation`,
`expansion`), so a key under one section can list only what that
section's labels use.

## Usage

``` r
label_map(data, label_max = 40, abbreviations = NULL)
```

## Arguments

- data:

  A data frame, tibble, or similar object with variable labels
  (typically created using the `labelled` package or imported from SAS).

- label_max:

  Maximum length of a displayed label, in characters, including the
  `...` marker. Defaults to 40, the historical convention. Must be at
  least 4, so that a cut always has room to be marked; use `Inf` or `NA`
  to disable truncation. Does not apply to a variable name filled in for
  a missing label.

- abbreviations:

  `NULL`, or a named character vector in which each name is a phrase and
  each value is that phrase's abbreviation:
  `c("Left ventricular" = "LV")`. Used only on labels over the cap, and
  for a shared heading in place of its initials. An `expansion`
  attribute, as
  [`study_abbreviations`](https://ehrlinger.github.io/hvtiRutilities/reference/study_abbreviations.md)
  returns, names the term each abbreviation stands for in the key. A
  word-like abbreviation such as `"Preop"` takes the case of the text it
  replaces.

## Value

A data frame with five columns, and an `abbreviations` attribute: a data
frame of `abbreviation` and `expansion` for every abbreviation the
labels show, with no rows when there are none.

- key:

  Character vector of variable names from the input dataset

- label:

  Character vector of labels fit to print: the variable label cut to
  `label_max`, or the variable's own name where the source carries no
  label

- label_full:

  The label as the source carried it, never truncated, or the variable
  name where there is none

- truncated:

  Logical: `TRUE` where `label` was cut from `label_full`. Always
  `FALSE` for a filled variable name. `subset(x, truncated)` is the
  report of what was cut

- over_cap:

  Logical: `TRUE` where `label` is longer than `label_max` because every
  shorter form collided with another label. `subset(x, over_cap)` is the
  report

## See also

[`get_label`](https://ehrlinger.github.io/hvtiRutilities/reference/get_label.md)
for looking up a single label,
[`add_labels`](https://ehrlinger.github.io/hvtiRutilities/reference/add_labels.md)
for registering labels for derived variables,
[`apply_label_overrides`](https://ehrlinger.github.io/hvtiRutilities/reference/apply_label_overrides.md)
for applying study-specific overrides from a YAML file.

## Examples

``` r
# Generate labeled survival data
dta <- generate_survival_data(n = 50, seed = 42)
lmap <- label_map(dta)
head(lmap)
#>           key                                 label
#> 1       ccfid                            Patient ID
#> 2 origin_year        Calendar year for iv_opyrs = 0
#> 3    iv_opyrs Observation interval (years) since...
#> 4     iv_dead       Follow-up time to death (years)
#> 5        dead  Death indicator (1=dead, 0=censored)
#> 6        reop             Reoperation (1=yes, 0=no)
#>                                       label_full truncated over_cap
#> 1                                     Patient ID     FALSE    FALSE
#> 2                 Calendar year for iv_opyrs = 0     FALSE    FALSE
#> 3 Observation interval (years) since origin_year      TRUE    FALSE
#> 4                Follow-up time to death (years)     FALSE    FALSE
#> 5           Death indicator (1=dead, 0=censored)     FALSE    FALSE
#> 6                      Reoperation (1=yes, 0=no)     FALSE    FALSE

# Use for publication-ready tables
summary_vars <- c("age", "bmi", "hgb_bs")
tbl <- data.frame(
  variable = summary_vars,
  description = lmap$label[match(summary_vars, lmap$key)],
  mean = sapply(dta[summary_vars], mean)
)
print(tbl)
#>        variable                description   mean
#> age         age     Age at surgery (years) 44.464
#> bmi         bmi    Body mass index (kg/m2) 26.792
#> hgb_bs   hgb_bs Baseline hemoglobin (g/dL) 12.856

# With sample data (has labels)
dta <- sample_data(n = 20)
label_map(dta)
#>       key                label           label_full truncated over_cap
#> 1      id   Patient Identifier   Patient Identifier     FALSE    FALSE
#> 2 boolean     Binary Indicator     Binary Indicator     FALSE    FALSE
#> 3 logical       Logical Status       Logical Status     FALSE    FALSE
#> 4  f_real Random Uniform Value Random Uniform Value     FALSE    FALSE
#> 5   float  Random Normal Value  Random Normal Value     FALSE    FALSE
#> 6    char               Gender               Gender     FALSE    FALSE
#> 7  factor       Category Group       Category Group     FALSE    FALSE

# Which labels were cut, and what they were
subset(label_map(dta, label_max = 20), truncated)
#> [1] key        label      label_full truncated  over_cap  
#> <0 rows> (or 0-length row.names)

# Keep the source text
label_map(dta, label_max = Inf)
#>       key                label           label_full truncated over_cap
#> 1      id   Patient Identifier   Patient Identifier     FALSE    FALSE
#> 2 boolean     Binary Indicator     Binary Indicator     FALSE    FALSE
#> 3 logical       Logical Status       Logical Status     FALSE    FALSE
#> 4  f_real Random Uniform Value Random Uniform Value     FALSE    FALSE
#> 5   float  Random Normal Value  Random Normal Value     FALSE    FALSE
#> 6    char               Gender               Gender     FALSE    FALSE
#> 7  factor       Category Group       Category Group     FALSE    FALSE

# Labels sharing a heading keep what tells them apart, and the key says why
procs <- data.frame(avr = 1, mvr = 1)
attr(procs$avr, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
attr(procs$mvr, "label") <- "Surgical procedure: mitral valve repair"
lmap <- label_map(procs)
lmap$label
#> [1] "SP: aortic valve replacement with..."
#> [2] "SP: mitral valve repair"             
attr(lmap, "abbreviations")
#>   abbreviation          expansion
#> 1           SP Surgical procedure
```
