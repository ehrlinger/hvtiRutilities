# Pediatric Heart Network echocardiographic z-scores

Computes body-surface-area-adjusted z-scores for pediatric
echocardiographic measurements from the Pediatric Heart Network (PHN)
Normal Echocardiogram Database (Lopez et al., 2017), and the normal (z =
0) value for each child's BSA.

The PHN model indexes each measurement `X` to BSA raised to a
structure-specific power `alpha`, and the indexed value is normally
distributed with no residual dependence on BSA. So

`z = (X / BSA^alpha - mean) / sd`

with `alpha`, `mean` and `sd` from the paper's Table 2 (see
[`phn_zscore_table()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore_table.md)).
The predicted normal value is `mean * BSA^alpha`. For the three ratios
(`LVMTV`, `LVTTD`, `LVSI`) `alpha` is 0, so BSA does not change their
z-scores, though it must still be given, and a missing BSA gives `NA`.

## Usage

``` r
phn_zscore(x, structure, units, bsa = NULL, height_cm = NULL, weight_kg = NULL)
```

## Arguments

- x:

  Numeric vector of measurements.

- structure:

  Character, the paper's abbreviation for the structure measured (for
  example `"ANN"`); length 1, or the length of `x`.

- units:

  Character, the unit `x` is in (for example `"mm"`); length 1, or the
  length of `x`. Required; see Details.

- bsa:

  Numeric vector of body surface area in m^2, length 1 or the length of
  `x`. Give this or `height_cm` and `weight_kg`.

- height_cm, weight_kg:

  Numeric vectors of height in cm and weight in kg at the
  echocardiogram, length 1 or the length of `x`, used to compute BSA by
  [`bsa_haycock()`](https://ehrlinger.github.io/hvtiRutilities/reference/bsa_haycock.md).

## Value

A `data.frame` with one row per element of `x` and columns `structure`,
`x`, `units`, `bsa` (m^2), `predicted` (the normal value for that BSA,
in `units`), and `z`. `z` is `NA` where `x` or BSA is `NA`; `predicted`
does not depend on `x`, and is `NA` where BSA is `NA`. Both are `NA` for
a missing BSA even for the ratios, whose z-scores do not otherwise
depend on BSA.

## Details

**BSA.** Give `bsa` directly, or `height_cm` and `weight_kg`, from which
BSA is computed with the Haycock formula
([`bsa_haycock()`](https://ehrlinger.github.io/hvtiRutilities/reference/bsa_haycock.md)),
the formula the PHN used. Not both. Use the height and weight measured
at the echocardiogram: z-scores computed from birth weight and length
are not z-scores for the child that was imaged.

**Units.** `units` is required, so that a measurement recorded in mm is
never scored against a norm in cm. Linear structures accept `"mm"` or
`"cm"`, areas `"mm2"` or `"cm2"`; volumes must be `"ml"`, mass `"g"`,
`LVMTV` `"g/ml"` and `LVTTD` and `LVSI` `"none"`. The coronary arteries
are tabulated in mm in the paper, the other linear structures in cm;
either unit works for both.

**Structures.** `structure` takes the paper's abbreviations, listed with
their definitions by
[`phn_zscore_table()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore_table.md).
Among them: aortic annulus `ANN`, aortic root `ROOT`, sinotubular
junction `STJ`, ascending aorta `AAO`, pulmonary annulus `PVSAX` (short
axis) and `PVLAX` (long axis), main and branch pulmonary arteries `MPA`,
`RPA`, `LPA`, mitral and tricuspid diameters `MVAP`, `MVLAT`, `TVAP`,
`TVLAT`, and the LV dimensions `LVEDD`, `LVPWT`, `LVST`. Matching
ignores case.

The paper defines `ROOT` only as "aortic root diameter", measured in the
parasternal long axis (Table 2); the ParameterZ PHN calculator labels it
"Sinus of Valsalva". `LVEDA` is the LV short-axis end-diastolic *area*
(cm^2); it is not interchangeable with `LVEDD`, the end-diastolic
*diameter*, nor with an LV area traced in an apical view.

**Views and derived quantities.** A z-score is only as comparable as the
measurement behind it, so match the view: the `view` column of
[`phn_zscore_table()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore_table.md)
gives Table 2's view for each structure. Several structures were not
measured directly but computed from others, and should be scored only
when computed the same way:

- `MVA` and `TVA`, the valve areas, are ellipses from the two annular
  diameters, `pi/4 * AP * LAT`, not planimetered areas.

- `LVEDV` and `LVEDVEPI` are `5/6 * area * length` (the bullet formula).

- `LVM` is `1.05 * (LVEDVEPI - LVEDV)`.

- The ratios are `LVMTV = LVM / LVEDV`, `LVTTD = LVPWT / LVEDD` and
  `LVSI = LVEDL / LVEDD`.

**What the model does not include.** The paper found age, sex and race
effects that were statistically significant but under 5% in size, and so
clinically insignificant; the published z-score uses the single mean and
SD in Table 2, as here. The reference population is healthy, non-obese
children aged 0 to 18 years. Its exclusions (Data Supplement, Table 1)
include structural heart disease and a corrected gestational age under
37 weeks at enrollment, so a premature infant is scored against term
norms.

## References

Lopez L, Colan S, Stylianou M, et al. Relationship of echocardiographic
Z scores adjusted for body surface area to age, sex, race, and
ethnicity: the Pediatric Heart Network Normal Echocardiogram Database.
*Circ Cardiovasc Imaging*. 2017;10(11):e006979.
[doi:10.1161/CIRCIMAGING.117.006979](https://doi.org/10.1161/CIRCIMAGING.117.006979)
. Coefficients: Table 2. Z-score formula and worked example: Results,
after Table 2.

Haycock GB, Schwartz GJ, Wisotsky DH. Geometric method for measuring
body surface area: a height-weight formula validated in infants,
children, and adults. *J Pediatr*. 1978;93(1):62-66.
[doi:10.1016/s0022-3476(78)80601-5](https://doi.org/10.1016/s0022-3476%2878%2980601-5)

## See also

[`phn_zscore_table()`](https://ehrlinger.github.io/hvtiRutilities/reference/phn_zscore_table.md),
[`bsa_haycock()`](https://ehrlinger.github.io/hvtiRutilities/reference/bsa_haycock.md)

## Examples

``` r
# The paper's worked example: a mitral diameter of 11 mm at BSA 0.3 m^2
phn_zscore(11, "MVLAT", units = "mm", bsa = 0.3)
#>   structure  x units bsa predicted         z
#> 1     MVLAT 11    mm 0.3  12.21421 -1.007654

# Aortic annulus from height and weight at the echo
phn_zscore(c(7.5, 9, 12), "ANN", units = "mm",
           height_cm = c(52, 60, 75), weight_kg = c(3.8, 5.6, 9.4))
#>   structure    x units       bsa predicted         z
#> 1       ANN  7.5    mm 0.2382383  7.223830 0.4041496
#> 2       ANN  9.0    mm 0.3106097  8.248390 0.9632896
#> 3       ANN 12.0    mm 0.4483351  9.909759 2.2298055
```
