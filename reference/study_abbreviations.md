# The abbreviation list a study's labels use

Merges the three abbreviation lists a job's labels can draw on, and
checks the result, so that
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
shortens labels the same way in every job of a study:

1.  `extra`, the job's own entries;

2.  the study's `abbreviations:` mapping in `_study.yml`;

3.  the group default list shipped with this package.

A higher level replaces a lower level's entry for the same phrase,
compared ignoring case, and an entry of `null` (`NA` or `NULL` in
`extra`) removes it.

## Usage

``` r
study_abbreviations(cfg = study_config(), extra = NULL, defaults = TRUE)
```

## Arguments

- cfg:

  A study configuration, as returned by
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.md).

- extra:

  The job's own entries: a named character vector or list, phrase to
  abbreviation, with `NA` or `NULL` to remove a phrase a lower level
  supplies. `NULL` for none.

- defaults:

  `FALSE` leaves the group default list out.

## Value

A named character vector, one element per spelling, phrase to
abbreviation, ready for `label_map(abbreviations = )`. Removed phrases
do not appear. Two attributes of the same length:

- source:

  each entry's level: `"job"`, `"study"` or `"default"`;

- expansion:

  the term each abbreviation stands for, the first spelling of its
  entry, which
  [`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md)
  prints in its key.

## Details

Every list is checked before anything is merged, and every problem is
reported in one error: an abbreviation must be one non-empty string no
longer than its phrase, and a phrase may appear only once in a list.
After merging, two phrases may not share an abbreviation, because the
shortened label could then mean either; the error names both phrases and
the level each came from. Abbreviations are compared ignoring case, with
one exception for the house style: `R` for replacement and `r` for
repair (`AVR`, `AVr`) may differ only in that last letter's case.

One entry may list several spellings of a term, separated by `" | "`:
`"Red blood cell | Red blood cells" = "RBC"`. The spellings share the
entry's abbreviation, which is not a clash, and the first spelling is
the expansion a key prints.

The list is a display input. It is never written into the stored labels.

## See also

[`add_abbreviation`](https://ehrlinger.github.io/hvtiRutilities/reference/add_abbreviation.md)
to add to a study's list,
[`label_map`](https://ehrlinger.github.io/hvtiRutilities/reference/label_map.md),
which applies it.

## Examples

``` r
root <- file.path(tempdir(), "abbrev-example")
study_setup(root, "Abbreviation example", 1L)
#> Study: /tmp/RtmpkWCNGi/abbrev-example
#> 
#> [x] _study.yml — study: Abbreviation example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
add_abbreviation("Surgical procedure", "SP", start = root)
study_abbreviations(study_config(root, require_data = FALSE),
                    extra = c("Left ventricular outflow tract" = "LVOT"))
#>                               Left ventricular 
#>                                           "LV" 
#>                              Right ventricular 
#>                                           "RV" 
#>                                    Left atrial 
#>                                           "LA" 
#>                               Pulmonary artery 
#>                                           "PA" 
#>                          Right coronary artery 
#>                                          "RCA" 
#>                        Internal mammary artery 
#>                                          "IMA" 
#>                                   Aortic valve 
#>                                           "AV" 
#>                                   Mitral valve 
#>                                           "MV" 
#>                                Tricuspid valve 
#>                                           "TV" 
#>                                Pulmonary valve 
#>                                           "PV" 
#>                       Aortic valve replacement 
#>                                          "AVR" 
#>                            Aortic valve repair 
#>                                          "AVr" 
#>                       Mitral valve replacement 
#>                                          "MVR" 
#>                            Mitral valve repair 
#>                                          "MVr" 
#>                    Tricuspid valve replacement 
#>                                          "TVR" 
#>                         Tricuspid valve repair 
#>                                          "TVr" 
#>                         Pulmonary valve repair 
#>                                          "PVr" 
#>                   Coronary artery bypass graft 
#>                                         "CABG" 
#>                Coronary artery bypass grafting 
#>                                         "CABG" 
#>             Percutaneous coronary intervention 
#>                                          "PCI" 
#>                         Cardiopulmonary bypass 
#>                                          "CPB" 
#>                      Intra-aortic balloon pump 
#>                                         "IABP" 
#>                         Carotid endarterectomy 
#>                                          "CEA" 
#>                        Coronary artery disease 
#>                                          "CAD" 
#>                       Congenital heart disease 
#>                                          "CHD" 
#>        Hypertrophic obstructive cardiomyopathy 
#>                                         "HOCM" 
#>                            Atrial fibrillation 
#>                                           "AF" 
#>                     Cerebral vascular accident 
#>                                          "CVA" 
#>                       Cerebrovascular accident 
#>                                          "CVA" 
#>                      Transient ischemic attack 
#>                                          "TIA" 
#>          Chronic obstructive pulmonary disease 
#>                                         "COPD" 
#>                   Deep sternal wound infection 
#>                                         "DSWI" 
#>                     New York Heart Association 
#>                                         "NYHA" 
#>                              Ejection fraction 
#>                                           "EF" 
#>    Left ventricular inner diameter in diastole 
#>                                        "LVIDd" 
#> Left ventricular internal diameter in diastole 
#>                                        "LVIDd" 
#>     Left ventricular inner diameter in systole 
#>                                        "LVIDs" 
#>  Left ventricular internal diameter in systole 
#>                                        "LVIDs" 
#>                        Relative wall thickness 
#>                                          "RWT" 
#>                            Fresh frozen plasma 
#>                                          "FFP" 
#>                                 Red blood cell 
#>                                          "RBC" 
#>                                Red blood cells 
#>                                          "RBC" 
#>                                 Length of stay 
#>                                          "LOS" 
#>                                   Preoperative 
#>                                        "Preop" 
#>                             Surgical procedure 
#>                                           "SP" 
#>                 Left ventricular outflow tract 
#>                                         "LVOT" 
#> attr(,"source")
#>  [1] "default" "default" "default" "default" "default" "default" "default"
#>  [8] "default" "default" "default" "default" "default" "default" "default"
#> [15] "default" "default" "default" "default" "default" "default" "default"
#> [22] "default" "default" "default" "default" "default" "default" "default"
#> [29] "default" "default" "default" "default" "default" "default" "default"
#> [36] "default" "default" "default" "default" "default" "default" "default"
#> [43] "default" "default" "study"   "job"    
#> attr(,"expansion")
#>  [1] "Left ventricular"                           
#>  [2] "Right ventricular"                          
#>  [3] "Left atrial"                                
#>  [4] "Pulmonary artery"                           
#>  [5] "Right coronary artery"                      
#>  [6] "Internal mammary artery"                    
#>  [7] "Aortic valve"                               
#>  [8] "Mitral valve"                               
#>  [9] "Tricuspid valve"                            
#> [10] "Pulmonary valve"                            
#> [11] "Aortic valve replacement"                   
#> [12] "Aortic valve repair"                        
#> [13] "Mitral valve replacement"                   
#> [14] "Mitral valve repair"                        
#> [15] "Tricuspid valve replacement"                
#> [16] "Tricuspid valve repair"                     
#> [17] "Pulmonary valve repair"                     
#> [18] "Coronary artery bypass graft"               
#> [19] "Coronary artery bypass graft"               
#> [20] "Percutaneous coronary intervention"         
#> [21] "Cardiopulmonary bypass"                     
#> [22] "Intra-aortic balloon pump"                  
#> [23] "Carotid endarterectomy"                     
#> [24] "Coronary artery disease"                    
#> [25] "Congenital heart disease"                   
#> [26] "Hypertrophic obstructive cardiomyopathy"    
#> [27] "Atrial fibrillation"                        
#> [28] "Cerebral vascular accident"                 
#> [29] "Cerebral vascular accident"                 
#> [30] "Transient ischemic attack"                  
#> [31] "Chronic obstructive pulmonary disease"      
#> [32] "Deep sternal wound infection"               
#> [33] "New York Heart Association"                 
#> [34] "Ejection fraction"                          
#> [35] "Left ventricular inner diameter in diastole"
#> [36] "Left ventricular inner diameter in diastole"
#> [37] "Left ventricular inner diameter in systole" 
#> [38] "Left ventricular inner diameter in systole" 
#> [39] "Relative wall thickness"                    
#> [40] "Fresh frozen plasma"                        
#> [41] "Red blood cell"                             
#> [42] "Red blood cell"                             
#> [43] "Length of stay"                             
#> [44] "Preoperative"                               
#> [45] "Surgical procedure"                         
#> [46] "Left ventricular outflow tract"             
unlink(root, recursive = TRUE)
```
