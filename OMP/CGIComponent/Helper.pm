package OMP::CGIComponent::Helper;

=head1 NAME

OMP::CGIHelper - Helper for the OMP feedback system CGI scripts

=head1 SYNOPSIS

  use OMP::CGIComponent::Helper;
  use OMP::CGIComponent::Helper qw/public_url/;

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

@EXPORT_OK = (qw/public_url private_url/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# A default width for HTML tables
our $TABLEWIDTH = 720;

=head1 Routines

=over 4

=item B<public_url>

Return the URL where public cgi scripts can be found.

  $url = OMP::CGIComponent::Helper->public_url();

=cut

sub public_url {
  # Get the base URL
  my $url = OMP::Config->getData( 'omp-url' );

  # Now the CGI dir
  my $cgidir = OMP::Config->getData( 'cgidir' );

  return "$url" . "$cgidir";
}

=item B<private_url>

Return the URL where private cgi scripts can be found.

  $url = OMP::CGIComponent::Helper->private_url();

=cut

sub private_url {
  # Get the base URL
  my $url = OMP::Config->getData( 'omp-private' );

  # Now the CGI dir
  my $cgidir = OMP::Config->getData( 'cgidir' );

  return "$url" . "$cgidir";
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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
