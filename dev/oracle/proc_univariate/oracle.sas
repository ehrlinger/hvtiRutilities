/*--------------------------------------------------------------------------
  SAS oracle for hvtiRutilities::proc_univariate()

  Runs PROC UNIVARIATE with OUTPUT OUT= on every scenario in scenarios.csv
  and writes one CSV per scenario to out/, plus sas_version.txt and
  oracle.log. The fixtures are synthetic; nothing here reads study data.

  Design: dev/specs/2026-09-17-proc-univariate-design.md

  To run: set ROOT below to this kit's directory, then submit the whole file.
--------------------------------------------------------------------------*/

%let root = /path/to/hvtiRutilities/dev/oracle/proc_univariate;

options nodate nonumber missing=' ' dlcreatedir nosyntaxcheck;

/* Create out/ if it does not exist. */
libname _mkout "&root/out";
libname _mkout clear;

proc printto log="&root/out/oracle.log" new;
run;

data _null_;
  file "&root/out/sas_version.txt";
  put "&sysvlong";
  put "&sysscp &sysscpl";
run;

%macro uni(scenario=, fixture=, weight=0, vardef=DF, mu0=0, class=0,
           ttest=1, ranktests=1);
  %local _rc vars hdr;

  proc datasets lib=work nolist nowarn;
    delete fx o cols;
  quit;

  filename _old "&root/out/&scenario..csv";
  %if %sysfunc(fexist(_old)) %then %do;
    %let _rc = %sysfunc(fdelete(_old));
    %if &_rc ne 0 %then %put ERROR: could not delete stale &scenario..csv.;
  %end;
  filename _old clear;

  data work.fx;
    infile "&root/fixtures/&fixture..csv" dsd firstobs=2 truncover;
    input id g :$8. x w;
  run;

  proc univariate data=work.fx noprint mu0=&mu0 vardef=&vardef
    %if &ranktests = 1 %then normal;
    ;
    %if &class = 1 %then %do;
      class g;
    %end;
    var x;
    %if &weight = 1 %then %do;
      weight w;
    %end;
    output out=work.o
      n=n nobs=nobs nmiss=nmiss sum=sum mean=mean std=std var=var cv=cv
      stdmean=stdmean uss=uss css=css skewness=skewness kurtosis=kurtosis
      sumwgt=sumwgt range=range qrange=qrange mode=mode min=min max=max
      median=median q1=q1 q3=q3 p1=p1 p5=p5 p10=p10 p90=p90 p95=p95 p99=p99
      %if &ttest = 1 %then %do;
        t=t probt=probt
      %end;
      %if &ranktests = 1 %then %do;
        msign=msign probm=probm signrank=signrank probs=probs
        normal=normal probn=probn
      %end;
      pctlpts=0 2.5 16 50 84 97.5 100 pctlpre=pp_;
  run;

  %if &syserr > 4 or not %sysfunc(exist(work.o)) %then %do;
    %put WARNING: scenario &scenario produced no output (syserr=&syserr).;
    %goto done;
  %end;

  proc contents data=work.o out=work.cols(keep=name varnum) noprint;
  run;

  proc sql noprint;
    select name into :vars separated by ' '
      from work.cols order by varnum;
    select lowcase(name) into :hdr separated by ','
      from work.cols order by varnum;
  quit;

  data _null_;
    set work.o;
    file "&root/out/&scenario..csv" dsd lrecl=32767;
    format _numeric_ best32.;
    if _n_ = 1 then put "&hdr";
    put (&vars) (:);
  run;

  %done:
%mend uni;

/* One %uni call per row of scenarios.csv, so the SAS runs cannot drift from
   the manifest that make_fixtures.R writes and check_oracle.R reads. */
data _null_;
  infile "&root/scenarios.csv" dsd firstobs=2 truncover;
  length scenario fixture vardef $32;
  input scenario $ fixture $ weight vardef $ mu0 class ttest ranktests
        optional;
  call execute(cats('%nrstr(%uni)(scenario=', scenario,
                    ', fixture=', fixture, ', weight=', weight,
                    ', vardef=', vardef, ', mu0=', mu0,
                    ', class=', class, ', ttest=', ttest,
                    ', ranktests=', ranktests, ')'));
run;

proc printto;
run;
