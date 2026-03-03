# Generate Synthetic Cardiac Surgery Survival Data

Creates a simulated dataset that mimics a cardiac surgery cohort,
suitable for testing survival analysis workflows in
`rf.survival.study.qmd`. Variable labels are attached via
[`labelled::var_label()`](https://larmarange.github.io/labelled/reference/var_label.html)
so they are compatible with `haven` and
[`hvtiRutilities::label_map()`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md).

## Usage

``` r
generate_survival_data(n = 500, seed = 1024)
```

## Arguments

- n:

  Integer. Number of patients to simulate. Default `500`.

- seed:

  Integer. Random seed passed to
  [`set.seed`](https://rdrr.io/r/base/Random.html) for reproducibility.
  Default `1024`.

## Value

A `data.frame` with `n` rows and 24 columns:

- ccfid:

  Character. Patient identifier (`"PT00001"`, …).

- origin_year:

  Integer. Calendar year corresponding to `iv_opyrs = 0` (randomly
  sampled between 1998 and 2018).

- iv_opyrs:

  Numeric. Observation interval length in years measured from
  `origin_year`; always greater than or equal to `iv_dead`.

- iv_dead:

  Numeric. Observed follow-up time in years (min of true survival time
  and administrative censoring time).

- dead:

  Integer. Event indicator: `1` = death, `0` = censored.

- reop:

  Integer. Reoperation indicator: `1` = yes, `0` = no.

- iv_reop:

  Numeric. Time to reoperation (years); `NA` if no reoperation.

- age:

  Numeric. Age at surgery in years (range 1–85).

- sex:

  Factor. `"Male"` / `"Female"` (55 / 45 %).

- bmi:

  Numeric. Body mass index in kg/m² (range 15–50).

- hgb_bs:

  Numeric. Baseline hemoglobin in g/dL (range 6–18).

- wbc_bs:

  Numeric. Baseline WBC count in K/µL (range 1.5–20).

- plate_bs:

  Numeric. Baseline platelet count in K/µL (range 50–500).

- gfr_bs:

  Numeric. Baseline eGFR in mL/min/1.73 m² (range 10–120).

- lvefvs_b:

  Numeric. Baseline LV ejection fraction in % (range 15–75).

- lvmass_b:

  Numeric. Baseline LV mass in g (range 60–400).

- lvmsi_b:

  Numeric. Baseline LV mass index in g/m² (range 40–220); derived as
  `lvmass_b / (bmi * 0.5)`.

- stvoli_b:

  Numeric. Baseline systolic stroke-volume index in mL/m² (range
  20–110).

- stvold_b:

  Numeric. Baseline diastolic stroke-volume index in mL/m² (range
  40–180).

- bypass_time:

  Numeric. Cardiopulmonary bypass time in minutes (range 20–240).

- xclamp_time:

  Numeric. Aortic cross-clamp time in minutes; sampled as 50–75 % of
  `bypass_time`.

- nyha_class:

  Ordered factor. NYHA functional class I–IV.

- diabetes:

  Factor. Diabetes mellitus: `"No"` / `"Yes"` (75 / 25 %).

- hypertension:

  Factor. Hypertension: `"No"` / `"Yes"` (55 / 45 %).

## Details

Survival times are drawn from a Weibull distribution (shape = 1.5,
~8-year median follow-up) with a linear predictor built from LVEF, age,
baseline hemoglobin, NYHA class, and eGFR. Administrative censoring is
applied uniformly between 1 and 15 years. Reoperation probability is
modelled via a logistic function of bypass time and NYHA class.

The returned data frame includes the five columns excluded from
`model_data` in the template (`ccfid`, `reop`, `iv_reop`, `origin_year`,
`iv_opyrs`), plus the survival outcome (`iv_dead`, `dead`) and 17
clinical predictors spanning demographics, pre-operative labs, cardiac
function, and surgical variables.

The global RNG state is saved and restored on exit, so calling this
function does not affect subsequent random number generation in the
session.

## See also

`rfsrc`, [`Surv`](https://rdrr.io/pkg/survival/man/Surv.html),
[`read_sas`](https://haven.tidyverse.org/reference/read_sas.html)

## Examples

``` r
dta <- generate_survival_data(n = 200, seed = 42)
str(dta)
#> 'data.frame':    200 obs. of  24 variables:
#>  $ ccfid       : chr  "PT00001" "PT00002" "PT00003" "PT00004" ...
#>   ..- attr(*, "label")= chr "Patient ID"
#>  $ origin_year : int  2018 2006 1999 2014 2009 2011 1999 2000 2017 2015 ...
#>   ..- attr(*, "label")= chr "Calendar year for iv_opyrs = 0"
#>  $ iv_opyrs    : num  3.77 3.99 8.64 13.54 2.28 ...
#>   ..- attr(*, "label")= chr "Observation interval (years) since origin_year"
#>  $ iv_dead     : num  3.77 2.76 8.64 9.16 2.28 3.72 0.77 5.65 1.09 5.97 ...
#>   ..- attr(*, "label")= chr "Follow-up time to death (years)"
#>  $ dead        : int  0 1 0 1 0 0 1 0 0 1 ...
#>   ..- attr(*, "label")= chr "Death indicator (1=dead, 0=censored)"
#>  $ reop        : int  0 1 0 0 0 1 1 0 0 0 ...
#>   ..- attr(*, "label")= chr "Reoperation (1=yes, 0=no)"
#>  $ iv_reop     : num  NA 1.81 NA NA NA 1.29 0.72 NA NA NA ...
#>   ..- attr(*, "label")= chr "Follow-up time to reoperation (years)"
#>  $ age         : num  65.6 36.5 50.4 54.5 51.1 43.4 67.7 43.6 75.3 44.1 ...
#>   ..- attr(*, "label")= chr "Age at surgery (years)"
#>  $ sex         : Factor w/ 2 levels "Female","Male": 2 2 1 2 1 2 1 2 2 2 ...
#>   ..- attr(*, "label")= chr "Sex"
#>  $ bmi         : num  27 30.8 27.2 30.7 26.3 26.7 29.4 32 20.8 26.8 ...
#>   ..- attr(*, "label")= chr "Body mass index (kg/m2)"
#>  $ hgb_bs      : num  14.9 14.6 13 13.2 11.7 12.6 11.1 11.3 10.8 14.5 ...
#>   ..- attr(*, "label")= chr "Baseline hemoglobin (g/dL)"
#>  $ wbc_bs      : num  8.24 8.48 5 6.69 4.98 5.91 4.48 4.71 9.07 6.82 ...
#>   ..- attr(*, "label")= chr "Baseline WBC count (K/uL)"
#>  $ plate_bs    : num  281 204 226 192 362 50 225 227 234 119 ...
#>   ..- attr(*, "label")= chr "Baseline platelet count (K/uL)"
#>  $ gfr_bs      : num  62 54.9 64.3 72.8 87 83.3 72.9 57.9 97.5 93.3 ...
#>   ..- attr(*, "label")= chr "Baseline eGFR (mL/min/1.73m2)"
#>  $ lvefvs_b    : num  43.1 48.4 65.9 60.1 53.6 53.9 62.5 52.8 55.7 38.5 ...
#>   ..- attr(*, "label")= chr "Baseline LV ejection fraction (%)"
#>  $ lvmass_b    : num  147 172 126 226 136 ...
#>   ..- attr(*, "label")= chr "Baseline LV mass (g)"
#>  $ lvmsi_b     : num  40 40 40 40 40 40 40 40 40 40 ...
#>   ..- attr(*, "label")= chr "Baseline LV mass index (g/m2)"
#>  $ stvoli_b    : num  76.7 53.7 31.4 74.4 56.3 69.5 84.1 71.2 49.7 53 ...
#>   ..- attr(*, "label")= chr "Baseline SV index - systolic (mL/m2)"
#>  $ stvold_b    : num  97.4 131.6 119.8 130.4 61.6 ...
#>   ..- attr(*, "label")= chr "Baseline SV index - diastolic (mL/m2)"
#>  $ bypass_time : num  72 118 88 62 71 73 96 106 77 80 ...
#>   ..- attr(*, "label")= chr "Cardiopulmonary bypass time (min)"
#>  $ xclamp_time : num  50 76 64 34 40 47 62 69 41 56 ...
#>   ..- attr(*, "label")= chr "Aortic cross-clamp time (min)"
#>  $ nyha_class  : Ord.factor w/ 4 levels "I"<"II"<"III"<..: 4 2 2 3 3 3 2 2 3 3 ...
#>   ..- attr(*, "label")= chr "NYHA functional class"
#>  $ diabetes    : Factor w/ 2 levels "No","Yes": 1 1 1 2 1 1 1 2 1 1 ...
#>   ..- attr(*, "label")= chr "Diabetes mellitus"
#>  $ hypertension: Factor w/ 2 levels "No","Yes": 1 1 2 1 2 2 2 1 2 1 ...
#>   ..- attr(*, "label")= chr "Hypertension"
table(dta$dead)          # event rate
#> 
#>   0   1 
#>  92 108 
summary(dta$iv_dead)     # follow-up distribution
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>   0.250   2.440   4.100   4.888   6.612  13.980 

# Drop admin columns to match model_data in the Quarto template
model_data <- dta[, !names(dta) %in% c("ccfid", "reop", "iv_reop",
  "origin_year", "iv_opyrs")]
```
