package OMP::CGIPage::Feedback;

=head1 NAME

OMP::CGIPage::Feedback - Web display of complete feedback pages.

=head1 SYNOPSIS

  use OMP::CGIPage::Feedback;

=head1 DESCRIPTION

Helper methods for constructing and displaying complete web pages
that display feedback comments.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::CGIComponent::Feedback;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Project;

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

  OMP::CGIComponent::Project::proj_status_table($q, %cookie);
  OMP::CGIComponent::Feedback::fb_entries_hidden($q, %cookie);
  OMP::CGIComponent::Feedback::comment_form($q, %cookie);
}

=item B<add_comment_output>

Submits comment and creates a page saying it has done so.

  add_comment_output($cgi, %cookie);

=cut

sub add_comment_output {
  my $q = shift;
  my %cookie = @_;

  OMP::CGIComponent::Project::proj_status_table($q, %cookie);
  OMP::CGIComponent::Feedback::submit_fb_comment($q, $cookie{projectid});
  OMP::CGIComponent::Feedback::fb_entries_hidden($q, %cookie);
}

=item B<fb_logout>

Gives the user a cookie with an expiration date in the past, effectively deleting the cookie.

  fb_logout($cgi);

=cut

sub fb_logout {
  my $q = shift;

  print $q->h2("You are now logged out of the feedback system.");
  print "You may see feedback for a project by clicking <a href='projecthome.pl'>here</a>.";
}

=item B<fb_output>

Creates the page showing feedback entries.

  fb_output($cgi, %cookie);

=cut

sub fb_output {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  OMP::CGIComponent::Project::proj_status_table($q, %cookie);
  OMP::CGIComponent::MSB::msb_sum_hidden($q, %cookie);
  OMP::CGIComponent::Feedback::fb_entries($q, %cookie);
}

=back

=head1 SEE ALSO

C<OMP::CGI::Component::Feedback>, C<OMP::CGI::Component::MSB>,
C<OMP::CGI::Component::Project>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
