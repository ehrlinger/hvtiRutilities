/*--------------------------------------------------------------------------
  One-off checks of PROC MEANS against what PROC UNIVARIATE did:
  1. weighted STDERR: std / sqrt(sum of weights) or std / sqrt(n)?
     (wt_frac fixture; writes out/means_wt_frac.csv)
  2. MODE with a single observation: the value, or missing?
     (n1 fixture; writes out/means_n1.csv)
--------------------------------------------------------------------------*/

%let root = /studies/general/proc_univariate-oracle;

options nodate nonumber missing=' ' nosyntaxcheck;

data work.fx;
  infile "&root/fixtures/wt_frac.csv" dsd firstobs=2 truncover;
  input id g :$8. x w;
run;

proc means data=work.fx noprint vardef=df;
  var x;
  weight w;
  output out=work.m n=n sumwgt=sumwgt mean=mean std=std stderr=stderr
         t=t probt=probt;
run;

data _null_;
  set work.m;
  file "&root/out/means_wt_frac.csv" dsd lrecl=32767;
  format _numeric_ best32.;
  if _n_ = 1 then put "n,sumwgt,mean,std,stderr,t,probt";
  put n sumwgt mean std stderr t probt;
run;

data work.n1;
  infile "&root/fixtures/n1.csv" dsd firstobs=2 truncover;
  input id g :$8. x w;
run;

proc means data=work.n1 noprint;
  var x;
  output out=work.m1 n=n mode=mode;
run;

data _null_;
  set work.m1;
  file "&root/out/means_n1.csv" dsd lrecl=32767;
  format _numeric_ best32.;
  if _n_ = 1 then put "n,mode";
  put n mode;
run;
