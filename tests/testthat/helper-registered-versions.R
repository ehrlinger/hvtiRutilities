# Write a small CSV source for the registered-version tests and return its path.
write_source_csv <- function(dir, data = data.frame(id = 1:3, x = c(1.5, 2.5, 3.5)), file = "built.csv") {
  path <- file.path(dir, file)
  utils::write.csv(data, path, row.names = FALSE)
  path
}
