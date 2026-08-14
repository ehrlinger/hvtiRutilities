%macro helper_one;
  %put one;
%mend helper_one;

%macro helper_two;
  %put two;
%mend helper_two;

%macro multi;
  %helper_one;
  %helper_two;
%mend multi;
