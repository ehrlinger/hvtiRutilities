*_______________________________________________________________________;
* MACRO NAME:  DocMacro
* SHORT DESC:  Does a documented thing
*-----------------------------------------------------------------------;
* CREATED BY:  Artis, Amanda                                  2019/04/05
*-----------------------------------------------------------------------;
* MODIFIED BY:  Artis, Amanda                                 2019/04/09
*
* Added binned summary estimates to the output.
*_______________________________________________________________________;
* MACRO CALL
*
* %DocMacro(DSN, NBINS)
*_______________________________________________________________________;
%macro DocMacro(dsn, nbins);
  %put &dsn. &nbins.;
%mend DocMacro;
