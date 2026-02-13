#' Display the NEWS file
#'
#' @description
#' Display the NEWS.md file for the hvtiRutilities package showing
#' release notes and change history.
#'
#' @return Invisibly returns NULL. Called for side effect of displaying NEWS.
#' @export
#'
#' @examples
#' \dontrun{
#' hvtiRutilities.news()
#' }
hvtiRutilities.news <- function() {
  news_file <- system.file("NEWS.md", package = "hvtiRutilities")

  if (news_file == "") {
    message("NEWS.md file not found in installed package.")
    return(invisible(NULL))
  }

  file.show(news_file, title = "hvtiRutilities News")
  invisible(NULL)
}
