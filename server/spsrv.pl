#!/local/perl-5.6/bin/perl -X

use 5.006;
use warnings;
use strict;

use lib "/jac_sw/omp/msbserver";
use OMP::SpServer;

use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to("OMP::SpServer")
  ->options({compress_threshold=>500})
  ->handle;

