# Reproducible Seeds in R and SAS

## The Problem: Scattered Seeds

Any analysis that relies on random number generation — imputation,
bootstrap resampling, cross-validation, synthetic data — needs a
**seed** to be reproducible. Without one, results change every time the
script runs.

In practice, seeds often end up hard-coded in dozens of places:

``` r
# 01-imputation.R
set.seed(42)

# 02-model.R
set.seed(123)

# 03-sensitivity.R
set.seed(7)
```

This causes three problems:

1.  **Hunting.** When a reviewer asks “what seed was used?”, you have to
    search every script.
2.  **Drift.** A collaborator changes one seed to debug an issue and
    forgets to change it back.
3.  **Inconsistency.** Different scripts use different seeds for no
    principled reason, making it hard to reason about the combined
    analysis.

## The Fix: One Seed, One Place

Store a single seed in a project-level configuration file and read it at
the top of every script. The `config.yml` approach works well because
YAML is human-readable, language-agnostic, and already widely used for
project configuration.

### Create a `config.yml`

Place this file in the root of your study directory:

``` yaml
# config.yml
seed: 8675309
```

Pick any integer you like. The specific value does not matter — what
matters is that there is exactly **one** value and everyone on the
project uses it.

### Read it in R

``` r
cfg <- yaml::read_yaml("config.yml")
set.seed(cfg$seed)
```

Put these two lines at the top of each analysis script, immediately
after loading packages. Every downstream call to
[`rnorm()`](https://rdrr.io/r/stats/Normal.html),
[`sample()`](https://rdrr.io/r/base/sample.html),
[`runif()`](https://rdrr.io/r/stats/Uniform.html), etc. will draw from
the same reproducible sequence.

If a particular step needs its **own** isolated seed (e.g., a
sensitivity analysis), derive it from the project seed so the value is
still traceable:

``` r
cfg <- yaml::read_yaml("config.yml")
set.seed(cfg$seed + 1L)
```

### Using the Seed with randomForestSRC

The `randomForestSRC` package has its own `seed` argument on `rfsrc()`
(and related functions like `rfsrc.fast()`). Importantly, **it requires
a negative integer**. When `seed` is left at its default (`NULL`),
results are not reproducible across runs.

To use your project seed:

``` r
cfg <- yaml::read_yaml("config.yml")

rf <- randomForestSRC::rfsrc(
  Surv(time, status) ~ .,
  data = cohort,
  seed = -cfg$seed
)
```

Note the negation (`-cfg$seed`). The `randomForestSRC` C backend uses
the sign to activate its internal reproducibility mode, so a positive
value will be silently ignored or produce an error.

This seed is **independent** of R’s global RNG state — `rfsrc()` does
not call [`set.seed()`](https://rdrr.io/r/base/Random.html) internally.
That means you can (and should) use both:
[`set.seed()`](https://rdrr.io/r/base/Random.html) for any base-R
randomness in your script, and `seed = -cfg$seed` for the forest itself.

### Using the Seed with varPro

The `varPro` package (model-independent variable selection via
rule-based variable priority) also accepts a `seed` argument, following
the same convention as `randomForestSRC` — **negative integers only**:

``` r
cfg <- yaml::read_yaml("config.yml")

vp <- varPro::varpro(
  Surv(time, status) ~ .,
  data = cohort,
  seed = -cfg$seed
)
```

The same pattern applies to `varpro` helper functions such as
`unsupv.varpro()` when they expose a `seed` argument.

### Read it in SAS

SAS does not have a built-in YAML parser, but the seed value is easy to
extract with a simple `INFILE` / `INPUT` approach or with a macro
variable. The most portable method is to maintain a companion `seed.sas`
file that is generated from (or kept in sync with) the YAML:

``` sas
/* seed.sas — keep in sync with config.yml */
%let SEED = 8675309;
```

Then include it at the top of each SAS program:

``` sas
%include "seed.sas";

/* Example: bootstrap resampling */
proc surveyselect data=cohort out=boot
    method=urs              /* unrestricted random sampling */
    seed=&SEED              /* project-level seed            */
    reps=1000
    samprate=1;
run;
```

Many SAS procedures accept a `seed=` option directly, so you can pass
`&SEED` wherever a seed is needed:

| Procedure               | Seed Option                              |
|-------------------------|------------------------------------------|
| `PROC SURVEYSELECT`     | `seed=&SEED`                             |
| `PROC MI`               | `seed=&SEED`                             |
| `PROC MCMC`             | `seed=&SEED`                             |
| `PROC HPFOREST`         | `seed=&SEED`                             |
| `PROC GLMSELECT`        | `seed=&SEED` (via `PARTITION` statement) |
| `PROC IML` — `RANDSEED` | `call randseed(&SEED);`                  |
| Data Step — `RAND()`    | `call streaminit(&SEED);`                |

### Keeping R and SAS in Sync

If your project uses both languages, the simplest approach is to treat
`config.yml` as the single source of truth and either:

- **Manually** update `seed.sas` when `config.yml` changes (fine for
  small teams), or
- **Generate** `seed.sas` with a short R helper at the start of your
  pipeline:

``` r
cfg <- yaml::read_yaml("config.yml")
writeLines(
  sprintf("%%let SEED = %d;", cfg$seed),
  con = "seed.sas"
)
```

Either way, both languages consume the same integer, and there is one
file to update if the seed ever needs to change.

## How Seeds Work

A quick refresher on what
[`set.seed()`](https://rdrr.io/r/base/Random.html) actually does, since
the mental model matters when structuring a multi-script analysis.

### R

`set.seed(n)` initialises R’s pseudo-random number generator (PRNG) — by
default the Mersenne Twister — to a deterministic state. Every
subsequent call to a function that consumes randomness
([`rnorm()`](https://rdrr.io/r/stats/Normal.html),
[`sample()`](https://rdrr.io/r/base/sample.html),
[`runif()`](https://rdrr.io/r/stats/Uniform.html), etc.) advances the
PRNG by a fixed, deterministic amount. This means: - Same seed + same
code = same results, always. - Inserting or removing a random call
**upstream** changes every result **downstream**, because the PRNG
sequence shifts.

R also stores the generator state in `.Random.seed` in the global
environment. The `hvtiRutilities` function
[`generate_survival_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/generate_survival_data.md)
demonstrates best practice by saving and restoring `.Random.seed` via
[`on.exit()`](https://rdrr.io/r/base/on.exit.html), so the function does
not alter the caller’s RNG state.

### SAS

SAS procedures use their own internal PRNG, typically the Mersenne
Twister as well. The `seed=` option on each procedure initialises that
procedure’s generator independently — unlike R, where a single global
state is shared. This means: - Each `PROC` call with `seed=&SEED` starts
from the **same** initial state. - Adding or removing a `PROC` upstream
does **not** affect downstream procedures (they each re-seed
independently).

This is a key difference: in R, seed order matters globally; in SAS,
each procedure is self-contained.

### randomForestSRC / varPro

These packages use their own internal C-level PRNG, separate from R’s
global state. The `seed` argument (negative integer) initialises that
internal generator. Like SAS procedures, each call to `rfsrc()` or
`varpro()` with `seed = -cfg$seed` starts from the same initial state
regardless of what happened earlier in the R session.

### Implications for Multi-Script Projects

| Concern                     | R (`set.seed`)                                                        | SAS (`seed=`)                 | randomForestSRC / varPro (`seed=`) |
|-----------------------------|-----------------------------------------------------------------------|-------------------------------|------------------------------------|
| Seed scope                  | Global — governs everything until the next call                       | Per-procedure                 | Per-call (internal C PRNG)         |
| Script ordering sensitivity | High — reordering random calls changes results                        | Low — each procedure re-seeds | Low — each call re-seeds           |
| Sign convention             | Positive integer                                                      | Positive integer              | **Negative** integer               |
| Best practice               | [`set.seed()`](https://rdrr.io/r/base/Random.html) once at script top | `seed=&SEED` on every proc    | `seed = -cfg$seed` on every call   |

## Checklist

Create `config.yml` with a single `seed:` key in the project root.

Add `yaml` to your R dependencies (or use `config::get()` if you prefer
the `config` package).

Begin every R analysis script with
`cfg <- yaml::read_yaml("config.yml"); set.seed(cfg$seed)`.

If using SAS, create `seed.sas` with `%let SEED = <value>;` and
`%include` it in every program.

Pass `seed = -cfg$seed` to every `rfsrc()` and `varpro()` call.

Document the seed value in your study’s README or statistical analysis
plan.

If a step needs its own seed, derive it from the project seed (e.g.,
`cfg$seed + 1L`) and document why.
