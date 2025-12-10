# sample_data creates a generated data set to test the included methods.

The `data.frame` contains a collection of columns with sample data

## Usage

``` r
sample_data(n = 100)
```

## Arguments

- n:

  number of records to include

## Value

a data.frame containing a sample dataset

## Examples

``` r
# create the data set
dta <- sample_data(n =100)
udta <- r_data_types(dta)
lmap <- label_map(dta)
```
