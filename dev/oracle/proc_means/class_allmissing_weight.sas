/*--------------------------------------------------------------------------
  One-off check: a CLASS level whose every observation has a missing
  WEIGHT. Does SAS output a row for that level (N = 0, NOBS = k), or omit
  the level? Checked for PROC MEANS and PROC UNIVARIATE.
  Inline synthetic data; writes out/class_allmiss_means.csv and
  out/class_allmiss_univ.csv.
--------------------------------------------------------------------------*/

%let root = /studies/general/proc_univariate-oracle;

options nodate nonumber missing=' ' nosyntaxcheck;

/* level x: weights present; level y: every weight missing. */
data work.cw;
  input g $ a w;
  datalines;
x 1 1
x 2 2
y 3 .
y 4 .
;
run;

proc means data=work.cw noprint;
  class g;
  var a;
  weight w;
  output out=work.m(where=(_type_ = 1)) n=n nmiss=nmiss nobs=nobs;
run;

proc univariate data=work.cw noprint;
  class g;
  var a;
  weight w;
  output out=work.u n=n nmiss=nmiss nobs=nobs;
run;

%macro dump(ds, file);
  data _null_;
    set &ds;
    file "&root/out/&file" dsd lrecl=32767;
    if _n_ = 1 then put "g,n,nmiss,nobs";
    put g n nmiss nobs;
  run;
%mend dump;

%dump(work.m, class_allmiss_means.csv)
%dump(work.u, class_allmiss_univ.csv)
