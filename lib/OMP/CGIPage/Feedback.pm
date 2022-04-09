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

use OMP::DateTools;
use OMP::ProjServer;
use OMP::CGIComponent::Helper qw/url_absolute/;
use OMP::CGIComponent::Feedback;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Project;

use base qw/OMP::CGIPage/;

$| = 1;

=head1 Routines

=over 4

=item B<add_comment_content>

Creates a page with a comment form.

  $page->add_comment_content($projectid);

=cut

sub add_comment_content {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  my $comp = new OMP::CGIComponent::Feedback(page => $self);

  return {
    project => OMP::ProjServer->projectDetails($projectid, 'object'),
    target => url_absolute($q),
    values => {
        # We don't re-display the form, but some pages link here with
        # a pre-prepared subject in a query parameter.
        subject => (scalar $q->param('subject')),
    },
    messages => [],
    num_comments => $comp->fb_entries_count($projectid),
  };
}

=item B<add_comment_output>

Submits comment and creates a page saying it has done so.

  $page->add_comment_output($projectid);

=cut

sub add_comment_output {
  my $self = shift;
  my $projectid = shift;

  my $comp = new OMP::CGIComponent::Feedback(page => $self);

  return {
    project => OMP::ProjServer->projectDetails($projectid, 'object'),
    target => undef,
    %{$comp->submit_fb_comment($projectid)},
    num_comments => $comp->fb_entries_count($projectid),
  };
}

=item B<fb_logout>

Gives the user a cookie with an expiration date in the past, effectively deleting the cookie.

  $page->fb_logout();

=cut

sub fb_logout {
  my $self = shift;

  return {
    message => "You are now logged out of the feedback system.",
  };
}

=item B<fb_output>

Creates the page showing feedback entries.

  $page->fb_output($projectid);

=cut

sub fb_output {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  return {
    target => url_absolute($q),
    project => OMP::ProjServer->projectDetails($projectid, 'object'),
    num_msbs => OMP::CGIComponent::MSB->new(page => $self)->msb_count($projectid),
    feedback => OMP::CGIComponent::Feedback->new(page => $self)->fb_entries($projectid),
    display_date => sub {
        return OMP::DateTools->display_date($_[0]);
    },
  };
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
