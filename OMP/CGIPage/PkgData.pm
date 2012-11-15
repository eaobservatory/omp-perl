package OMP::CGIPage::PkgData;

=head1 NAME

OMP::CGIPage::PkgData - Routines to help web serving of data packaging

=head1 SYNOPSIS

  use OMP::CGIPage::PkgData;

=head1 DESCRIPTION

General routines required to create a web page for packaging
OMP data files for the PI. Note that JCMT data retrieval requests
are optionally routed through CADC.

=cut

use 5.006;
use strict;
use warnings;
use OMP::Error qw/ :try /;
use File::Basename;
our $VERSION = '0.03';

use OMP::ProjServer;
use OMP::PackageData;

=head1 PUBLIC FUNCTIONS

These functions write the web page.

=over 4

=item B<request_data>

Request the UT date of interest and/or package the data
and serve it. Will use CADC if the configuration for this telescope
requests it.

If inccal is not specified it defaults to true.

=cut

sub request_data {
  my $q = shift;
  my %cookie = @_;

  # First try and get the fault ID from the URL param list,
  # then try the normal param list.
  my $utdate = $q->url_param('utdate');
  $utdate = $q->param('utdate') unless $utdate;

  # if we have a date, package up the data
  if ($utdate) {

    my $inccal = $q->url_param('inccal');
    $inccal = $q->param('inccal') unless $inccal;
    $inccal = 1 unless defined $inccal;

    # Need to decide whether we are using CADC or OMP for data retrieval
    # To do that we need to know the telescope name
    my $tel = OMP::ProjServer->getTelescope( $cookie{projectid} );

    if (!defined $tel) {
      print "Error obtaining telescope name from project $cookie{projectid}\n";
      return;
    }

    # Now determine which retrieval scheme is in play (cadc vs omp)
    my $retrieve_scheme;
    try {
      $retrieve_scheme = OMP::Config->getData( "retrieve_scheme", telescope => $tel );
    } otherwise {
      $retrieve_scheme = 'omp';
    };

    if ($tel eq 'JCMT' && $retrieve_scheme =~ /cadc/i ) {
      &_package_data_cadc($q, $utdate, $inccal, \%cookie);
    } else {
      &_package_data($q, $utdate, $inccal, \%cookie);
    }

  } else {
    &_write_form($q, \%cookie);
  }

}


=back

=head2 Internal functions

=over 4

=item B<_write_form>

Write the form requesting a UT date.

  _write_form( $q, \%cookie );

=cut

sub _write_form {
  my $q = shift;
  my $cookie = shift;

  print $q->h2("Retrieve data for project ". $cookie->{projectid} );
  print "<table border=0><tr><td>";
  print $q->startform;
  print "<b>Enter a UT date: (YYYY-MM-DD)</b></td><td>";
  print $q->textfield(-name=>'utdate',
                      -size=>15,
                      -maxlength=>32);
  print "</td><tr><td>";
  print "Include calibrations:</td><td>";
  print $q->radio_group(-name=>'inccal',
                        -labels => { 1 => 'Yes', 0 => 'No' },
                        -values=>[1,0],
                        -default=>1);
  print "</td><tr><td colspan=2 align=right>";

  print $q->submit(-name=>'Submit');
  print $q->endform;
  print "</td></table>";

}

=item B<_package_data>

Write output HTML and package up the data.

  _package_data( $q, $utdate_string, $inccal, \%cookie );

=cut

sub _package_data {
  my $q = shift;
  my $utdate = shift;
  my $inccal = shift;
  my $cookie = shift;

  print $q->h2("Retrieving data for project ". $cookie->{projectid} .
    " and UT date $utdate");

  print "<p><b>Copying files and creating tar archive(s).  This normally takes several minutes per Gbyte.  Please do not point your browser to another page until the process is complete.</b></p>";

  if ($inccal) {
    print "[including calibrations]";
  } else {
    print "[without calibrations]";
  }

  # we use verbose messages
  print "<PRE>\n";
  my $pkg = new OMP::PackageData( utdate => $utdate,
                                  projectid => $cookie->{projectid},
                                  password => $cookie->{password},
                                  inccal => $inccal,
                                );

  $pkg->pkgdata;
  print "</PRE>\n";

  my @urls = $pkg->ftpurl;
  if (@urls) {
    my $plural = (scalar(@urls) > 1 ? "s" : "");
    print "Retrieve your data from the following url$plural :<br>\n";
    print join("\n", map { "<A href=\"$_\">$_</a><br>" } @urls);
  } else {
    print "There must have been an untrapped error. Could not obtain a url";
  }


}

=item B<_package_data_cadc>

Write output HTML and special form required for CADC retrieval

  _package_data_cadc( $q, $utdate_string, $inccal, \%cookie );

=cut

sub _package_data_cadc {
  my $q = shift;
  my $utdate = shift;
  my $inccal = shift;
  my $cookie = shift;

  print $q->h2("Determining data files associated with project ". $cookie->{projectid} .
    " and UT date $utdate");

  if ($inccal) {
    print "[including calibrations]";
  } else {
    print "[without calibrations]";
  }

  # Go through the package data object so that we do not need to worry about
  # inconsistencies with local retrieval
  print "<PRE>\n";
  my $pkg;
  my $E;
  try {
    $pkg = new OMP::PackageData( utdate => $utdate,
                                 projectid => $cookie->{projectid},
                                 password => $cookie->{password},
                                 inccal => $inccal,
                               );
  } catch OMP::Error::UnknownProject with {
    $E = shift;
    print "This project ID is not recognized by the OMP<br>\n";
  } otherwise {
    $E = shift;
    print "Odd data retrieval error: $E\n";
  };
  print "</PRE>\n";
  return if defined $E;

  print "<P>Data retrieval is now handled by the Canadian Astronomical Data Centre (CADC). ".
        "Pressing the button below will take you to the CADC data retrieval page with all your project files pre-selected. ".
        "You will be required to authenticate yourself to CADC. Note that calibration observations are not password protected so you may be asked for your password midway through the transfer. </P>";

  print "<p>To have access to any proprietary data, <B>you must have
   registered your CADC userid with the JAC.</B> Access permissions
   at the CADC are assigned to each file based on the CADC userid
   supplied with the data by the JAC.  It is not sufficient to have a
   userid at both institutions, even if they are the same!</p>\n";

  # Write a feedback message even though we can not be sure the person will click on the link
  $pkg->add_fb_comment( "(via CADC)" );

  # Get the obsGrp
  my $obsgrp = $pkg->obsGrp;

  # Now form the CADC form
  print $q->startform( -action=> "http://www.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/jcmt/search/downloads");

  # get the file names and strip path information if present
  my @obs = $obsgrp->obs();
  my @files = map { $_->simple_filename } @obs;
  print "$_\n"
    for $q->hidden( -name => "fileNameClass",
                    -default => \@files );

  print $q->submit(-name => "Retrieve from CADC" );
  print $q->endform;

}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002,2007 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
