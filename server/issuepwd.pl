#!/local/perl-5.6/bin/perl -X

# Simple CGI script to allow people to request password
# updates for their OMP project

use 5.006;
use warnings;
use strict;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib "/jac_sw/omp/msbserver";
use OMP::ProjServer;
use Error qw/ :try /;

use CGI;

$!=1; # Make unbuffered

my $q = new CGI;
print $q->header;
print $q->start_html("OMP Password request page");

print $q->startform;
print "Project ID: ",$q->textfield('projectid','',8,20);
print "<P>", $q->submit( '  Request password  ');
print $q->endform;

if ($q->param) {
  my $projectid = $q->param("projectid");
  try {
    OMP::ProjServer->issuePassword( $projectid );
    print "<P>Password has been mailed to your registered address</p>\n";
  } catch OMP::Error::UnknownProject with {
    print "<P>Unable to process your request because this project ID does not exist in our database<p>\n";
  } otherwise {
    my $E = shift;
    print "<p>Unfortunately an error occurred whilst processing your request<p>\n";
    print "$E\n";
  }

}

print $q->end_html;
