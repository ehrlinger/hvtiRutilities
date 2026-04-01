#' Read and prepare a clinical dataset in one step
#'
#' @description
#' A convenience wrapper that detects the file type, reads the data with the
#' appropriate reader, and optionally runs \code{\link{r_data_types}} to
#' convert column types. This saves novice users from having to remember
#' which package reads which format and ensures labels are preserved.
#'
#' Supported formats:
#' \describe{
#'   \item{\code{.sas7bdat}}{SAS datasets via \code{haven::read_sas()}}
#'   \item{\code{.csv}}{Comma-separated files via \code{utils::read.csv()} with
#'     \code{check.names = FALSE}, so column names are preserved exactly as
#'     written in the file (spaces, hyphens, and special characters are not
#'     silently converted to \code{.}).}
#'   \item{\code{.xlsx}, \code{.xls}}{Excel workbooks via
#'     \code{readxl::read_excel()}}
#'   \item{\code{.rds}}{R serialized objects via \code{readRDS()}}
#' }
#'
#' @param file Character. Path to the dataset file.
#' @param convert_types Logical. If \code{TRUE} (default), runs
#'   \code{\link{r_data_types}} on the result.
#' @param ... Additional arguments passed to \code{\link{r_data_types}}
#'   (e.g., \code{factor_size}, \code{skip_vars}, \code{binary_factor}).
#'   Ignored when \code{convert_types = FALSE}.
#'
#' @return A data frame with labels preserved and (optionally) types
#'   converted.
#'
#' @seealso \code{\link{r_data_types}} for details on type conversion,
#'   \code{\link{label_map}} to extract labels after reading.
#'
#' @export
#'
#' @examples
#' # Read a CSV
#' tmp <- tempfile(fileext = ".csv")
#' write.csv(mtcars, tmp, row.names = FALSE)
#' dta <- read_clinical_data(tmp)
#' str(dta[, 1:5])
#' unlink(tmp)
#'
#' # Read without type conversion
#' tmp <- tempfile(fileext = ".csv")
#' write.csv(mtcars, tmp, row.names = FALSE)
#' dta_raw <- read_clinical_data(tmp, convert_types = FALSE)
#' str(dta_raw[, 1:5])
#' unlink(tmp)
#'
#' # Read an RDS file
#' tmp <- tempfile(fileext = ".rds")
#' saveRDS(iris, tmp)
#' dta <- read_clinical_data(tmp, factor_size = 5)
#' str(dta)
#' unlink(tmp)
read_clinical_data <- function(file, convert_types = TRUE, ...) {
  if (!is.character(file) || length(file) != 1L) {
    stop("'file' must be a single file path.", call. = FALSE)
  }
  if (!file.exists(file)) {
    stop("File not found: ", file, call. = FALSE)
  }

  ext <- tolower(tools::file_ext(file))

  data <- switch(
    ext,
    sas7bdat = haven::read_sas(file),
    csv      = utils::read.csv(file, stringsAsFactors = FALSE,
                              check.names = FALSE),
    xlsx     = ,
    xls      = readxl::read_excel(file),
    rds      = readRDS(file),
    stop(
      "Unsupported file type: '.", ext, "'. ",
      "Supported formats: .sas7bdat, .csv, .xlsx, .xls, .rds",
      call. = FALSE
    )
  )

  # Ensure we always return a plain data.frame
  data <- as.data.frame(data)

  if (convert_types) {
    data <- r_data_types(data, ...)
  }

  data
}
