#!/local/perl-5.6/bin/perl -XT

# Simple CGI script to allow people to request password
# updates for their OMP project

use 5.006;
use warnings;
use strict;

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use HTML::WWWTheme;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib "/jac_sw/omp/msbserver";
use OMP::ProjServer;
use Error qw/ :try /;



$|=1; # Make unbuffered


my $q = new CGI;
print $q->header;

# Use the OMP theme and make some changes to it.
my $theme = new HTML::WWWTheme("/WWW/JACpublic/JAC/software/omp/LookAndFeelConfig");

$theme->SetHTMLStartString("<html><head><title>OMP Password request page</title></head>");
$theme->SetSideBarTop("<a href='http://jach.hawaii.edu/'>Joint Astronomy Centre</a>");

print $theme->StartHTML(),
      $theme->MakeHeader(),
      $theme->MakeTopBottomBar();

print "<H1>OMP Password Request Page</h1>";
print "You can use this page to request an updated password for your project.";
print "The password will be mailed to your registered email address.";


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


# End the document
print $theme->MakeTopBottomBar(),
      $theme->MakeFooter(),
      $theme->EndHTML();
