package OMP::CGIPage;

=head1 NAME

OMP::CGIPage - Generate complete dynamic OMP web pages

=head1 SYNOPSIS

use CGI;

use OMP::CGIPage;

$query = new CGI;

$cgi = new OMP::CGIPage( CGI => $query );

$cgi->write_page(\&form_content, \&form_ouptut);

=head1 DESCRIPTION

This class generates the content of the OMP feedback system CGI scripts by
piecing together code from different places.  It also handles look and feel.

=cut

use 5.006;
use strict;
use warnings;
use CGI::Carp qw/fatalsToBrowser/;
use Template;

use OMP::Auth;
use OMP::CGIComponent::Helper qw/start_form_absolute/;
use OMP::Config;
use OMP::DBbackend;
use OMP::ProjDB;
use OMP::Error qw(:try);
use OMP::Fault;
use OMP::FaultDB;
use OMP::General;
use OMP::FaultServer;
use OMP::NetTools;
use OMP::Password;
use OMP::UserServer;

use HTML::WWWTheme;

our $VERSION = (qw$ Revision: 1.2 $ )[1];

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::CGIPage> object.

  $cgi = new OMP::CGIPage( CGI => $q );

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  my $c = {
           CGI => undef,
           RSSFeed => {},
           Theme => undef,
           Title => 'OMP Feedback System',
           Auth => undef,
          };

  # create the object (else we cant use accessor methods)
  my $object = bless $c, $class;

  # Populate object
  for my $key (keys %args) {
    my $method = lc($key);
    $object->$method( $args{$key});
  }

  return $object;
}

=back

=head2 Accessor Methods

=over 4

=item B<theme>

The C<HTML::WWWTheme> associated with this class.

  $theme = $cgi->theme;
  $cgi->theme( $theme);

This is used and generated internally.

=cut

sub theme {
  my $self = shift;
  if (@_) {
    my $theme = shift;
    confess "Incorrect type. Must be a HTML::WWWTheme object $theme"
      unless UNIVERSAL::isa( $theme, "HTML::WWWTheme");
    $self->{Theme} = $theme;
  }

  return $self->{Theme};
}

=item B<cgi>

Return the CGI object of class C<CGI>.

  $q = $cgi->cgi;
  $cgi->cgi( $q );

The argument must be in class C<CGI>.

=cut

sub cgi {
  my $self = shift;
  if (@_) {
    my $cgi = shift;
    croak "Incorrect type. Must be a CGI object"
      unless UNIVERSAL::isa( $cgi, "CGI");
    $self->{CGI} = $cgi;
  }
  return $self->{CGI};
}

=item B<html_title>

Return the string to be used for the HTML title.

  $title = $c->html_title;
  $c->html_title( $title );

Default value is "OMP Feedback System".

=cut

sub html_title {
  my $self = shift;
  if (@_) { $self->{Title} = shift; }
  return $self->{Title};
}

=item B<rss_feed>

The RSS feed associated with this object.

  %rss = $c->rss_feed();
  $c->rss_feed(%rss);

Takes a hash or hash reference with the following keys:

  title - Title of the RSS feed
  href  - URL of the RSS feed

Returns a hash.

=cut

sub rss_feed {
  my $self = shift;
  if (@_) {
    %{$self->{RSSFeed}} = (ref($_[0]) eq 'HASH' ? %{$_[0]} : @_);
  }
  return %{$self->{RSSFeed}};
}

=item B<auth>

The authentication object, if a user is logged in.

  $auth = $cgi->auth();
  $cgi->auth($auth);

=cut

sub auth {
  my $self = shift;
  if (@_) {
    my $auth = shift;
    throw OMP::Error::BadArgs('OMP::CGIPage->auth must be an OMP::Auth')
        unless UNIVERSAL::isa($auth, 'OMP::Auth');
    $self->{Auth} = $auth;
  }
  return $self->{Auth};
}

=back

=head2 General Methods

=over 4

=item B<_make_theme>

Create the theme object.

  $cgi->_make_theme;

=cut

sub _make_theme {
  my $self = shift;
  my $theme = $self->theme;
  unless (defined $theme) {
    # Use the OMP theme and make some changes to it.
    # This is in a different place on hihi than it is on malama

    my @themefile = (OMP::Config->getData('www-theme'),
                     "/JACpublic/JAC/software/omp/LookAndFeelConfig",
                     "/WWW/JACpublic/JAC/software/omp/LookAndFeelConfig");
    my $themefile;

    foreach (@themefile) {
      if (-e $_) {
        $themefile = $_;
        last;
      }
    }

    croak "Unable to locate OMPtheme file\n"
      unless $themefile;

    $theme = new HTML::WWWTheme($themefile);
    croak "Unable to instantiate HTML::WWWTheme object" unless $theme;

    $self->theme($theme);

  }
}

=item B<_write_footer>

Create the footer of the HTML document.

  $cgi->_write_footer;

=cut

sub _write_footer {
  my $self = shift;
  my $q = $self->cgi;
  my $theme = $self->theme;


  print $theme->MakeTopBottomBar();
  print "</td></table></td></tr></table>";
  print "<div ALIGN='right'><h6><a HREF='#top'>return to top...</a></h6></div></body>";
  print $theme->EndHTML();

}

=item B<write_page>

Create the page with the login form if login detail are needed.  Once login
details are acquired, call the code references or methods provided to this
method.

  $cgi->write_page( \&form_content, \&form_output, $auth_type, %opts );

First argument is the name of the C<OMP::CGI> method (or a code reference) to
be called for displaying a page with content and fields for taking parameters.
Second argument is the name of a method (or a code reference) to be called
for displaying the output generated by submitting any forms on the original
page, or undef if the same method should be used in both cases.

Options for C<auth_type> are:

=over 4

=item no_auth

The login verification process is skipped

=item staff

Require staff log-in.

=item project

Require membership of the project specified by the "project" query parameter,
or staff log-in.

=back

These options can be prefixed as follows (in this order):

=over 4

=item local_or_

Allow access from a local machine.

=item staff_or_

Allow access with staff log-in, even if futher authorization information
is not provided (e.g. the project ID for "project" C<auth_type>).

=back

Additional options are:

=over 4

=item no_header

The header and footer are omitted for the
output page to allow the output of types other than HTML.

=back

The given methods will be called with the validated project ID as the
first argument (after C<$self>).

The second method will only be called if the parameter 'show_output'
is defined in the CGI query parameter list.  The easiest way to make sure
the 'show_output' parameter is defined is to embed it as a hidden field
in any forms on the original page:

  start_form_absolute($query);

  $query->textfield(name=>'name', value=>'Bob');

  $query->hidden(name=>'show_output', value=>'true');

  $query->submit;

  $query->end_form;

The subroutines passed to this method should shift off the first argument.

  sub form_output {
    my $self = shift;
    ...
  }

=cut

sub write_page {
  my $self = shift;
  my $form_content = shift;
  my $form_output = shift;
  my $auth_type = shift;
  my %opt = @_;

  my $q = $self->cgi;

  my $form_same = 0;
  unless (defined $form_output) {
    $form_output = $form_content;
    $form_same = 1;
  }

  # Check to see that they are defined...
  # Check that they are code refs
  foreach ($form_content, $form_output) {
    throw OMP::Error::BadArgs("Code reference or method name not given")
      unless defined($_);

    my $type = ref($_);
    croak "Must be a code reference or method name."
      unless ($type eq 'CODE' or $self->can($_));
  }

  croak 'No auth_type specified' unless defined $auth_type;

  my $template = (exists $opt{'template'}) ? $opt{'template'} : undef;

  if (defined $opt{'title'}) {
    $self->html_title($opt{'title'});
  }

  # Retrieve the theme or create a new one
  $self->_make_theme;

  $self->auth(my $auth = OMP::Auth->log_in($q));

  return if $auth->abort();

  my $auth_ok = 0;

  if ($auth_type =~ '^local_or_(\w+)$') {
    $auth_type = $1;
    $auth_ok = 1 if OMP::NetTools->is_host_local();
  }

 if ($auth_type =~ '^staff_or_(\w+)$') {
    $auth_type = $1;
    $auth_ok = 1 if $auth->is_staff();
 }

  my @args = ();
  unless ($auth_type eq 'no_auth') {
    # Check to see if any login information has been provided. If not then
    # put up a login page.
    return $self->_write_login() unless ($auth_ok or defined $auth->user());

    if ($auth_type eq 'staff') {
      return $self->_write_forbidden() unless ($auth_ok or $auth->is_staff());
    }
    elsif ($auth_type eq 'project') {
      # Require project access.

      my $projectid = OMP::General->extract_projectid($q->url_param('project'));
      unless (defined $projectid) {
        return $self->_write_project_choice() unless $auth_ok;
      }
      else {
        # Ensure project ID is upper case before attempting authorization.
        $projectid = uc $projectid;
      }

      return $self->_write_forbidden()
        unless ($auth_ok or $auth->is_staff or $auth->has_project($projectid));

      push @args, $projectid;
      $self->_sidebar_project($projectid);
      $self->html_title($projectid . ': ' . $self->html_title());
    }
    else {
      croak 'Unrecognized auth_type value';
    }
  }

  my $extra = $self->_write_page_extra();
  throw OMP::Error::BadArgs("hashref not returned by _write_page_extra")
      unless 'HASH' eq ref $extra;
  return if (exists $extra->{'abort'} and $extra->{'abort'});
  push @args, @{$extra->{'args'}} if exists $extra->{'args'};

  my $mode_output = ($q->param('show_output')  or $q->url_param('output'))
                && !($q->param('show_content') or $q->url_param('content'));

  # Force output mode if there's no form (the 2 subroutines are the same)
  # and we want to serve non-HTML.
  $mode_output ||= ($opt{'no_header'} and $form_same);

  # Print HTML header (including sidebar)
  $self->_write_header(undef, \%opt)
    unless (defined $template) || ($opt{'no_header'} && $mode_output);

  # Now everything is ready for our output.

  # See if we should show content (display forms)
  my $result = $mode_output
    ? $self->_call_method($form_output, @args)
    : $self->_call_method($form_content, @args);

  unless ($opt{'no_header'} && $mode_output) {
    unless (defined $template) {
      # Write the footer
      $self->_write_footer()
    }
    else {
      $self->_write_http_header(undef, \%opt);
      $self->render_template($template, {
        %{$self->_write_page_context_extra(\%opt)},
        %$result});
    }
  }

  return;
}

sub _write_page_context_extra {
    my $self = shift;
    my $opt = shift;

    my $jscript_url = OMP::Config->getData('www-js');
    push @$jscript_url, map {'/' . $_} @{$opt->{'javascript'}} if exists $opt->{'javascript'};

    return {
        omp_title => $self->html_title,
        omp_style => $self->_get_style,
        omp_favicon => OMP::Config->getData('www-favicon'),
        omp_javascript => $jscript_url,
        omp_user => $self->auth->user,
    };
}

=item B<_write_page_extra>

Method to prepare extra information for the L<write_page> system.  Subclasses
should override this method to perform any additional steps required.  A
reference to a hash must be returned.  This may contain:

=over 4

=item abort

Stop processing if true.  This can be used, for example, if some kind of
selection page has been shown.

=item args

Reference to an array of additional arguments to pass to the handler methods.

=back

=cut

sub _write_page_extra {
    my $self = shift;
    return {};
}

=item B<write_page_finish_log_in>

Complete a 2-step log in process.

    $page->write_page_finish_log_in(%auth_options);

The given options are passed to C<OMP::Auth-E<gt>log_in>.  It should either
return an object with C<abort> or C<message> set.

Note that this method invokes C<_write_error> rather than showing the log in
page again with C<_write_login>.  This is because we may have ended up with
the wrong set of query parameters.

=cut

sub write_page_finish_log_in {
  my $self = shift;

  my $q = $self->cgi;

  $self->auth(my $auth = OMP::Auth->log_in($q, @_));

  return if $auth->abort();

  $self->_make_theme;

  if (defined $self->auth->message) {
    return $self->_write_error($self->auth->message);
  }

  return $self->_write_error('No log in process in progress.');
}

=item B<write_page_logout>

Creates a logout page and gives a cookie that has already expired.  A code reference
should be the only argument.

  $cgi->write_page_logout( \&content );

=cut

sub write_page_logout {
  my $self = shift;
  my $content = shift;

  my $q = $self->cgi;

  $self->auth(OMP::Auth->log_out($q));

  $self->html_title('Log out');

  $self->_make_theme;
  $self->_write_header();

  $content->($self);

  $self->_write_footer();
}

=item B<render_template>

Renders a Template::Toolkit template from the "templ" directory (as specified
by the www-templ configuration parameter.)

    $cgi->render_template($name, \%context);

=cut

sub render_template {
    my $self = shift;
    my $name = shift;
    my $context = shift;

    my $template = new Template({
        INCLUDE_PATH => scalar OMP::Config->getData('www-templ'),
    }) or die "Could not configure template object: $Template::ERROR";

    $template->process($name, $context) or die $template->error();
}

=back

=head2 Internal Methods

=over 4

=item B<_call_method>

Given a method name or code reference, call the method or code reference.

  $cgi->($method_name, @args);

=cut

sub _call_method {
  my $self = shift;
  my $method = shift;

  if (ref($method) eq 'CODE') {
    # It's a code reference; call it with self as the object.
    return $method->($self, @_);
  } else {
    # It's a method name, run it on self.
    return $self->$method(@_);
  }
}

=item B<_get_style>

Return the URL of the style-sheet

=item B<_set_style>

Set the URL of the style-sheet

=cut

{
  my $STYLE = OMP::Config->getData('www-css');

  sub _get_style {
    return $STYLE;
  }

  sub _set_style {
    my $self = shift;
    $STYLE = shift;
  }
}

=item B<_sidebar_project>

Set up a project sidebar.

  $page->_sidebar_project($projectid);

=cut

sub _sidebar_project {
  my $self = shift;
  my $projectid = shift;
  my $theme = $self->theme;
  my $q = $self->cgi;

  $theme->SetMoreLinksTitle("<font color=#ffffff>Project $projectid</font>");

  my @sidebarlinks = ("<a class='sidemain' href='projecthome.pl?project=$projectid'>Project home</a>",
                      "<a class='sidemain' href='feedback.pl?project=$projectid'>Feedback entries</a>",
                      "<a class='sidemain' href='fbmsb.pl?project=$projectid'>Program details</a>",
                      "<a class='sidemain' href='spregion.pl?project=$projectid'>Program regions</a>",
                      "<a class='sidemain' href='spsummary.pl?project=$projectid'>Program summary</a>",
                      "<a class='sidemain' href='fbcomment.pl?project=$projectid'>Add comment</a>",
                      "<a class='sidemain' href='msbhist.pl?project=$projectid'>MSB History</a>",
                      "<a class='sidemain' href='projusers.pl?project=$projectid'>Contacts</a>");

  # If there are any faults associated with this project put a link up to the
  # fault system and display the number of faults.
  my $faultdb = new OMP::FaultDB( DB => OMP::DBServer->dbConnection, );
  my @faults = $faultdb->getAssociations(lc($projectid), 1);
  push (@sidebarlinks, "<a class='sidemain' href='fbfault.pl?project=$projectid'>Faults</a>&nbsp;&nbsp;<span class='sidemain'>(" . scalar(@faults) . ")</span>")
    if ($faults[0]);

  push @sidebarlinks, "&nbsp;<br><a class='sidemain' href='/'>OMP Home</a>";

  $theme->SetInfoLinks(\@sidebarlinks);
}

=item B<_write_http_header>

Write the HTTP header, including cookie if present.

    $cgi->_write_http_header($status, \%opt);

=cut

sub _write_http_header {
  my $self = shift;
  my $status = shift;
  my $opt = shift;

  my $q = $self->cgi;
  my $cookie = $self->auth->cookie;

  my %header_opt = (-expires => '-1d');
  $header_opt{'-cookie'} = $cookie if defined $cookie;
  $header_opt{'-status'} = $status if defined $status;

  print $q->header(%header_opt);
}

=item B<_write_header>

Create the document header (and provide the cookie).

  $cgi->_write_header(undef, \%opt);

  $cgi->_write_header($status);

The header will also link the created document to the style sheet and
RSS feed.

=cut

sub _write_header {
  my $self = shift;
  my $status = shift;
  my $opt = shift // {};

  my $style = $self->_get_style;
  my %rssinfo = $self->rss_feed;

  my $theme = $self->theme;

  # Print the header info
  # Make sure there is a cookie if we're going to provide
  # it in the header
  $self->_write_http_header($status, $opt);

  my $title = $self->html_title;

  # HTML start string
  my $start_string = "<html><head><title>$title</title>";

  # Link to style sheet
  $start_string .= "<link rel=\"stylesheet\" type=\"text/css\" href=\"$style\" title=\"ompstyle\">"
    unless (! $style);

  $start_string .= '<meta name="theme-color" content="#55559b" />';

  # Link to RSS feed
  $start_string .= "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"$rssinfo{title}\" href=\"$rssinfo{href}\" />"
    unless (! exists $rssinfo{title});

  # Add omp icon and javascript
  my $jscript_url = OMP::Config->getData('www-js');
  push @$jscript_url, map {'/' . $_} @{$opt->{'javascript'}} if exists $opt->{'javascript'};
  my $favicon_url = OMP::Config->getData('www-favicon');
  $start_string .= "<link rel='icon' href='${favicon_url}'/>";
  $start_string .= "<script type='text/javascript' src='${_}'></script>" foreach @$jscript_url;

  # Close start string
  $start_string .= "</head>";

  $theme->SetHTMLStartString($start_string);

  $theme->SetSideBarTop("<a class='sidemain' href='https://www.eao.hawaii.edu/'>EAO local home</a>");

  # Get the location of blank.gif
  my $blankgif = OMP::Config->getData('blankgif');
  $theme->SetBlankGif($blankgif);

  my $user = $self->auth->user;
  if (defined $user) {
      my $sym = '';
      $sym .= ' &#x2605;' if $user->is_staff();
      push @{$theme->SetInfoLinks()},
        '&nbsp;<hr>&nbsp;<br><span class="sidemain">' . $user->name . $sym . '<span><br><a class="sidemain" href="fblogout.pl">Log out</a>';
  }

  print $theme->StartHTML(),
        $theme->MakeHeader(),
        $theme->MakeTopBottomBar();

}

=item B<_write_login>

Create a page with a login form.

  $cgi->_write_login();

=cut

sub _write_login {
  my $self = shift;
  my $q = $self->cgi;

  $self->_write_header();

  print $q->p($q->img({-src => '/images/banner_white.gif'})),
      $q->h1('Log in');

  if (defined $self->auth->message) {
    print $q->p($q->strong($self->auth->message));
  }

  print $q->div({-class => 'log_in_panel'},
    $q->p($q->a({-href => '#'}, 'Log in with Hedwig')),
    $q->div(
      start_form_absolute($q),
      $q->p(
        $q->hidden(-name => 'provider', -default => 'hedwig', -override => 1),
        $q->submit(-value => 'Log in with Hedwig', -name => 'submit_log_in'),
      ),
      $q->end_form()));

  print $q->div({-class => 'log_in_panel'},
    $q->p($q->a({-href => '#'}, 'EAO staff log in')),
    $q->div(
    $q->p("Please enter your user name and password."),
      start_form_absolute($q),
      # This hidden field contains the 'login_form' param that lets us know we've just come
      # from the login form, so we'll be sure to run the form_content callback and not
      # form_output.
      $q->hidden(-name=>'provider',
                 -default=>'staff', -override => 1),
      $q->hidden(-name=>'show_content',
                 -default=>1),
      $q->table(
        $q->Tr(
          $q->td('User name:'),
          $q->td({-colspan => '2'},
            $q->textfield(-name=>'username',
                          -size=>17,
                          -maxlength=>30))),
        $q->Tr(
          $q->td('Password:'),
          $q->td(
            $q->password_field(-name=>'password',
                               -default => '', -override => 1,
                               -size=>17,
                               -maxlength=>30)),
          $q->td($q->submit(-value => "Submit", -name => 'submit_log_in')))),
      $q->end_form()));

  $self->_write_footer();
}

=item B<_write_forbidden>

Create a page with "forbidden" error message.

  $cgi->_write_forbidden();

=cut

sub _write_forbidden {
  my $self = shift;
  my $q = $self->cgi;

  $self->_write_header('403 Forbidden');

  print $q->p($q->img({-src => '/images/banner_white.gif'})),
      $q->h1('Forbidden'),
      $q->p('The system was unable to verify your access to this page.');

  $self->_write_footer();
}

=item B<_write_error>

Create a page with an error message.

  $page->_write_error('Message', ...);

This method includes a header and footer, so that it can
be used from C<"no_header"> handler methods.

=cut

sub _write_error {
  my $self = shift;

  my $q = $self->cgi;

  $self->_write_header('500 Internal Server Error');

  print $q->h2('Error'), $q->p(\@_);

  $self->_write_footer();
}

=item B<_write_project_choice>

Create a page with a project choice form.

  $cgi->_write_project_choice();

=cut

sub _write_project_choice {
  my $self = shift;
  my $q = $self->cgi;

  $self->_write_header();

  my %proj_opts = ();
  my $datalist = '';
  if (defined $self->auth->user) {
    my $projects = $self->auth->projects;
    if (@$projects) {
      $proj_opts{'-list'} = 'projects';
      $datalist = join '',
        '<datalist id="projects">',
        (map {'<option value="' . $_ .'" />'} sort @$projects),
        '</datalist>';
    }
  }

  print $q->p($q->img({-src => '/images/banner_white.gif'})),
      $q->h1('Project');

  print $q->p("Please select a project."),
      start_form_absolute($q, -method => 'GET'),
      $q->table(
        $q->Tr(
          $q->td('Project:'),
          $q->td($q->textfield(
            -name => 'project',
            -size => 17,
            -maxlength => 30, %proj_opts) . $datalist,
          $q->td($q->submit(
            -value => "Submit",
            -name => ''))))),
      $q->end_form;

  $self->_write_footer();
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

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



