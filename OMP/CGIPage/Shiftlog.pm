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
use Carp;

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

  my $verified = parse_query( $q );

  # Print a header.
  print_header();

  # Submit the comment.
  submit_comment( $verified );

  # Display the comments for the current shift.
  display_shift_comments( $verified, \%cookie );

  # Display a form for inputting comments.
  display_comment_form( $q, $verified );

  # Display a form for changing the date.
  display_date_form( $q, $verified );

  # Display a form for changing the telescope.
  display_telescope_form( $q, $verified );

}

=back

=head1 SEE ALSO

C<OMP::CGIComponent::Shiftlog>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
