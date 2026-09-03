# One-shot deprecation flags, keyed by name. An environment rather than a
# package variable so a warning fires once per session rather than once per
# call: a study reading forty datasets should be told once.
.hvti_deprecated <- new.env(parent = emptyenv())

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
#' @details
#' \strong{SAS format catalogs.} A \code{.sas7bdat} file stores a format's
#' \emph{name} -- \code{YESNOF.} -- and not its values. The code-to-text
#' mapping lives in a separate \code{.sas7bcat} catalog. Without one, reading
#' a SAS dataset yields numeric codes and no value labels, however the read is
#' written, and no amount of downstream work can recover text that never
#' arrived. Pass \code{catalog_file} to read the two together.
#'
#' A catalog on its own is only half the journey. With
#' \code{convert_types = TRUE}, \code{\link{r_data_types}} discards value
#' labels unless \code{use_value_labels = TRUE} is passed through \code{...},
#' so supplying a catalog without it warns.
#'
#' @param file Character. Path to the dataset file.
#' @param convert_types Logical. Apply \code{\link{r_data_types}} to the data
#'   after reading. Defaults to \code{FALSE}: the file is returned as read.
#'   \code{TRUE} converts any two-valued numeric column to logical, which is
#'   wrong for 0/1 event and censoring flags, so type conversion belongs to a
#'   declared variable-derivation step rather than to reading.
#' @param ... Additional arguments passed to \code{\link{r_data_types}}
#'   (e.g., \code{factor_size}, \code{skip_vars}, \code{binary_factor},
#'   \code{use_value_labels}). Ignored when \code{convert_types = FALSE}.
#' @param catalog_file Character. Path to a SAS format catalog
#'   (\code{.sas7bcat}), passed to \code{haven::read_sas()}. Defaults to
#'   \code{NULL}, which is what was read before this argument existed, so no
#'   existing call changes. Only valid for a \code{.sas7bdat} data file;
#'   supplying one with any other format is an error rather than a silent
#'   no-op. Must be named, because it follows \code{...}.
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
#' dta <- read_clinical_data(tmp, convert_types = FALSE)
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
#' dta <- read_clinical_data(tmp, convert_types = TRUE, factor_size = 5)
#' str(dta)
#' unlink(tmp)
read_clinical_data <- function(file, convert_types = FALSE, ...,
                               catalog_file = NULL) {
  if (missing(convert_types) && is.null(.hvti_deprecated$convert_types)) {
    .hvti_deprecated$convert_types <- TRUE
    warning(
      "read_clinical_data(): 'convert_types' now defaults to FALSE, so ",
      "columns are returned as read. It previously defaulted to TRUE, which ",
      "converted any two-valued numeric column to logical -- including 0/1 ",
      "event and censoring flags. Pass convert_types = TRUE to restore the ",
      "old behaviour, or FALSE to silence this warning.",
      call. = FALSE
    )
  }

  # Supplying a catalog states an intent -- the code-to-text mapping is
  # wanted -- and r_data_types() discards it unless use_value_labels is TRUE.
  # Reading a catalog and then throwing away what it decoded is the silent
  # loss this argument exists to end, so it is named rather than left to the
  # once-per-session warning in r_data_types(), which may already be spent.
  if (!is.null(catalog_file) && isTRUE(convert_types) &&
        !("use_value_labels" %in% ...names())) {
    warning(
      "read_clinical_data(): a 'catalog_file' was supplied, but ",
      "'use_value_labels' was not, so r_data_types() will convert the ",
      "value labels the catalog decoded back to their numeric codes and ",
      "discard the level text. Pass use_value_labels = TRUE to keep it.",
      call. = FALSE
    )
  }

  if (!is.character(file) || length(file) != 1L) {
    stop("'file' must be a single file path.", call. = FALSE)
  }
  if (!file.exists(file)) {
    stop("File not found: ", file, call. = FALSE)
  }

  ext <- tolower(tools::file_ext(file))

  if (!is.null(catalog_file)) {
    if (!is.character(catalog_file) || length(catalog_file) != 1L) {
      stop("'catalog_file' must be a single file path.", call. = FALSE)
    }
    if (ext != "sas7bdat") {
      stop("'catalog_file' only applies to .sas7bdat files; '", file,
           "' is .", ext, ". A format catalog is a SAS artefact and no ",
           "other reader can use one.", call. = FALSE)
    }
    if (!file.exists(catalog_file)) {
      # Named as the catalog rather than reusing "File not found": with two
      # path arguments, a caller cannot act on a message that does not say
      # which of them is missing.
      stop("Format catalog not found: ", catalog_file, call. = FALSE)
    }
  }

  if (!nzchar(ext))
    stop(
      "Cannot determine file type: '", file, "' has no extension. ",
      "Supported formats: .sas7bdat, .csv, .xlsx, .xls, .rds",
      call. = FALSE
    )

  data <- switch(
    ext,
    sas7bdat = haven::read_sas(file, catalog_file = catalog_file),
    csv      = utils::read.csv(file, stringsAsFactors = FALSE,
                              check.names = FALSE),
    xlsx     = ,
    xls      = readxl::read_excel(file),
    rds      = readRDS(file),
    stop(
      "Unsupported file type: '.", ext, "' in '", file, "'. ",
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
