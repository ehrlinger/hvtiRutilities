# Build a lookup map of data labels

builds a

## Usage

``` r
label_map(built)
```

## Arguments

- built:

  a dataset with sas labels

## Value

a hash function with label:key pairs

\# Build the map. avsd_label_map \<- label_map(avsd_raw) dta\$label \<-
avsd_label_map\$label\[match(dta\$name, avsd_label_map\$key)\]
