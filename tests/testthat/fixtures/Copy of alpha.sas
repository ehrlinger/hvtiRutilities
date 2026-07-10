%macro alpha(dsn);
  data &dsn._out; set &dsn.; run;
%mend alpha;
