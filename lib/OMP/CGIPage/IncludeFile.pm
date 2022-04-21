package OMP::CGIPage::IncludeFile;

=head1 NAME

OMP::CGIPage::IncludeFile - Include HTML fragments into OMP pages

=head1 SYNOPSIS

  use OMP::CGIPage::IncludeFile;

=head1 METHODS

=over 4

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use IO::File;

use OMP::CGIComponent::IncludeFile;
use OMP::Config;
use OMP::General;
use OMP::MSBServer;
use OMP::NetTools;

use base qw/OMP::CGIPage/;

=item B<get_resource>

OMP::CGIPage handler for serving resource files generated
offline (e.g. graphs).

  $page->get_resource([$projectid]);

This is done in the OMP so that we can check that
the user is permitted to view the resource.

Currently we check that the project had observations
on the night in question.  If more 'types' of resources
are to be added, it may be necessary to perform a
different kind of authorization for each one.

=cut

sub get_resource {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;
  my $comp = new OMP::CGIComponent::IncludeFile(page => $self);

  my $type = $q->url_param('type');
  my $utdate = $q->url_param('utdate');
  my $filename = $q->url_param('filename');

  if (defined $projectid) {
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
      $self->_write_forbidden();
      return;
    }
  }

  $comp->_get_resource_ut($type, $utdate, $filename);
}

=back

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
