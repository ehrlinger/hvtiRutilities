%macro delta(n);
  %let half = %sysevalf(&n. / 2);
%mend delta;
