# Candidate pairs carrying the same information under unrelated names

**What this catches that pruning cannot.**
[`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md)
groups *transformations*, by stripping a known affix and finding the
parent. Two candidates that are numerically the same information but
share no affix relationship are invisible to it.

`male` and `female` are the case that got through a real screen: exact
complements, both offered, and 101 of 500 replicates selected **both**.
With a free `log_mu` a design holding both is singular, so those
replicates were fitting a rank-deficient model and nothing in the output
said so.

## Usage

``` r
pool_collinear_pairs(data, pool, threshold = 0.99)
```

## Arguments

- data:

  A data frame holding the candidate columns.

- pool:

  Character vector of candidate names.

- threshold:

  Absolute correlation at or above which a pair is reported.

## Value

A data frame with columns `var1`, `var2`, `r` and `complement`, ordered
by decreasing `abs(r)`. Empty when the pool is clean, so the caller
decides whether to warn, fail, or print it.

## Details

**Run it on the pool actually screened, after pruning.** On an unpruned
pool every `ln_x` correlates with its own `x` at ~1 and the report is a
wall of expected pairs. After pruning, anything flagged is something
pruning could not catch, which is exactly the set a human needs to look
at.

`complement` separates the two cases a reader treats differently: an
exact complement (`x + y == 1`) is a coding duplicate and one of the
pair should simply not be a candidate, while a high correlation between
genuinely different measurements is a judgement call about what the
model can identify.

## See also

[`concept_map`](https://ehrlinger.github.io/hvtiRutilities/reference/concept_map.md),
[`prune_to_one_form`](https://ehrlinger.github.io/hvtiRutilities/reference/prune_to_one_form.md)

## Examples

``` r
d <- data.frame(male = c(1, 0, 1, 0), female = c(0, 1, 0, 1),
                age = c(60, 71, 55, 68))
pool_collinear_pairs(d, c("male", "female", "age"))
#>   var1   var2  r complement
#> 1 male female -1       TRUE
```
