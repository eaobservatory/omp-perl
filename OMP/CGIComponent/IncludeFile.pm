package OMP::CGIComponent::IncludeFile;

=head1 NAME

OMP::CGIComponent::IncludeFile - Include HTML fragments into OMP pages.

=head1 SYNOPSIS

use OMP::CGIComponent::IncludeFile;

=head1 DESCRIPTION

This module provides facilities for including raw HTML code into OMP
pages.  This allows data to be prepared offline but displayed in the OMP,
subject to the OMP's project based access controls.

It also includes utilities to deal with resources (e.g. images such as
graphs) which may be included by the included HTML.

=head1 SUBROUTINES

=over 4

=cut

use strict;
use warnings;

use CGI qw/header/;
use CGI::Carp qw/fatalsToBrowser/;
use Exporter;
use IO::File;

use OMP::Config;
use OMP::General;
use OMP::MSBServer;

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/include_file_ut/;

our %mime = (
  png  => 'image/png',
  gif  => 'image/gif',
  jpg  => 'image/jpeg',
  jpeg => 'image/jpeg',
);


=item B<include_file_ut>

Includes a file based on the UT date.

 include_file_ut('dq-nightly', $utdate[, 'index.html']);

The first parameter specifies the type of file,
which allows the directory containing it to be
read from the correpsonding 'directory' entry
in the OMP configuration file.  This directory
must contain a set of UT-date based subdirectories
in the normal ORAC style format, eg 19990401.

It is assumed that the caller has already verified
that the user has permission to see the specified file.

Return value: 1 if a file was successfully included,
or 0 if it could not be found.

=cut

sub include_file_ut {
  my ($type, $utdate, $filename) = @_;

  # Determine directory to search for files.
  my $directory = OMP::Config->getData('directory-'.$type);

  # Check UT date is valid.
  $utdate =~ s/-//g;
  if ($utdate =~ /^([0-9]{8})$/) {
    $utdate = $1;
  }
  else {
    croak('UT date string ['.$utdate.'] is not valid.');
  }

  # Apply default filename if not provided.
  $filename = 'index.html' unless $filename;

  my $pathname = join('/', $directory, $utdate, $filename);

  # Display a text warning if we can't find the file.  This may
  # be perfectly reasonable, so don't raise an actual error.
  unless (-e $pathname) {
    print '<p>No <tt>' . $type . '</tt> file is available for this date.</p>';
    return 0;
  }

  print "\n<!-- Begin included file " . $pathname . " -->\n";
  my $fh = new IO::File($pathname);

  foreach (<$fh>) {
    s/src="([^"]+)"/'src="' . _resource_url($type, $utdate, $1) . '"'/eg;
    print;
  }

  $fh->close();
  print "\n<!-- End included file " . $pathname . " -->\n";

  return 1;
}

=item B<get_resource>

OMP::CGIPage handler for serving resource files generated
offline (e.g. graphs).

  get_resource($cgi, %cookie);

This is done in the OMP so that we can check that
the user is permitted to view the resource.

Currently we check that the project had observations
on the night in question.  If more 'types' of resources
are to be added, it may be necessary to perform a
different kind of authorization for each one. 

=cut

sub get_resource {
  my $q = shift;
  my %cookie = @_;

  my $type = $q->url_param('type');
  my $utdate = $q->url_param('utdate');
  my $filename = $q->url_param('filename');

  # Check we are allowed to access this project.
  my $projectid = OMP::General->extract_projectid($cookie{'projectid'});
  croak 'Did not receive a valid project ID.' unless $projectid;

  # Check UT date is valid.
  $utdate =~ s/-//g;
  if ($utdate =~ /^([0-9]{8})$/) {
    $utdate = $1;
  }
  else {
    croak('UT date string ['.$utdate.'] is not valid.');
  }

  my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
                                               date => $utdate,
                                               comments => 0,
                                               transactions => 0,
                                               format => 'data',});

  unless (scalar @$observed) {
    print header(-status => '403 Forbidden');
    print '<h1>403 Forbidden</h1>';
    return;
  }

  _get_resource_ut($type, $utdate, $filename);
}

=back

=head1 INTERNAL SUBROUTINES

=over 4

=item B<_get_resource_ut>

Finds and prints out the contents of a file which is to be
found in a directory based on the UT date.

  _get_resource_ut($type, $utdate, $filename)

An HTTP header is included based on the file
type guessed from the extension.

=cut

sub _get_resource_ut {
  my ($type, $utdate, $filename) = @_;

  # Determine directory to search for files.
  my $directory = OMP::Config->getData('directory-'.$type);

  # Check UT date is valid.
  $utdate =~ s/-//g;
  if ($utdate =~ /^([0-9]{8})$/) {
    $utdate = $1;
  }
  else {
    croak('UT date string ['.$utdate.'] is not valid.');
  }

  # Check filename is valid.
  my $extension;
  if ($filename =~ /^([-_a-zA-Z0-9]+)\.([a-zA-Z0-9]+)$/) {
    $filename = $1 . '.' . $2;
    $extension = $2;
  }
  else {
    croak('File name [' . $filename . '] is not valid.');
  }

  my $pathname = join('/', $directory, $utdate, $filename);

  unless (-e $pathname) {
    print header(-status => '404 Not Found');
    print '<h1>404 Not Found</h1>';
    return;
  }

  print header(-type => (exists $mime{$extension})
                                  ? $mime{$extension}
                                  : 'application/octet-stream');

  my $fh = new IO::File($pathname);

  local $/ = undef;
  print <$fh>;

  $fh->close();
}

=item B<_resource_url>

Generates the URL to a script which an be used to server a given
resource.  The script should use L<get_resource> or a similar
routine to find and serve the resource after checking that
the user has permission to see it.

=cut

sub _resource_url {
  my ($type, $utdate, $filename) = @_;
  return 'get_resource.pl?type=' . $type
       . '&amp;utdate=' . $utdate
       . '&amp;filename=' . $filename;
}

=back

=head1 AUTHORS

Graham Bell E<lt>g.bell@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2013 Science and Technology Facilities Council.
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
