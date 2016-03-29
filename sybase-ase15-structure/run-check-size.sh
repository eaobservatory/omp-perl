#!/bin/sh

# A simple wrapper to loop over user databases to see size statistics.

root='/jac_sw/omp/msbserver'
checker="${root}/sybase-ase15-structure/check-size.pl"

for db in  \
  jcmt_tms \
  jcmt     \
  ukirt    \
  omp
do
  # Pipe the output to "head -n 12" to avoid table size listing.
  "${checker}" -D "${db}"
  # Add blank space to separate the output.
  printf "\n\n"
done

