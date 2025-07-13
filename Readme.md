Open CASCADE Technology test data set repo
==========================================

This repo contains data files used by
[OCCT tests](https://dev.opencascade.org/doc/overview/html/occt_contribution__tests.html).

The data files come from two primary sources:

* Official datasets published with OCCT releases
* Additional data extracted from attachments to publicly accessible issues in 
  [OCCT bug tracker](https://tracker.dev.opencascade.org)

The additional files are found in bug tracker using the script `getocctdata.tcl`
located in `scripts`.

Before adding any new file to the repo, it should be checked using command
`testfile` available in OCCT DRAW, this is mainly to prevent duplicates and
check that Unix-style (LF) end-of-lines are used for text files.
