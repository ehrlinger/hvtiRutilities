# Pediatric Heart Network (PHN) echocardiographic z-scores.
#
# Every coefficient below is transcribed from Table 2 of Lopez et al. (2017),
# "Relationship of Echocardiographic Z-Scores Adjusted for Body Surface Area to
# Age, Sex, Race, and Ethnicity: The Pediatric Heart Network Normal
# Echocardiogram Database", Circ Cardiovasc Imaging 10(11):e006979,
# doi:10.1161/CIRCIMAGING.117.006979 (PMC5812349). Columns used: Unit, alpha,
# Mean, SD. Nothing is fitted, interpolated or rounded here. The paper's own
# z-score formula and worked example are in its Results, just after Table 2.
.PHN_TABLE2 <- data.frame(
  structure = c(
    "MVAP", "MVLAT", "MVA", "TVAP", "TVLAT", "TVA",
    "ANN", "ROOT", "STJ", "AAO", "ARCHPROX", "ARCHDIST", "ISTH",
    "LMCA", "LAD", "RCA",
    "PVSAX", "PVLAX", "MPA", "RPA", "LPA",
    "LVEDD", "LVPWT", "LVST", "LVEDL", "LVEDLEPI", "LVEDA", "LVEDAEPI",
    "LVEDV", "LVEDVEPI", "LVM", "LVMTV", "LVTTD", "LVSI"
  ),
  unit = c(
    "cm", "cm", "cm2", "cm", "cm", "cm2",
    "cm", "cm", "cm", "cm", "cm", "cm", "cm",
    "mm", "mm", "mm",
    "cm", "cm", "cm", "cm", "cm",
    "cm", "cm", "cm", "cm", "cm", "cm2", "cm2",
    "ml", "ml", "g", "g/ml", "none", "none"
  ),
  alpha = c(
    0.50, 0.50, 1.00, 0.50, 0.50, 1.00,
    0.50, 0.50, 0.50, 0.50, 0.50, 0.50, 0.50,
    0.45, 0.45, 0.45,
    0.50, 0.50, 0.50, 0.50, 0.50,
    0.45, 0.40, 0.40, 0.45, 0.45, 0.90, 0.90,
    1.30, 1.30, 1.25, 0, 0, 0
  ),
  mean = c(
    2.31, 2.23, 4.06, 2.36, 2.36, 4.39,
    1.48, 2.06, 1.69, 1.79, 1.53, 1.36, 1.25,
    2.95, 1.90, 2.32,
    1.91, 2.01, 1.82, 1.07, 1.10,
    3.89, 0.57, 0.58, 6.31, 6.87, 11.91, 20.00,
    62.02, 113.14, 53.02, 0.88, 0.15, 1.63
  ),
  sd = c(
    0.24, 0.22, 0.68, 0.28, 0.29, 0.83,
    0.14, 0.18, 0.16, 0.18, 0.23, 0.19, 0.18,
    0.57, 0.34, 0.55,
    0.24, 0.28, 0.24, 0.18, 0.18,
    0.33, 0.09, 0.09, 0.46, 0.45, 1.89, 2.59,
    11.94, 17.85, 9.06, 0.16, 0.03, 0.17
  ),
  # Definitions from Table 2's "Parameter Abbreviations" footnote.
  label = c(
    "Mitral anteroposterior diameter",
    "Mitral lateral diameter",
    "Mitral area",
    "Tricuspid anteroposterior diameter",
    "Tricuspid lateral diameter",
    "Tricuspid area",
    "Aortic annular diameter",
    "Aortic root diameter",
    "Sinotubular junction",
    "Ascending aortic diameter",
    "Proximal transverse arch diameter",
    "Distal transverse arch diameter",
    "Aortic isthmus diameter",
    "Left main coronary artery diameter",
    "Proximal left anterior descending coronary artery diameter",
    "Proximal right coronary artery diameter",
    "Pulmonary annular short-axis diameter",
    "Pulmonary annular long-axis diameter",
    "Main pulmonary artery diameter",
    "Right pulmonary artery diameter",
    "Left pulmonary artery diameter",
    "LV short-axis end-diastolic endocardial diameter",
    "LV short-axis end-diastolic posterior wall thickness",
    "LV short-axis end-diastolic septal thickness",
    "LV long-axis end-diastolic endocardial length",
    "LV long-axis end-diastolic epicardial length",
    "LV short-axis end-diastolic endocardial area",
    "LV short-axis end-diastolic epicardial area",
    "LV short-axis end-diastolic endocardial volume",
    "LV short-axis end-diastolic epicardial volume",
    "LV mass",
    "LV mass-to-volume ratio",
    "LV thickness-to-dimension ratio",
    "LV sphericity index"
  ),
  # Table 2 column "Echocardiographic View or Formula". The formula rows are
  # derived from other measurements, not measured directly.
  view = c(
    "Parasternal long axis",                      # MVAP
    "Apical 4 chamber",                           # MVLAT
    "pi/4 * MVAP * MVLAT",                        # MVA
    "Parasternal long axis",                      # TVAP
    "Apical 4 chamber",                           # TVLAT
    "pi/4 * TVAP * TVLAT",                        # TVA
    "Parasternal long axis",                      # ANN
    "Parasternal long axis",                      # ROOT
    "Parasternal long axis",                      # STJ
    "Parasternal long axis",                      # AAO
    "Suprasternal long axis",                     # ARCHPROX
    "Suprasternal long axis",                     # ARCHDIST
    "Suprasternal long axis",                     # ISTH
    "Parasternal short axis",                     # LMCA
    "Parasternal short axis",                     # LAD
    "Parasternal short axis",                     # RCA
    "Parasternal short axis",                     # PVSAX
    "Parasternal long axis",                      # PVLAX
    "Parasternal short axis",                     # MPA
    "Parasternal short axis",                     # RPA
    "Parasternal short axis",                     # LPA
    "Parasternal short axis",                     # LVEDD
    "Parasternal short axis",                     # LVPWT
    "Parasternal short axis",                     # LVST
    "Apical 4 chamber",                           # LVEDL
    "Apical 4 chamber",                           # LVEDLEPI
    "Parasternal short axis",                     # LVEDA
    "Parasternal short axis",                     # LVEDAEPI
    "5/6 * LVEDA * LVEDL",                        # LVEDV
    "5/6 * LVEDAEPI * LVEDLEPI",                  # LVEDVEPI
    "1.05 * (LVEDVEPI - LVEDV)",                  # LVM
    "LVM / LVEDV",                                # LVMTV
    "LVPWT / LVEDD",                              # LVTTD
    "LVEDL / LVEDD"                               # LVSI
  ),
  stringsAsFactors = FALSE
)

# Units a caller may give for each Table 2 unit, with the factor that converts
# the caller's value to the Table 2 unit.
.PHN_UNIT_FACTORS <- list(
  "cm"   = c(cm = 1, mm = 0.1),
  "mm"   = c(mm = 1, cm = 10),
  "cm2"  = c(cm2 = 1, mm2 = 0.01),
  "ml"   = c(ml = 1),
  "g"    = c(g = 1),
  "g/ml" = c("g/ml" = 1),
  "none" = c(none = 1)
)

#' Body surface area by the Haycock formula
#'
#' @description
#' Computes body surface area (BSA) from height and weight with the formula of
#' Haycock, Schwartz and Wisotsky (1978):
#' `BSA (m^2) = 0.024265 * weight(kg)^0.5378 * height(cm)^0.3964`.
#' This is the formula the Pediatric Heart Network used for its echocardiographic
#' z-scores, so it is the one [phn_zscore()] uses.
#'
#' Give the height and weight measured at the echocardiogram, not at birth.
#'
#' @param height_cm Numeric vector of heights (lengths, for infants) in cm.
#' @param weight_kg Numeric vector of weights in kg, the same length as
#'   `height_cm` or length 1.
#'
#' @return A numeric vector of BSA in m^2, `NA` where either input is `NA`.
#'
#' @references
#' Haycock GB, Schwartz GJ, Wisotsky DH. Geometric method for measuring body
#' surface area: a height-weight formula validated in infants, children, and
#' adults. *J Pediatr*. 1978;93(1):62-66. \doi{10.1016/s0022-3476(78)80601-5}
#'
#' @seealso [phn_zscore()]
#' @export
#' @examples
#' bsa_haycock(height_cm = 50, weight_kg = 3.5)
bsa_haycock <- function(height_cm, weight_kg) {
  if (!is.numeric(height_cm) || !is.numeric(weight_kg)) {
    stop("bsa_haycock(): `height_cm` and `weight_kg` must be numeric.", call. = FALSE)
  }
  n <- max(length(height_cm), length(weight_kg))
  if (!length(height_cm) %in% c(1L, n) || !length(weight_kg) %in% c(1L, n)) {
    stop("bsa_haycock(): `height_cm` and `weight_kg` must have the same length, or length 1.", call. = FALSE)
  }
  bad <- function(v) any(!is.na(v) & (!is.finite(v) | v <= 0))
  if (bad(height_cm) || bad(weight_kg)) {
    stop("bsa_haycock(): `height_cm` and `weight_kg` must be positive and finite (or `NA`).", call. = FALSE)
  }
  0.024265 * weight_kg^0.5378 * height_cm^0.3964
}

#' The Pediatric Heart Network z-score coefficients
#'
#' @description
#' Returns the coefficients [phn_zscore()] uses, exactly as published in
#' Table 2 of Lopez et al. (2017): for each structure, its unit, the BSA
#' exponent `alpha`, and the mean and standard deviation of the indexed value
#' `measurement / BSA^alpha`, with the echocardiographic view it was measured
#' in or the formula it was derived by.
#'
#' @return A `data.frame` with one row per structure (34 rows) and columns
#'   `structure` (the paper's abbreviation), `label` (the paper's definition),
#'   `view` (Table 2's "Echocardiographic View or Formula"), `unit` (the unit
#'   the mean and SD are in), `alpha`, `mean` and `sd`.
#'
#' @references
#' Lopez L, Colan S, Stylianou M, et al. Relationship of echocardiographic
#' Z scores adjusted for body surface area to age, sex, race, and ethnicity:
#' the Pediatric Heart Network Normal Echocardiogram Database.
#' *Circ Cardiovasc Imaging*. 2017;10(11):e006979, Table 2.
#' \doi{10.1161/CIRCIMAGING.117.006979}
#'
#' @seealso [phn_zscore()]
#' @export
#' @examples
#' subset(phn_zscore_table(), structure %in% c("ANN", "ROOT", "STJ", "AAO"))
phn_zscore_table <- function() {
  .PHN_TABLE2[c("structure", "label", "view", "unit", "alpha", "mean", "sd")]
}

#' Pediatric Heart Network echocardiographic z-scores
#'
#' @description
#' Computes body-surface-area-adjusted z-scores for pediatric echocardiographic
#' measurements from the Pediatric Heart Network (PHN) Normal Echocardiogram
#' Database (Lopez et al., 2017), and the normal (z = 0) value for each child's
#' BSA.
#'
#' The PHN model indexes each measurement `X` to BSA raised to a
#' structure-specific power `alpha`, and the indexed value is normally
#' distributed with no residual dependence on BSA. So
#'
#' `z = (X / BSA^alpha - mean) / sd`
#'
#' with `alpha`, `mean` and `sd` from the paper's Table 2 (see
#' [phn_zscore_table()]). The predicted normal value is `mean * BSA^alpha`.
#' For the three ratios (`LVMTV`, `LVTTD`, `LVSI`) `alpha` is 0, so BSA
#' does not change their z-scores, though it must still be given, and a
#' missing BSA gives `NA`.
#'
#' @details
#' **BSA.** Give `bsa` directly, or `height_cm` and `weight_kg`, from which BSA
#' is computed with the Haycock formula ([bsa_haycock()]), the formula the PHN
#' used. Not both. Use the height and weight measured at the echocardiogram:
#' z-scores computed from birth weight and length are not z-scores for the
#' child that was imaged.
#'
#' **Units.** `units` is required, so that a measurement recorded in mm is
#' never scored against a norm in cm. Linear structures accept `"mm"` or
#' `"cm"`, areas `"mm2"` or `"cm2"`; volumes must be `"ml"`, mass `"g"`,
#' `LVMTV` `"g/ml"` and `LVTTD` and `LVSI` `"none"`. The coronary arteries are
#' tabulated in mm in the paper, the other linear structures in cm; either unit
#' works for both.
#'
#' **Structures.** `structure` takes the paper's abbreviations, listed with
#' their definitions by [phn_zscore_table()]. Among them: aortic annulus `ANN`,
#' aortic root `ROOT`, sinotubular junction `STJ`, ascending aorta `AAO`,
#' pulmonary annulus `PVSAX` (short axis) and `PVLAX` (long axis), main and
#' branch pulmonary arteries `MPA`, `RPA`, `LPA`, mitral and tricuspid
#' diameters `MVAP`, `MVLAT`, `TVAP`, `TVLAT`, and the LV dimensions `LVEDD`,
#' `LVPWT`, `LVST`. Matching ignores case.
#'
#' The paper defines `ROOT` only as "aortic root diameter", measured in the
#' parasternal long axis (Table 2); the ParameterZ PHN calculator labels it
#' "Sinus of Valsalva".
#' `LVEDA` is the LV short-axis end-diastolic *area* (cm^2); it is not
#' interchangeable with `LVEDD`, the end-diastolic *diameter*, nor with an LV
#' area traced in an apical view.
#'
#' **Views and derived quantities.** A z-score is only as comparable as the
#' measurement behind it, so match the view: the `view` column of
#' [phn_zscore_table()] gives Table 2's view for each structure. Several
#' structures were not measured directly but computed from others, and
#' should be scored only when computed the same way:
#' * `MVA` and `TVA`, the valve areas, are ellipses from the two annular
#'   diameters, `pi/4 * AP * LAT`, not planimetered areas.
#' * `LVEDV` and `LVEDVEPI` are `5/6 * area * length` (the bullet formula).
#' * `LVM` is `1.05 * (LVEDVEPI - LVEDV)`.
#' * The ratios are `LVMTV = LVM / LVEDV`, `LVTTD = LVPWT / LVEDD` and
#'   `LVSI = LVEDL / LVEDD`.
#'
#' **What the model does not include.** The paper found age, sex and race
#' effects that were statistically significant but under 5% in size, and so
#' clinically insignificant; the published z-score uses the single mean and
#' SD in Table 2, as here. The reference population is healthy, non-obese
#' children aged 0 to 18 years. Its exclusions (Data Supplement, Table 1)
#' include structural heart disease and a corrected gestational age under 37
#' weeks at enrollment, so a premature infant is scored against term norms.
#'
#' @param x Numeric vector of measurements.
#' @param structure Character, the paper's abbreviation for the structure
#'   measured (for example `"ANN"`); length 1, or the length of `x`.
#' @param units Character, the unit `x` is in (for example `"mm"`); length 1,
#'   or the length of `x`. Required; see Details.
#' @param bsa Numeric vector of body surface area in m^2, length 1 or the
#'   length of `x`. Give this or `height_cm` and `weight_kg`.
#' @param height_cm,weight_kg Numeric vectors of height in cm and weight in
#'   kg at the echocardiogram, length 1 or the length of `x`, used to compute
#'   BSA by [bsa_haycock()].
#'
#' @return A `data.frame` with one row per element of `x` and columns
#'   `structure`, `x`, `units`, `bsa` (m^2), `predicted` (the normal value for
#'   that BSA, in `units`), and `z`. `z` is `NA` where `x` or BSA is `NA`;
#'   `predicted` does not depend on `x`, and is `NA` where BSA is `NA`. Both
#'   are `NA` for a missing BSA even for the ratios, whose z-scores do not
#'   otherwise depend on BSA.
#'
#' @references
#' Lopez L, Colan S, Stylianou M, et al. Relationship of echocardiographic
#' Z scores adjusted for body surface area to age, sex, race, and ethnicity:
#' the Pediatric Heart Network Normal Echocardiogram Database.
#' *Circ Cardiovasc Imaging*. 2017;10(11):e006979.
#' \doi{10.1161/CIRCIMAGING.117.006979}. Coefficients: Table 2. Z-score
#' formula and worked example: Results, after Table 2.
#'
#' Haycock GB, Schwartz GJ, Wisotsky DH. Geometric method for measuring body
#' surface area: a height-weight formula validated in infants, children, and
#' adults. *J Pediatr*. 1978;93(1):62-66. \doi{10.1016/s0022-3476(78)80601-5}
#'
#' @seealso [phn_zscore_table()], [bsa_haycock()]
#' @export
#' @examples
#' # The paper's worked example: a mitral diameter of 11 mm at BSA 0.3 m^2
#' phn_zscore(11, "MVLAT", units = "mm", bsa = 0.3)
#'
#' # Aortic annulus from height and weight at the echo
#' phn_zscore(c(7.5, 9, 12), "ANN", units = "mm",
#'            height_cm = c(52, 60, 75), weight_kg = c(3.8, 5.6, 9.4))
phn_zscore <- function(x, structure, units, bsa = NULL, height_cm = NULL, weight_kg = NULL) {
  if (!is.numeric(x)) {
    stop("phn_zscore(): `x` must be numeric.", call. = FALSE)
  }
  n <- length(x)
  if (missing(structure) || !is.character(structure)) {
    stop("phn_zscore(): `structure` must be a character vector of Table 2 abbreviations, e.g. \"ANN\".", call. = FALSE)
  }
  if (missing(units) || !is.character(units)) {
    stop("phn_zscore(): `units` is required, e.g. units = \"mm\".", call. = FALSE)
  }
  recycle <- function(v, arg) {
    if (length(v) == n) return(v)
    if (length(v) == 1L) return(rep(v, n))
    stop("phn_zscore(): `", arg, "` must have length 1 or the length of `x` (", n, ").", call. = FALSE)
  }
  structure <- recycle(toupper(structure), "structure")
  units <- recycle(tolower(units), "units")

  have_bsa <- !is.null(bsa)
  have_hw <- !is.null(height_cm) || !is.null(weight_kg)
  if (have_bsa && have_hw) {
    stop("phn_zscore(): give `bsa` or `height_cm` and `weight_kg`, not both.", call. = FALSE)
  }
  if (!have_bsa && !have_hw) {
    stop("phn_zscore(): give `bsa`, or `height_cm` and `weight_kg`.", call. = FALSE)
  }
  if (have_hw) {
    if (is.null(height_cm) || is.null(weight_kg)) {
      stop("phn_zscore(): `height_cm` and `weight_kg` must both be given.", call. = FALSE)
    }
    bsa <- bsa_haycock(recycle(height_cm, "height_cm"), recycle(weight_kg, "weight_kg"))
  } else {
    if (!is.numeric(bsa)) stop("phn_zscore(): `bsa` must be numeric.", call. = FALSE)
    if (any(!is.na(bsa) & (!is.finite(bsa) | bsa <= 0))) {
      stop("phn_zscore(): `bsa` must be positive and finite (or `NA`).", call. = FALSE)
    }
    bsa <- recycle(bsa, "bsa")
  }

  row <- match(structure, .PHN_TABLE2$structure)
  if (anyNA(row)) {
    bad <- unique(structure[is.na(row)])
    stop("phn_zscore(): unknown `structure` ", paste0("\"", bad, "\"", collapse = ", "),
         ". See phn_zscore_table() for the Table 2 abbreviations.", call. = FALSE)
  }
  coef <- .PHN_TABLE2[row, ]

  to_table <- vapply(seq_len(n), function(i) {
    allowed <- .PHN_UNIT_FACTORS[[coef$unit[i]]]
    if (!units[i] %in% names(allowed)) {
      stop("phn_zscore(): `units` \"", units[i], "\" does not fit ", structure[i], ", which takes ",
           paste0("\"", names(allowed), "\"", collapse = " or "), ".", call. = FALSE)
    }
    allowed[[units[i]]]
  }, numeric(1))

  # A missing BSA gives NA for every structure, the ratios included, where
  # alpha = 0 and NA^0 would otherwise be 1.
  scale <- ifelse(is.na(bsa), NA_real_, bsa^coef$alpha)
  z <- (x * to_table / scale - coef$mean) / coef$sd
  predicted <- coef$mean * scale / to_table

  data.frame(
    structure = structure,
    x = x,
    units = units,
    bsa = bsa,
    predicted = predicted,
    z = z,
    stringsAsFactors = FALSE
  )
}
