pkgname <- "hvtiRutilities"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
base::assign(".ExTimings", "hvtiRutilities-Ex.timings", pos = 'CheckExEnv')
base::cat("name\tuser\tsystem\telapsed\n", file=base::get(".ExTimings", pos = 'CheckExEnv'))
base::assign(".format_ptime",
function(x) {
  if(!is.na(x[4L])) x[1L] <- x[1L] + x[4L]
  if(!is.na(x[5L])) x[2L] <- x[2L] + x[5L]
  options(OutDec = '.')
  format(x[1L:3L], digits = 7L)
},
pos = 'CheckExEnv')

### * </HEADER>
library('hvtiRutilities')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("hvtiRutilities.news")
### * hvtiRutilities.news

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: hvtiRutilities.news
### Title: Display the NEWS file
### Aliases: hvtiRutilities.news

### ** Examples

## Not run: 
##D hvtiRutilities.news()
## End(Not run)



base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("hvtiRutilities.news", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
cleanEx()
nameEx("label_map")
### * label_map

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: label_map
### Title: Build a lookup map of data labels
### Aliases: label_map

### ** Examples

# Create a dataset with labels
library(labelled)
dta <- data.frame(
  age = c(25, 30, 35),
  sex = c("M", "F", "M")
)
var_label(dta$age) <- "Patient Age"
var_label(dta$sex) <- "Patient Sex"

# Build the label map
label_lookup <- label_map(dta)
print(label_lookup)

# Use for matching in summary tables
summary <- data.frame(variable = c("age", "sex"))
summary$description <- label_lookup$label[match(summary$variable, label_lookup$key)]



base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("label_map", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
cleanEx()
nameEx("r_data_types")
### * r_data_types

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: r_data_types
### Title: Automatically infer and convert data types
### Aliases: r_data_types

### ** Examples

# Basic usage with sample data
dta <- sample_data(n = 100)
str(dta)  # Original types
dta_converted <- r_data_types(dta)
str(dta_converted)  # Converted types

# Real data example with mtcars
str(datasets::mtcars$vs)  # numeric (0/1)
mtcars_converted <- r_data_types(datasets::mtcars)
str(mtcars_converted$vs)  # logical (FALSE/TRUE)

# Skip specific columns
mtcars_partial <- r_data_types(datasets::mtcars, skip_vars = c("vs", "am"))
str(mtcars_partial$vs)  # Still numeric (unchanged)

# Control factor creation threshold
mtcars_strict <- r_data_types(datasets::mtcars, factor_size = 5)

# Keep binary variables as factors
mtcars_factors <- r_data_types(datasets::mtcars, binary_factor = TRUE)
str(mtcars_factors$vs)  # Factor instead of logical



base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("r_data_types", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
cleanEx()
nameEx("sample_data")
### * sample_data

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: sample_data
### Title: sample_data creates a generated data set to test the included
###   methods.
### Aliases: sample_data

### ** Examples

# create the data set
dta <- sample_data(n = 100)
udta <- r_data_types(dta)
lmap <- label_map(dta)




base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("sample_data", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
