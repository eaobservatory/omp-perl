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

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use IO::File;

use OMP::Config;
use OMP::General;
use OMP::MSBServer;
use OMP::NetTools;

use base qw/OMP::CGIComponent/;

our %mime = (
  png  => 'image/png',
  gif  => 'image/gif',
  jpg  => 'image/jpeg',
  jpeg => 'image/jpeg',
);


=item B<include_file_ut>

Includes a file based on the UT date.

    my $html = $comp->include_file_ut('dq-nightly', $utdate[, filename => 'index.html'][, projectid => $projectid]);

The first parameter specifies the type of file,
which allows the directory containing it to be
read from the correpsonding 'directory' entry
in the OMP configuration file.  This directory
must contain a set of UT-date based subdirectories
in the normal ORAC style format, eg 19990401.

It is assumed that the caller has already verified
that the user has permission to see the specified file.

=cut

sub include_file_ut {
  my $self = shift;
  my $type = shift;
  my $utdate = shift;
  my %opt = @_;

  my $projectid = (exists $opt{'projectid'}) ? $opt{'projectid'} : undef;

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
  my $filename = (exists $opt{'filename'}) ? $opt{'filename'} : 'index.html';

  my $pathname = join('/', $directory, $utdate, $filename);

  # Display a text warning if we can't find the file.  This may
  # be perfectly reasonable, so don't raise an actual error.
  unless (-e $pathname) {
    return '<p>No <tt>' . $type . '</tt> file is available for this date.</p>';
  }

  my @result = ();
  push @result, "<!-- Begin included file " . $pathname . " -->";
  my $fh = new IO::File($pathname);

  foreach (<$fh>) {
    s/src="([^"]+)"/'src="' . _resource_url($type, $utdate, $1, $projectid) . '"'/eg;
    push @result, $_;
  }

  $fh->close();
  push @result, "<!-- End included file " . $pathname . " -->";

  return join "\n", @result;
}

=head1 INTERNAL SUBROUTINES

=over 4

=item B<_get_resource>

Finds and prints out the contents of a file which is to be
found in the given subdirectory.  The caller should ensure
that the subdirectory parameter is valid.

  $comp->_get_resource($type, $subdirectory, $filename)

An HTTP header is included based on the file
type guessed from the extension.

=cut

sub _get_resource {
  my $self = shift;
  my ($type, $subdirectory, $filename) = @_;

  # Determine directory to search for files.
  my $directory = OMP::Config->getData('directory-'.$type);

  # Check directory is valid.
  croak('Subdirectory not defined.') unless defined $subdirectory;
  if ($subdirectory =~ /^([-_.a-zA-Z0-9]+)$/) {
    $subdirectory = $1;
  }
  else {
    croak('Subdirectory ['.$subdirectory.'] is not valid.');
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

  my $pathname = join('/', $directory, $subdirectory, $filename);

  unless (-e $pathname) {
    print $self->cgi->header(-status => '404 Not Found');
    print '<h1>404 Not Found</h1>';
    return;
  }

  print $self->cgi->header(
      -type => exists $mime{$extension}
          ? $mime{$extension}
          : 'application/octet-stream',
      -expires => '+10m',
  );

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
  my ($type, $utdate, $filename, $projectid) = @_;
  my $url = 'get_resource.pl?type=' . $type
       . '&amp;utdate=' . $utdate
       . '&amp;filename=' . $filename;

  $url .= '&amp;project=' . $projectid if defined $projectid;

  return $url;
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
