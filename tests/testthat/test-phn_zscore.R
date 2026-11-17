# Tests for phn_zscore(), phn_zscore_table() and bsa_haycock().
#
# Two independent oracles:
#
# 1. The paper's own worked example (Lopez et al. 2017, Results, after
#    Table 2): a mitral diameter of 11 mm at BSA 0.3 m^2 has Z = -1.0, from
#    alpha 0.50, mean 2.23, SD 0.22.
#
# 2. The ParameterZ PHN calculator (parameterz.com, "Lopez et al., Circ
#    Cardiovasc Imaging 2017"), which computes BSA by Haycock and implements
#    the same Table 2. Its JSON endpoint was queried on 2026-11-17 with the
#    synthetic inputs below (no patient data):
#      /calc/echo/lopez-circimaging-2017/?ht=60&wt=5.5&aov=8&sov=11&stj=9&aao=10
#        &pv=9&pv_plax=9&mpa=9&rpa=5&lpa=5&mvd_l=13&mvd_ap=13&tvd_l=14&tvd_ap=14
#        &lvedd_psax=25&lvpwd_psax=3.5&ivsd_psax=3.5&lmca=2&lv_eda_psax=4.5
#        &lvedv=15&lvm_2d=14&lv_sphere_idx=1.6&lv_mass_vol_ratio=0.9
#        &lvpw_lvedd_ratio=0.15
#      /calc/echo/lopez-circimaging-2017/?ht=160&wt=50&prox_arch=18&dist_arch=16
#        &isthmus=15&lad=2.5&prox_rca=3&lmca=3.5&mv_area=6&tv_area=6.5
#        &lv_eda_epi_psax=27&lv_eda_psax=16&lv_maj_ed_a4c=75&lv_maj_epi_ed_a4c=82
#        &lvedv_epi=170&lvedv=95&lvm_2d=80&aov=19&sov=27
#    Its linear inputs are in mm, areas in cm^2. Together the two queries cover
#    all 34 Table 2 structures. Values are pasted at full precision.

test_that("the paper's worked example gives Z = -1.0", {
  r <- phn_zscore(11, "MVLAT", units = "mm", bsa = 0.3)
  expect_equal(round(r$z, 1), -1.0)
  # By hand: (1.1 / sqrt(0.3) - 2.23) / 0.22
  expect_equal(r$z, (1.1 / sqrt(0.3) - 2.23) / 0.22)
})

test_that("Haycock BSA matches the published formula and the PHN calculator", {
  # Haycock 1978 abstract: SA = weight^0.5378 x height^0.3964 x 0.024265
  expect_equal(bsa_haycock(170, 70), 0.024265 * 70^0.5378 * 170^0.3964)
  expect_equal(bsa_haycock(60, 5.5), 0.30761428948889635, tolerance = 1e-12)
  expect_equal(bsa_haycock(160, 50), 1.487303243710502, tolerance = 1e-12)
  expect_true(is.na(bsa_haycock(NA_real_, 5)))
})

test_that("infant: matches the ParameterZ PHN calculator for 23 structures", {
  m <- c(ANN = 8, ROOT = 11, STJ = 9, AAO = 10, PVSAX = 9, PVLAX = 9, MPA = 9, RPA = 5, LPA = 5,
         MVLAT = 13, MVAP = 13, TVLAT = 14, TVAP = 14, LVEDD = 25, LVPWT = 3.5, LVST = 3.5, LMCA = 2)
  pz <- c(-0.2685472208883805, -0.4260852223389628, -0.42060117056200025, 0.07224575746962818,
          -1.1970674470413334, -1.3832006688925709, -0.822067447041334, -0.9360993434874084,
          -1.1027660101540753, 0.5177523056722427, 0.14127294686622216, 0.5662273478701595,
          0.5864497531512366, 1.0893716277617536, -0.10139807944823387, -0.21250919055934508,
          0.7887615960159702)
  pz_mean <- c(8.208522033207187, 11.425375262437033, 9.373244754135234, 9.927874621243829,
               10.59343046177414, 11.148060328882734, 10.094263581376406, 5.934539578061954,
               6.100928538194532, 12.36824603652164, 12.811949930208515, 13.08926486376281,
               13.08926486376281, 22.885084950979486, 3.556947523299054, 3.6193501114271074,
               1.7355013009097555)
  r <- phn_zscore(unname(m), names(m), "mm", height_cm = 60, weight_kg = 5.5)
  expect_equal(r$z, pz, tolerance = 1e-10)
  expect_equal(r$predicted, pz_mean, tolerance = 1e-10)

  o <- phn_zscore(c(4.5, 15, 14, 1.6, 0.9, 0.15),
                  c("LVEDA", "LVEDV", "LVM", "LVSI", "LVMTV", "LVTTD"),
                  c("cm2", "ml", "g", "none", "g/ml", "none"),
                  height_cm = 60, weight_kg = 5.5)
  expect_equal(o$z, c(0.5777222882369908, 0.6224193775083481, 0.8930543268477553,
                      -0.17647058823529296, 0.1250000000000001, 0.0), tolerance = 1e-10)
})

test_that("adolescent: matches the ParameterZ PHN calculator for the remaining structures", {
  s <- c("ARCHPROX", "ARCHDIST", "ISTH", "LAD", "RCA", "LMCA", "MVA", "TVA", "LVEDAEPI", "LVEDA",
         "LVEDL", "LVEDLEPI", "LVEDVEPI", "LVEDV", "LVM", "ANN", "ROOT")
  x <- c(18, 16, 15, 2.5, 3, 3.5, 6, 6.5, 27, 16, 75, 82, 170, 95, 80, 19, 27)
  u <- c("mm", "mm", "mm", "mm", "mm", "mm", "cm2", "cm2", "cm2", "cm2", "mm", "mm", "ml", "ml", "g", "mm", "mm")
  pz <- c(-0.2349837878888051, -0.2528480524651477, -0.11132532969641254, 0.5618523561766521,
          0.34406502058195293, -0.03957592712265514, -0.03801903726567968, -0.023703643516928854,
          -0.4290377151881871, -0.3791754441975008, -0.08024042760829082, -0.02538278309288384,
          -0.653887817833906, -0.4453297207073829, -0.47605847286349096, 0.5567939868753654,
          0.855169962102013)
  r <- phn_zscore(x, s, u, height_cm = 160, weight_kg = 50)
  expect_equal(r$z, pz, tolerance = 1e-10)
})

test_that("the coefficient table is Table 2 of Lopez et al. 2017", {
  tb <- phn_zscore_table()
  expect_s3_class(tb, "data.frame")
  expect_equal(nrow(tb), 34L)
  expect_false(anyDuplicated(tb$structure) > 0)
  # Spot checks transcribed from Table 2 (unit, alpha, mean, SD).
  row <- function(s) unname(unlist(tb[tb$structure == s, c("unit", "alpha", "mean", "sd")]))
  expect_equal(row("ANN"), c("cm", "0.5", "1.48", "0.14"))
  expect_equal(row("ROOT"), c("cm", "0.5", "2.06", "0.18"))
  expect_equal(row("STJ"), c("cm", "0.5", "1.69", "0.16"))
  expect_equal(row("AAO"), c("cm", "0.5", "1.79", "0.18"))
  expect_equal(row("PVSAX"), c("cm", "0.5", "1.91", "0.24"))
  expect_equal(row("LMCA"), c("mm", "0.45", "2.95", "0.57"))
  expect_equal(row("LVEDD"), c("cm", "0.45", "3.89", "0.33"))
  expect_equal(row("LVEDA"), c("cm2", "0.9", "11.91", "1.89"))
  expect_equal(row("LVEDV"), c("ml", "1.3", "62.02", "11.94"))
  expect_equal(row("LVM"), c("g", "1.25", "53.02", "9.06"))
})

test_that("z is 0 at the predicted value, and units only rescale", {
  r <- phn_zscore(10, "ANN", "mm", bsa = 0.4)
  expect_equal(phn_zscore(r$predicted, "ANN", "mm", bsa = 0.4)$z, 0)
  expect_equal(phn_zscore(1, "ANN", "cm", bsa = 0.4)$z, r$z)
  expect_equal(phn_zscore(1, "ANN", "cm", bsa = 0.4)$predicted, r$predicted / 10)
  # Coronaries are tabulated in mm; cm input is converted.
  expect_equal(phn_zscore(0.2, "LMCA", "cm", bsa = 0.4)$z, phn_zscore(2, "LMCA", "mm", bsa = 0.4)$z)
  # Areas: mm2 to cm2.
  expect_equal(phn_zscore(450, "LVEDA", "mm2", bsa = 0.4)$z, phn_zscore(4.5, "LVEDA", "cm2", bsa = 0.4)$z)
  # Case-insensitive structure and units.
  expect_equal(phn_zscore(10, "ann", "MM", bsa = 0.4)$z, r$z)
})

test_that("ratios do not depend on BSA", {
  expect_equal(phn_zscore(1.8, "LVSI", "none", bsa = 0.2)$z, phn_zscore(1.8, "LVSI", "none", bsa = 1.9)$z)
})

test_that("missing values propagate as NA", {
  r <- phn_zscore(c(10, NA, 12), "ANN", "mm", bsa = c(0.4, 0.5, NA))
  expect_equal(is.na(r$z), c(FALSE, TRUE, TRUE))
  expect_equal(is.na(r$predicted), c(FALSE, FALSE, TRUE))
})

test_that("a missing BSA gives NA for the ratios too", {
  r <- phn_zscore(c(1.6, 1.6), "LVSI", "none", bsa = c(NA_real_, 0.5))
  expect_equal(is.na(r$z), c(TRUE, FALSE))
  expect_equal(is.na(r$predicted), c(TRUE, FALSE))
  h <- phn_zscore(1.6, "LVSI", "none", height_cm = NA_real_, weight_kg = 5)
  expect_true(is.na(h$z))
})

test_that("non-finite BSA, height and weight are refused", {
  expect_error(phn_zscore(10, "ANN", "mm", bsa = Inf), "positive and finite")
  # NaN is missing in R (is.na(NaN) is TRUE), so it propagates like NA.
  expect_true(is.na(phn_zscore(10, "ANN", "mm", bsa = NaN)$z))
  expect_error(phn_zscore(10, "ANN", "mm", height_cm = Inf, weight_kg = 5), "positive and finite")
  expect_error(bsa_haycock(Inf, 5), "positive and finite")
  expect_error(bsa_haycock(60, -Inf), "positive and finite")
  expect_true(is.na(bsa_haycock(NA_real_, 5)))
})

test_that("bsa and height/weight give the same answer", {
  b <- bsa_haycock(75, 9.4)
  expect_equal(phn_zscore(12, "ANN", "mm", height_cm = 75, weight_kg = 9.4)$z,
               phn_zscore(12, "ANN", "mm", bsa = b)$z)
})

test_that("bad input fails loudly", {
  expect_error(phn_zscore(10, "ANN", bsa = 0.4), "`units` is required")
  expect_error(phn_zscore(10, "ANN", "mm"), "give `bsa`")
  expect_error(phn_zscore(10, "ANN", "mm", bsa = 0.4, height_cm = 60, weight_kg = 5), "not both")
  expect_error(phn_zscore(10, "ANN", "mm", height_cm = 60), "must both be given")
  expect_error(phn_zscore(10, "MV", "mm", bsa = 0.4), "unknown `structure` \"MV\"")
  expect_error(phn_zscore(10, "ANN", "cm2", bsa = 0.4), "does not fit ANN")
  expect_error(phn_zscore(10, "LVEDV", "mm", bsa = 0.4), "does not fit LVEDV")
  expect_error(phn_zscore(1:3, c("ANN", "STJ"), "mm", bsa = 0.4), "length 1 or the length of `x`")
  expect_error(phn_zscore(10, "ANN", "mm", bsa = -1), "positive")
  expect_error(bsa_haycock(0, 5), "positive")
})
