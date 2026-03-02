##=============================================================================
## generate_survival_data.R
##=============================================================================

#' Generate Synthetic Cardiac Surgery Survival Data
#'
#' Creates a simulated dataset that mimics a cardiac surgery cohort, suitable
#' for testing survival analysis workflows in \file{rf.survival.study.qmd}.
#' Variable labels are attached via \code{labelled::var_label()} so they are
#' compatible with \code{haven} and \code{hvtiRutilities::label_map()}.
#'
#' @details
#' Survival times are drawn from a Weibull distribution (shape = 1.5,
#' ~8-year median follow-up) with a linear predictor built from LVEF, age,
#' baseline hemoglobin, NYHA class, and eGFR. Administrative censoring is
#' applied uniformly between 1 and 15 years. Reoperation probability is
#' modelled via a logistic function of bypass time and NYHA class.
#'
#' The returned data frame includes the three columns excluded from
#' \code{model_data} in the template (\code{ccfid}, \code{reop},
#' \code{iv_reop}), plus the survival outcome (\code{iv_dead}, \code{dead})
#' and 17 clinical predictors spanning demographics, pre-operative labs,
#' cardiac function, and surgical variables.
#'
#' The global RNG state is saved and restored on exit, so calling this
#' function does not affect subsequent random number generation in the session.
#'
#' @param n Integer. Number of patients to simulate. Default \code{500}.
#' @param seed Integer. Random seed passed to \code{\link{set.seed}} for
#'   reproducibility. Default \code{1024}.
#'
#' @return A \code{data.frame} with \code{n} rows and 22 columns:
#' \describe{
#'   \item{ccfid}{Character. Patient identifier (\code{"PT00001"}, …).}
#'   \item{iv_dead}{Numeric. Observed follow-up time in years (min of true
#'     survival time and administrative censoring time).}
#'   \item{dead}{Integer. Event indicator: \code{1} = death, \code{0} =
#'     censored.}
#'   \item{reop}{Integer. Reoperation indicator: \code{1} = yes,
#'     \code{0} = no.}
#'   \item{iv_reop}{Numeric. Time to reoperation (years); \code{NA} if no
#'     reoperation.}
#'   \item{age}{Numeric. Age at surgery in years (range 1–85).}
#'   \item{sex}{Factor. \code{"Male"} / \code{"Female"} (55 / 45 \%).}
#'   \item{bmi}{Numeric. Body mass index in kg/m² (range 15–50).}
#'   \item{hgb_bs}{Numeric. Baseline hemoglobin in g/dL (range 6–18).}
#'   \item{wbc_bs}{Numeric. Baseline WBC count in K/µL (range 1.5–20).}
#'   \item{plate_bs}{Numeric. Baseline platelet count in K/µL (range 50–500).}
#'   \item{gfr_bs}{Numeric. Baseline eGFR in mL/min/1.73 m² (range 10–120).}
#'   \item{lvefvs_b}{Numeric. Baseline LV ejection fraction in \% (range
#'     15–75).}
#'   \item{lvmass_b}{Numeric. Baseline LV mass in g (range 60–400).}
#'   \item{lvmsi_b}{Numeric. Baseline LV mass index in g/m² (range 40–220);
#'     derived as \code{lvmass_b / (bmi * 0.5)}.}
#'   \item{stvoli_b}{Numeric. Baseline systolic stroke-volume index in mL/m²
#'     (range 20–110).}
#'   \item{stvold_b}{Numeric. Baseline diastolic stroke-volume index in mL/m²
#'     (range 40–180).}
#'   \item{bypass_time}{Numeric. Cardiopulmonary bypass time in minutes
#'     (range 20–240).}
#'   \item{xclamp_time}{Numeric. Aortic cross-clamp time in minutes; sampled
#'     as 50–75 \% of \code{bypass_time}.}
#'   \item{nyha_class}{Ordered factor. NYHA functional class I–IV.}
#'   \item{diabetes}{Factor. Diabetes mellitus: \code{"No"} / \code{"Yes"}
#'     (75 / 25 \%).}
#'   \item{hypertension}{Factor. Hypertension: \code{"No"} / \code{"Yes"}
#'     (55 / 45 \%).}
#' }
#'
#' @seealso
#' \code{\link[randomForestSRC]{rfsrc}},
#' \code{\link[survival]{Surv}},
#' \code{\link[haven]{read_sas}}
#'
#' @importFrom labelled var_label
#' @importFrom stats rnorm rweibull runif rbinom plogis
#' 
#' @export
#'
#' @examples
#' dta <- generate_survival_data(n = 200, seed = 42)
#' str(dta)
#' table(dta$dead)          # event rate
#' summary(dta$iv_dead)     # follow-up distribution
#'
#' # Drop admin columns to match model_data in the Quarto template
#' model_data <- dta[, !names(dta) %in% c("ccfid", "reop", "iv_reop")]
generate_survival_data <- function(n = 500, seed = 1024) {
  # Save and restore global RNG state to avoid side effects on the session
  old_rng_state <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    .GlobalEnv$.Random.seed
  } else {
    NULL
  }
  on.exit({
    if (is.null(old_rng_state)) {
      suppressWarnings(rm(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
    } else {
      assign(".Random.seed", old_rng_state, envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)

  ## ---- Patient IDs ----
  ccfid <- paste0("PT", formatC(seq_len(n), width = 5, flag = "0"))

  ## ---- Demographics ----
  age       <- round(rnorm(n, mean = 45, sd = 15), 1)   # age at surgery (years)
  age       <- pmax(1, pmin(age, 85))
  sex       <- factor(sample(c("Male", "Female"), n, replace = TRUE, prob = c(0.55, 0.45)))
  bmi       <- round(rnorm(n, mean = 27, sd = 5), 1)
  bmi       <- pmax(15, pmin(bmi, 50))

  ## ---- Pre-operative labs ----
  hgb_bs    <- round(rnorm(n, mean = 13.0, sd = 1.8), 1)  # baseline hemoglobin (g/dL)
  hgb_bs    <- pmax(6, pmin(hgb_bs, 18))

  wbc_bs    <- round(rnorm(n, mean = 7.5, sd = 2.5), 2)   # WBC (K/uL)
  wbc_bs    <- pmax(1.5, pmin(wbc_bs, 20))

  plate_bs  <- round(rnorm(n, mean = 220, sd = 65), 0)    # platelets (K/uL)
  plate_bs  <- pmax(50, pmin(plate_bs, 500))

  gfr_bs    <- round(rnorm(n, mean = 75, sd = 20), 1)     # eGFR (mL/min/1.73m2)
  gfr_bs    <- pmax(10, pmin(gfr_bs, 120))

  ## ---- Pre-operative cardiac function ----
  lvefvs_b  <- round(rnorm(n, mean = 55, sd = 10), 1)     # LVEF (%)
  lvefvs_b  <- pmax(15, pmin(lvefvs_b, 75))

  lvmass_b  <- round(rnorm(n, mean = 180, sd = 55), 1)    # LV mass (g)
  lvmass_b  <- pmax(60, pmin(lvmass_b, 400))

  lvmsi_b   <- round(lvmass_b / (bmi * 0.5), 1)           # LV mass index (g/m2, approx)
  lvmsi_b   <- pmax(40, pmin(lvmsi_b, 220))

  stvoli_b  <- round(rnorm(n, mean = 55, sd = 15), 1)     # SV indexed - systolic (mL/m2)
  stvoli_b  <- pmax(20, pmin(stvoli_b, 110))

  stvold_b  <- round(rnorm(n, mean = 95, sd = 25), 1)     # SV indexed - diastolic (mL/m2)
  stvold_b  <- pmax(40, pmin(stvold_b, 180))

  ## ---- Surgical variables ----
  bypass_time  <- round(rnorm(n, mean = 90, sd = 30), 0)  # cardiopulmonary bypass time (min)
  bypass_time  <- pmax(20, pmin(bypass_time, 240))

  xclamp_time  <- round(bypass_time * runif(n, 0.5, 0.75), 0)  # cross-clamp time (min)

  nyha_class   <- factor(
    sample(c("I", "II", "III", "IV"), n, replace = TRUE, prob = c(0.2, 0.4, 0.3, 0.1)),
    levels = c("I", "II", "III", "IV"), ordered = TRUE
  )

  diabetes     <- factor(
    sample(c("No", "Yes"), n, replace = TRUE, prob = c(0.75, 0.25))
  )

  hypertension <- factor(
    sample(c("No", "Yes"), n, replace = TRUE, prob = c(0.55, 0.45))
  )

  ## ---- Survival outcome ----
  ## Baseline hazard influenced by LVEF, age, hemoglobin, and NYHA class
  lp <- -0.03 * lvefvs_b +
    0.02 * age +
    -0.08 * hgb_bs +
    0.3 * (as.integer(nyha_class) - 1) +
    -0.01 * gfr_bs

  lp <- lp - mean(lp)   # center

  # Weibull shape = 1.5, scale varies by linear predictor
  shape_surv <- 1.5
  scale_surv <- exp(-lp / shape_surv) * 8   # ~8-year median follow-up

  iv_dead <- round(rweibull(n, shape = shape_surv, scale = scale_surv), 2)

  # Administrative censoring at 15 years
  censor_time <- runif(n, min = 1, max = 15)
  dead        <- as.integer(iv_dead <= censor_time)
  iv_dead     <- pmin(iv_dead, censor_time)

  ## ---- Reoperation ----
  reop_prob   <- plogis(-2.5 + 0.01 * bypass_time + 0.02 * (as.integer(nyha_class) - 1))
  reop        <- as.integer(rbinom(n, 1, prob = reop_prob))
  iv_reop     <- ifelse(reop == 1,
                        round(runif(n, min = 0, max = iv_dead), 2),
                        NA_real_)

  ## ---- Assemble data frame ----
  dta <- data.frame(
    ccfid,
    iv_dead, dead,
    reop, iv_reop,
    age, sex, bmi,
    hgb_bs, wbc_bs, plate_bs, gfr_bs,
    lvefvs_b, lvmass_b, lvmsi_b, stvoli_b, stvold_b,
    bypass_time, xclamp_time,
    nyha_class, diabetes, hypertension,
    stringsAsFactors = FALSE
  )

  ## ---- Variable labels ----
  labelled::var_label(dta) <- list(
    ccfid        = "Patient ID",
    iv_dead      = "Follow-up time to death (years)",
    dead         = "Death indicator (1=dead, 0=censored)",
    reop         = "Reoperation (1=yes, 0=no)",
    iv_reop      = "Follow-up time to reoperation (years)",
    age          = "Age at surgery (years)",
    sex          = "Sex",
    bmi          = "Body mass index (kg/m2)",
    hgb_bs       = "Baseline hemoglobin (g/dL)",
    wbc_bs       = "Baseline WBC count (K/uL)",
    plate_bs     = "Baseline platelet count (K/uL)",
    gfr_bs       = "Baseline eGFR (mL/min/1.73m2)",
    lvefvs_b     = "Baseline LV ejection fraction (%)",
    lvmass_b     = "Baseline LV mass (g)",
    lvmsi_b      = "Baseline LV mass index (g/m2)",
    stvoli_b     = "Baseline SV index - systolic (mL/m2)",
    stvold_b     = "Baseline SV index - diastolic (mL/m2)",
    bypass_time  = "Cardiopulmonary bypass time (min)",
    xclamp_time  = "Aortic cross-clamp time (min)",
    nyha_class   = "NYHA functional class",
    diabetes     = "Diabetes mellitus",
    hypertension = "Hypertension"
  )

  dta
}
