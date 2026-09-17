/*--------------------------------------------------------------------------
  One-off check, PROC MEANS only (PROC MEANS has no NOBS keyword on the
  OUTPUT statement, so the printed table is captured with ODS OUTPUT).
  A CLASS level whose every observation has a missing WEIGHT: does the
  printed table include that level, and what is its N Obs?
  Also records _FREQ_ from OUTPUT OUT=. Writes
  out/class_allmiss_means_printed.csv and out/class_allmiss_means_out.csv.
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

ods output summary=work.printed;
proc means data=work.cw n nmiss nobs;
  class g;
  var a;
  weight w;
  output out=work.o(where=(_type_ = 1)) n=n nmiss=nmiss;
run;

proc contents data=work.printed noprint out=work.pc(keep=name varnum);
run;

proc sql noprint;
  select name into :pv separated by ' ' from work.pc order by varnum;
  select name into :ph separated by ',' from work.pc order by varnum;
quit;

data _null_;
  set work.printed;
  file "&root/out/class_allmiss_means_printed.csv" dsd lrecl=32767;
  if _n_ = 1 then put "&ph";
  put &pv;
run;

data _null_;
  set work.o;
  file "&root/out/class_allmiss_means_out.csv" dsd lrecl=32767;
  if _n_ = 1 then put "g,_freq_,n,nmiss";
  put g _freq_ n nmiss;
run;
