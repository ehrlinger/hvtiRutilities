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

make_release_aware_study <- function(dir, pinned_sequence = 1L,
                                     named = FALSE) {
  root <- file.path(dir, "study")
  study_setup(root, "Release-aware fixture", 42L)
  fx <- write_release_fixture(root)
  releases <- fx$catalog$datasets$surgery_cohort$releases
  hit <- vapply(releases, function(x) {
    identical(x$sequence, as.integer(pinned_sequence))
  }, logical(1))
  if (sum(hit) != 1L) stop("fixture has no requested pinned sequence")
  release <- releases[[which(hit)]]

  if (named) {
    default <- data.frame(dead = c(1L, 0L), iv_dead = 1:2)
    write.csv(default, file.path(fx$data_dir, "default.csv"), row.names = FALSE)
    register_data(root, "default.csv", "dead", "iv_dead")
    register_data(
      root,
      release$file,
      "dead",
      "iv_dead",
      dataset = "named_data",
      role = "named",
      catalog_dataset = "surgery_cohort",
      release_id = release$release_id
    )
    fx$study_dataset <- "named_data"
  } else {
    register_data(
      root,
      release$file,
      "dead",
      "iv_dead",
      catalog_dataset = "surgery_cohort",
      release_id = release$release_id
    )
    fx$study_dataset <- "study"
  }
  fx
}
