package OMP::CGI::FeedbackPage;

=head1 NAME

OMP::CGI::FeedbackPage - Web display of complete feedback pages.

=head1 SYNOPSIS

  use OMP::CGI::FeedbackPage;

=head1 DESCRIPTION

Helper methods for constructing and displaying complete web pages
that display feedback comments.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::CGI::Feedback;
use OMP::CGI::MSB;
use OMP::CGI::Project;

$| = 1;

=head1 Routines

=over 4

=item B<add_comment_content>

Creates a page with a comment form.

  add_comment_content($cgi, %cookie);

=cut

sub add_comment_content {
  my $q = shift;
  my %cookie = @_;

  print $q->h2("Add feedback comment to project $cookie{projectid}");

  OMP::CGI::Project::proj_status_table($q, %cookie);
  OMP::CGI::Feedback::fb_entries_hidden($q, %cookie);
  OMP::CGI::Feedback::comment_form($q, %cookie);
}

=item B<add_comment_output>

Submits comment and creates a page saying it has done so.

  add_comment_output($cgi, %cookie);

=cut

sub add_comment_output {
  my $q = shift;
  my %cookie = @_;

  OMP::CGI::Project::proj_status_table($q, %cookie);
  OMP::CGI::Feedback::submit_fb_comment($q, $cookie{projectid});
  OMP::CGI::Feedback::fb_entries_hidden($q, %cookie);
}

=item B<fb_output>

Creates the page showing feedback entries.

  fb_output($cgi, %cookie);

=cut

sub fb_output {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  OMP::CGI::Project::proj_status_table($q, %cookie);
  OMP::CGI::MSB::msb_sum_hidden($q, %cookie);
  OMP::CGI::Feedback::fb_entries($q, %cookie);
}

=back

=head1 SEE ALSO

C<OMP::CGI::Feedback>, C<OMP::CGI::MSB>, C<OMP::CGI::Project>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
