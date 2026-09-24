# Which study files a checkpoint may commit. A hard deny that no configuration
# can override, then the allow-list, then a size cap. Denied files are counted
# per rule but never named, because dataset filenames can carry
# cohort-identifying fragments. Files in 50_documents/ other than .qmd and
# .bib sources are neither committed nor denied: they are listed so that
# CHECKPOINT.yml can record their checksums (spec D9).

.cp_code_ext <- function() c("r", "rmd", "qmd", "sas", "sh", "py", "sql", "rproj")
.cp_doc_ext  <- function() c("qmd", "bib")
.cp_data_ext <- function() {
  c("sas7bdat", "xpt", "parquet", "rds", "rdata", "csv", "xlsx", "xls",
    "lst", "log")
}
.cp_output_ext <- function() c("html", "pdf", "docx", "pptx", "png", "tiff")
.cp_always <- function() {
  c("_study.yml", "renv.lock", "renv/activate.R", ".Rprofile",
    "manifest.yaml", "_quarto.yml", ".renvignore", "README.md")
}
.cp_data_dirs <- function() c("00_datasets", "datasets", "90_estimates", "estimates")
.cp_doc_dirs  <- function() c("50_documents", "documents")
.cp_denied_levels <- function() {
  c("data_folder", "data_extension", "output_extension", "credential", "symlink")
}

# Credentials are matched by file name wherever they sit.
.cp_credential <- function(name) {
  name_lower <- tolower(name)
  name_lower %in% c(".env", ".renviron", ".netrc", ".git-credentials", "tracker.env") ||
    startsWith(name_lower, "id_rsa") || startsWith(name_lower, "id_ed25519") ||
    tolower(tools::file_ext(name)) %in% c("pem", "key", "p12", "pfx")
}

# TRUE for each path whose file, or any parent directory below root, is a
# symbolic link. list.files() follows linked directories, so every prefix is
# checked, not just the file. On Windows Sys.readlink() returns "" and no
# link is detected.
.cp_symlinked <- function(root, rel) {
  prefixes <- lapply(strsplit(rel, "/", fixed = TRUE), function(p) {
    vapply(seq_along(p), function(i) paste(p[seq_len(i)], collapse = "/"),
           character(1))
  })
  uniq <- unique(unlist(prefixes))
  target <- Sys.readlink(file.path(root, uniq))
  linked <- uniq[!is.na(target) & nzchar(target)]
  vapply(prefixes, function(p) any(p %in% linked), logical(1))
}

# The rule a relative path hits, or NA. The order is the precedence: tooling,
# symlink, credential, data_folder, document, data_extension,
# output_extension. "tooling" and "document" are not counted as denied.
.cp_deny_rule <- function(rel, linked = FALSE) {
  parts <- strsplit(rel, "/", fixed = TRUE)[[1]]
  n <- length(parts)
  ext <- tolower(tools::file_ext(rel))
  in_renv_lib <- n >= 2L && any(parts[-n] == "renv" & parts[-1] == "library")
  if (parts[1] == ".checkpoint" || ".git" %in% parts || in_renv_lib) {
    return("tooling")
  }
  if (linked) return("symlink")
  if (.cp_credential(parts[n])) return("credential")
  if (tolower(parts[1]) %in% .cp_data_dirs()) return("data_folder")
  if (n >= 2L && tolower(parts[1]) %in% .cp_doc_dirs() && !ext %in% .cp_doc_ext()) {
    return("document")
  }
  if (ext %in% .cp_data_ext()) return("data_extension")
  if (ext %in% .cp_output_ext()) return("output_extension")
  NA_character_
}

# A pattern without "/" matches the file name; one with "/" matches the whole
# relative path, with "*" free to cross directories.
.cp_included <- function(rel, include) {
  for (p in include) {
    target <- if (grepl("/", p, fixed = TRUE)) rel else basename(rel)
    if (grepl(utils::glob2rx(p), target)) return(TRUE)
  }
  FALSE
}

.cp_allowed <- function(rel, include) {
  top <- strsplit(rel, "/", fixed = TRUE)[[1]][1]
  ext <- tolower(tools::file_ext(rel))
  rel %in% .cp_always() ||
    ext %in% .cp_code_ext() ||
    (tolower(top) %in% .cp_doc_dirs() && ext %in% .cp_doc_ext()) ||
    .cp_included(rel, include)
}

.cp_select <- function(root, include = character(0), max_bytes = 50 * 1024^2) {
  rel <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  linked <- .cp_symlinked(root, rel)
  rules <- vapply(seq_along(rel), function(i) .cp_deny_rule(rel[i], linked[i]),
                  character(1))
  ok <- vapply(rel, .cp_allowed, logical(1), include = include,
               USE.NAMES = FALSE)
  cand <- rel[is.na(rules) & ok]
  bytes <- file.size(file.path(root, cand))
  big <- !is.na(bytes) & bytes > max_bytes
  levels <- .cp_denied_levels()
  tab <- table(factor(rules[rules %in% levels], levels = levels))
  list(
    files = sort(cand[!big]),
    documents = sort(rel[rules %in% "document"]),
    skipped = data.frame(path = cand[big], bytes = bytes[big],
                         stringsAsFactors = FALSE),
    denied = structure(as.integer(tab), names = levels)
  )
}
