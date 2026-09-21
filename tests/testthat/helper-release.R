write_release_fixture <- function(root, releases = NULL,
                                  dataset_id = "surgery_cohort") {
  data_dir <- study_dir("datasets", root)
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  source <- testthat::test_path("fixtures", "dataset-catalog-v1.yml")
  catalog_path <- file.path(data_dir, "dataset-catalog.yml")
  file.copy(source, catalog_path, overwrite = TRUE)
  catalog <- yaml::read_yaml(catalog_path)

  if (!is.null(releases)) {
    catalog$datasets <- setNames(
      list(list(releases = releases)),
      dataset_id
    )
  } else if (!identical(dataset_id, "surgery_cohort")) {
    names(catalog$datasets) <- dataset_id
  }

  records <- catalog$datasets[[dataset_id]]$releases
  for (i in seq_along(records)) {
    release <- records[[i]]
    n <- as.integer(release$n_rows)
    data <- data.frame(
      id = seq_len(n),
      dead = as.integer(seq_len(n) <= floor(n / 2)),
      iv_dead = seq_len(n)
    )
    path <- file.path(data_dir, release$file)
    write.csv(data, path, row.names = FALSE)
    records[[i]]$sha256 <- digest::digest(
      path,
      algo = "sha256",
      file = TRUE
    )
  }
  catalog$datasets[[dataset_id]]$releases <- records
  yaml::write_yaml(catalog, catalog_path)

  list(
    root = root,
    catalog_path = catalog_path,
    catalog = catalog,
    data_dir = data_dir
  )
}
