package OMP::CGIComponent::Helper;

=head1 NAME

OMP::CGIHelper - Helper for the OMP feedback system CGI scripts

=head1 SYNOPSIS

  use OMP::CGIComponent::Helper qw/start_form_absolute/;

=head1 DESCRIPTION

Provide functions to generate commonly displayed items for the feedback
system CGI scripts, such as a table containing information on the current
status of a project.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Config;
use OMP::General;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/start_form_absolute url_absolute/);

%EXPORT_TAGS = (
                'all' =>[ @EXPORT_OK ],
               );

Exporter::export_tags(qw/ all /);

# A default width for HTML tables
our $TABLEWIDTH = 720;

=head1 Routines

=over 4

=item B<start_form_absolute>

Return a start form tag (generated using CGI->start_form) using
an "absolute" URL (without host).  Any additional arguments are
passed to that method.  The URL should only contain query
parameters from current URL parameters (not posted form parameters).

  print start_form_absolute($q);

=cut

sub start_form_absolute {
  my $q = shift;
  my %args = @_;

  my %url_opt = (-absolute => 1);
  unless (exists $args{'-method'} and $args{'-method'} eq 'GET') {
      # Create a new CGI object containing only the URL parameters.
      $q = $q->new({map {$_ => $q->url_param($_)} $q->url_param()});
      $url_opt{'-query'} = 1;
  }

  return $q->start_form(-action => $q->url(%url_opt), %args);
}

=item B<url_absolute>

Get an "absolute" URL (without host) including only query parameters.

=cut

sub url_absolute {
    my $q = shift;
    return $q->new({
        map {$_ => $q->url_param($_)} $q->url_param()
    })->url(-absolute => 1, -query => 1);
}

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
