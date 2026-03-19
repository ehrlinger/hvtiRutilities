#' Generate a sample dataset for testing
#'
#' Creates a data frame with labeled columns of various types, suitable for
#' demonstrating \code{\link{r_data_types}} and \code{\link{label_map}}.
#'
#' @param n Number of records to generate. Default \code{100}.
#'
#' @return A data frame with \code{n} rows and 7 labeled columns:
#' \describe{
#'   \item{id}{Integer sequence (Patient Identifier)}
#'   \item{boolean}{Integer 1/2 (Binary Indicator)}
#'   \item{logical}{Character "F"/"T" (Logical Status)}
#'   \item{f_real}{Uniform random values (Random Uniform Value)}
#'   \item{float}{Normal random values (Random Normal Value)}
#'   \item{char}{Character "male"/"female" (Gender)}
#'   \item{factor}{Factor C1-C5 (Category Group)}
#' }
#'
#' @examples
#' # Create and inspect labeled data
#' dta <- sample_data(n = 20)
#' str(dta)
#' label_map(dta)
#'
#' # Full workflow: generate, convert types, extract labels
#' dta <- sample_data(n = 100)
#' dta_clean <- r_data_types(dta, skip_vars = "id")
#' lmap <- label_map(dta_clean)
#' print(lmap)
#'
#' @export sample_data
sample_data <- function(n = 100) {
  dta <- data.frame(id = seq(1, n))
  dta$boolean <- sample.int(n = 2, size = n, replace = TRUE)
  dta$logical <- c("F", "T")[dta$boolean]
  dta$f_real <- sample(stats::runif(n = 9), size = n, replace = TRUE)
  dta$float <- stats::rnorm(n = n)
  dta$char <- c("male", "female")[sample.int(n = 2, size = n, replace = TRUE)]
  dta$factor <- factor(sample(c("C1", "C2", "C3", "C4", "C5"),
    size = n, replace = TRUE
  ))

  labelled::var_label(dta) <- list(
    id      = "Patient Identifier",
    boolean = "Binary Indicator",
    logical = "Logical Status",
    f_real  = "Random Uniform Value",
    float   = "Random Normal Value",
    char    = "Gender",
    factor  = "Category Group"
  )

  dta
}
