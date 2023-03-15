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

Authorization depends on the resource type.  If the user
authenticated via a project then C<$projectid> will
be defined.  Otherwise they will have authenticated
via local or staff access.

=over 4

=item dq-nightly

For project access, ensure C<$utdate> is given and check
that the project had observations on the night in question.

=item fault-image

Project access not currently permitted.

=back

=cut

sub get_resource {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;
  my $comp = new OMP::CGIComponent::IncludeFile(page => $self);

  my $type = $q->url_param('type');
  my $utdate = $q->url_param('utdate');
  my $faultid = $q->url_param('fault');
  my $filename = $q->url_param('filename');

  if (defined $utdate) {
    # Check UT date is valid.
    $utdate =~ s/-//g;
    if ($utdate =~ /^([0-9]{8})$/) {
      $utdate = $1;
    }
    else {
      croak('UT date string ['.$utdate.'] is not valid.');
    }
  }

  if (defined $faultid) {
    $faultid = OMP::General->extract_faultid("[${faultid}]");
    croak 'Invalid fault ID' unless defined $faultid;
  }

  my $subdirectory = undef;
  if ($type eq 'dq-nightly') {
    if (defined $projectid) {
      croak('UT date not specified') unless defined $utdate;
      my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
                                                   date => $utdate,
                                                   comments => 0,
                                                   transactions => 0,
                                                   format => 'data',});

      return $self->_write_forbidden() unless scalar @$observed;
    }

    $subdirectory = $utdate;
  }
  elsif ($type eq 'fault-image') {
    return $self->_write_forbidden() if defined $projectid;

    $subdirectory = $faultid;
  }
  else {
    croak "Resource type not recognized.";
  }

  $comp->_get_resource($type, $subdirectory, $filename);
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
