#!/bin/sh

#  Files are copied/put on host kalani in /tmp/omp-out to download. So this
#  should run only on kalani.

dir='/tmp/omp-out'

mkdir "${dir}"  \
&& chmod 1755 "${dir}"  \
&& chown httpd:apache "${dir}"

