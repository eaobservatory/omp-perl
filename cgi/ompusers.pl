#!/local/perl-5.6/bin/perl -XT

# simple CGI script to list current OMP users. Needs
# to be rewritten by Kynan.

use 5.006;
use warnings;
use strict;

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use HTML::WWWTheme;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib "/jac_sw/omp/test/omp/msbserver";
use OMP::UserServer;
use Error qw/ :try /;



$|=1; # Make unbuffered


my $q = new CGI;
print $q->header;

# Use the OMP theme and make some changes to it.
my $root = "/JACpublic/JAC/software/omp/LookAndFeelConfig";
my $file = ( -e $root ? $root : "/WWW$root");

my $theme = new HTML::WWWTheme("$file");

$theme->SetHTMLStartString("<html><head><title>OMP User information</title></head>");
$theme->SetSideBarTop("<a href='http://jach.hawaii.edu/'>Joint Astronomy Centre</a>");

print $theme->StartHTML(),
      $theme->MakeHeader(),
      $theme->MakeTopBottomBar();

print "<h1>OMP users</h1>";

my $users = OMP::UserServer->queryUsers( "<UserQuery></UserQuery>" );

if (@$users) {
  print "<TABLE border='1' width='100%'>\n";
  for (@$users) {
    print "<tr bgcolor='#7979aa'>";
    print "<TD>" . $_->userid ."</TD>";
    print "<TD>" . $_->html ."</TD>";
    print "<TD><a href=\"update_user.pl?".$_->userid."\">Update</a></TD>";
  }
  print "</TABLE>\n";
} else {
  print "No OMP users found!<br>\n";
}

# End the document
print $theme->MakeTopBottomBar(),
      $theme->MakeFooter(),
      $theme->EndHTML();
