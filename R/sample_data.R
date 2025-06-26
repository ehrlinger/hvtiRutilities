#' sample_data creates a generated data set to test the included methods.
#'
#' The \code{data.frame} contains a collection of columns with sample data
#'
#' @param n number of records to include
#'
#' @return a data.frame containing a sample dataset
#'
#' @examples
#' # create the data set
#' dta <- sample_data(n =100)
#' udta <- r_data_types(dta)
#' lmap <- label_map(dta)
#'
#' @export sample_data
sample_data <- function(n = 100) {
  dta <- data.frame(id = seq(1, n))
  dta$boolean <- sample.int(size=2, n = n, replace = TRUE)
  dta <- dta |>
    dplyr::mutate(logical = as.character(factor(
      dta$boolean, labels = c("F", "T")
    )))
  dta$f_real <- sample(stats::runif(n=9), size=n, replace = TRUE)
  dta$float <- stats::rnorm(n = n)
  dta$char <- sample.int(size=2, n = n, replace = TRUE)
  dta <- dta |>
    dplyr::mutate(char = as.character(factor(
      dta$char,
      labels = c("male", "female")
    )))
  dta$factor <- factor(sample(c("C1", "C2", "C3", "C4", "C5"),
                              size=n, replace = TRUE))
  return(dta)
}
