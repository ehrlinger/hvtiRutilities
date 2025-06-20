.onAttach <- function(libname, pkgname) {
  hvtiRutilities.version <- read.dcf(file=system.file("DESCRIPTION", package=pkgname),
                            fields="Version")
  packageStartupMessage(paste("\n",
                              pkgname,
                              hvtiRutilities.version,
                              "\n",
                              "\n",
                              "Type hvtiRutilities.news() to see new features, changes, and bug fixes.",
                              "\n",
                              "\n"))
}
