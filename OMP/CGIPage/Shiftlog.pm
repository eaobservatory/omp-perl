package OMP::CGIPage::Shiftlog;

=head1 NAME

OMP::CGIPage::Shiftlog - Display complete web pages for the shiftlog tool.

=head1 SYNOPSIS

  use OMP::CGIComponent::Shiftlog;

  shiftlog_page( $cgi );

=head1 DESCRIPTION

This module provides routines to display complete web pages for viewing
shiftlog information, and submitting shiftlog comments.

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;

use OMP::CGIComponent::Shiftlog;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw(shiftlog_page);

our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags(qw/ all /);


=head1 Routines

All routines are exported by default.

=over 4

=item B<shiftlog_page>

Creates a page with a form for filing a shiftlog entry
after a form on that page has been submitted.

  shiftlog_page( $cgi );

The only argument is the C<CGI> object.

=cut

sub shiftlog_page {
  my $q = shift;
  my %cookie = @_;

  my $parsed = parse_query( $q );

  print_header();

  submit_comment( $parsed );

  display_shift_comments( $parsed, \%cookie );

  display_comment_form( $q, $parsed );

  display_date_form( $q, $parsed );

  display_telescope_form( $q, $parsed );
}

=back

=head1 SEE ALSO

C<OMP::CGIComponent::Shiftlog>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
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
