* `rmarkdown` is no longer in `Suggests`. Nothing in the package, its tests or
  its vignettes called it. The Quarto vignette engine still reaches
  `rmarkdown` through the `quarto` package, which imports it.
