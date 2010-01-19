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
piecing together code from different places.  It also handles cookie
management and look and feel.

=cut

use 5.006;
use strict;
use warnings;
use CGI::Carp qw/fatalsToBrowser/;

use OMP::Config;
use OMP::ProjServer;
use OMP::Cookie;
use OMP::Error qw(:try);
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultServer;
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
	   Cookie => [],
	   PrivateURL => OMP::Config->getData('omp-private'),
	   PublicURL => OMP::Config->getData('omp-url'),
	   RSSFeed => {},
	   Theme => undef,
	   Title => 'OMP Feedback System',
	   User => undef,
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

=item B<name>

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

=item B<cookie>

Returns an array reference containing objects of class C<OMP::Cookie>.
If called with a cookie object as an argument the object is stored with
the rest of the cookies.  When called with an array reference all
cookies are replaced.

  $cookie = $cgi->cookie;
  $cgi->cookie( $cookie );

=cut

sub cookie {
  my $self = shift;
  if (@_) {
    my $cookie = shift;
    my @cookies;

    if (ref($cookie) eq 'ARRAY') {
      # Multiple cookies.  Replace existing cookies with these ones
      for (@{$cookie}) {
	croak "Incorrect type. Must be a OMP::Cookie object"
	  unless UNIVERSAL::isa( $_, "OMP::Cookie");
      }

      @cookies = @{$cookie};
    } else {
      # Single cookie.  Place it in our cookie array.
      croak "Incorrect type. Must be a OMP::Cookie object"
	unless UNIVERSAL::isa( $cookie, "OMP::Cookie");

      @cookies = @{$self->{Cookie}}
	if (defined $self->{Cookie}->[0]);

      push(@cookies, $cookie);
    }

    # Get rid of duplicate cookies
    my %no_dupes = map {$_->name, $_} @cookies;
    @cookies = values %no_dupes;
    @{$self->{Cookie}} = @cookies;
  }

  if (wantarray) {
    return @{$self->{Cookie}};
  } else {
    return [ @{$self->{Cookie}} ];
  }
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

=item B<public_url>

Return the URL of the public CGI directory.

  $url = $c->public_url;
  $c->public_url( $url );

=cut

sub public_url {
  my $self = shift;
  if (@_) { $self->{PublicURL} = shift; }
  return $self->{PublicURL};
}

=item B<private_url>

Return the URL of the public CGI directory.

  $url = $c->private_url;
  $c->private_url( $url );

=cut

sub private_url {
  my $self = shift;
  if (@_) { $self->{PrivateURL} = shift; }
  return $self->{PrivateURL};
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

=item B<user>

The user ID of the current user.

  $user = $fcgi->user();
  $fcgi->user($userid);

Argument is a string that is a user ID.  Returns a string.

=cut

sub user {
  my $self = shift;
  if (@_) {
    $self->{User} = shift;
  } elsif (! defined $self->{User}) {
    # Take the category name from the cookie object
    # and cache it
    $self->{User} = $self->_get_param('user');
  }
  return $self->{User} || "";
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
  print "<br><div class='footer'>This system provided by the <a href='http://www.jach.hawaii.edu/JAC/software'>Joint Astronomy Centre Software Group</a></div>";
  print "<div ALIGN='right'><h6><a HREF='#top'>return to top...</a></h6></div></body>";
  print $theme->EndHTML();

}

=item B<_write_staff_login>

Create a login page that takes an OMP user id and staff password.

  $self->_write_staff_login( $failed );

Takes a single optional argument.  If the argument is true, a message
is displayed informing the user that their login information was
incorrect.

=cut

sub _write_staff_login {
  my $self = shift;
  my $arg = shift;

  my $q = $self->cgi;

  $self->_make_theme();

  $self->_write_header();

  print "<strong>The login details you provided were incorrect.</strong><br><br>"
    if (defined $arg);

  print "These pages are restricted to JAC staff only.  Please provide your user ID and the staff password.<br>";

  print "<table><tr valign=bottom><td align=right>";
  print $q->startform;

  print $q->hidden(-name=>'login_form',
		   -default=>1,);
  print $q->hidden(-name=>'show_content',
		   -default=>1);
  print $q->br;
  print "Username: </td><td>";
  print $q->textfield(-name=>'userid',
		      -size=>17,
		      -maxlength=>30);
  print $q->br;
  print "</td><tr><td>Staff Password: </td><td>";
  print $q->password_field(-name=>'password',
			   -size=>17,
			   -maxlength=>30);
  print "</td><td>";
  print $q->submit("Submit");
  print $q->endform;
  print "</td></table>";

  $self->_write_footer();
}

=item B<_write_admin_login>

Create a login page that takes an OMP user id and administrator password.

  $self->_write_admin_login();

=cut

sub _write_admin_login {
  my $self = shift;

  my $q = $self->cgi;

  $self->_make_theme();

  $self->_write_header();

  print "Please provide your user ID and the administrator password.<br>";

  print "<table><tr valign=bottom><td align=right>";
  print $q->startform;

  print $q->hidden(-name=>'login_form',
		   -default=>1,);
  print $q->hidden(-name=>'show_content',
		   -default=>1);
  print $q->br;
  print "Username: </td><td>";
  print $q->textfield(-name=>'userid',
		      -size=>17,
		      -maxlength=>30);
  print $q->br;
  print "</td><tr><td>Admin Password: </td><td>";
  print $q->password_field(-name=>'password',
			   -size=>17,
			   -maxlength=>30);
  print "</td><td>";
  print $q->submit("Submit");
  print $q->endform;
  print "</td></table>";

  $self->_write_footer();
}

=item B<write_page>

Create the page with the login form if login detail are needed.  Once login
details are acquired, call the code references or methods provided to this
method.

  $cgi->write_page( \&form_content, \&form_output, $no_verify );

First argument is the name of the C<OMP::CGI> method (or a code reference) to
be called for displaying a page with content and fields for taking parameters.
Second argument is the name of a method (or a code reference) to be called
for displaying the output generated by submitting any forms on the original
page.  If the third argument is true, the login verification process is
skipped.

The second method will only be called if the parameter 'show_output'
is defined in the CGI query parameter list.  The easiest way to make sure
the 'show_output' parameter is defined is to embed it as a hidden field
in any forms on the original page:

  $query->start_form;

  $query->textfield(name=>'name', value=>'Bob');

  $query->hidden(name=>'show_output', value=>'true');

  $query->submit;

  $query->end_form;

The subroutines passed to this method should shift off the first
The rest of the elements should be dumped to a hash as they contain the cookie
contents:

  sub form_output {
    my $query = shift;
    my %cookie = @_;
    ...
  }

=cut

sub write_page {
  my $self = shift;
  my ( $form_content, $form_output, $noauth ) = @_;

  my $q = $self->cgi;
  # Check to see that they are defined...
  # Check that they are code refs
  foreach ($form_content, $form_output) {
    throw OMP::Error::BadArgs("Code reference or method name not given")
      unless defined($_);

    my $type = ref($_);
    croak "Must be a code reference or method name."
      unless ($type eq 'CODE' or $self->can($_));
  }

  # Get parameters for the default cookie
  my %new_params = $self->_get_default_cookie_params();

  # Store new parameters to the cookie and reset the expiry time
  $self->_set_cookie(params=>\%new_params);

  # Retrieve the theme or create a new one
  $self->_make_theme;

  if (! $noauth) {
    # Check to see if any login information has been provided. If not then
    # put up a login page.  If there is login information verify it and put
    # up a login page if it is incorrect.
    my $verify = $self->_verify_login;

    if ($verify == 2) {
      # No login details were provided
      $self->_write_login();
      return;
    } elsif ($verify == 0) {
      # Login failed
      $self->_write_login(1);
      return;
    }
  }

  # Set the cookie with a new expiry time (this occurs even if we
  # already have one. This allows for automatic expiry if noone
  # reloads the page

  # Set up sidebar
  if (! $noauth) {
    $self->_sidebar();
  }

  # Print HTML header (including sidebar)
  $self->_write_header();

  # Now everything is ready for our output. Just call the
  # code ref with the cookie contents

  # See if we should show content (display forms)
  if ($q->param('show_content') or $q->url_param('content')) {
    $self->_call_method($form_content);
  } elsif ($q->param('show_output') or $q->url_param('output')) {
    $self->_call_method($form_output);
  } else {
    $self->_call_method($form_content);
  }

  # Write the footer
  $self->_write_footer();

  return;
}

=item B<write_page_proposals>

Write a page with the ability to server proposal files in whatever format they
are in.  This subroutine is special because it allows you to specify the header attributes so you can do things other than "text/html."  Prompts
for project password if not run locally.  If the output subroutine is being
called the header is not written and must be written instead by the output
subroutine.

  $cgi->write_page_proposals( \&form_content, \&form_output);

=cut

sub write_page_proposals {
  my $self = shift;
  my ($form_content, $form_output) = @_;

  my $q = $self->cgi;

  my $c = new OMP::Cookie( CGI => $q );

  $self->cookie( $c );

  my %cookie = $c->getCookie;

  # Retrieve the theme or create a new one
  $self->_make_theme;

  if ($q->param) {

    my $notlocal;

    my $private = OMP::Config->getData('omp-private');

    # Do authentication if we're not running on the private web server
    if ($q->url !~ /^$private/) {
      $notlocal = 1;
      $cookie{notlocal} = 1;
    }

    if ($notlocal) {

      # Store the password and project id for verification
      if ($q->param('login_form')) {
	$cookie{projectid} = $q->param('projectid');
	$cookie{password} = $q->param('password');
      }

      # Verify a password of some sort
      my $verify;
      if (exists $cookie{projectid} and exists $cookie{password}) {
	$verify = OMP::ProjServer->verifyPassword($cookie{projectid}, $cookie{password});
      } else {
	$self->_write_login($q->url_param('urlprojid'));
	return;
      }

      if (! $verify) {
	$self->_write_login($q->url_param('urlprojid'));
	return;
      }

    }

    $form_output->($q, %cookie);

  } else {
    # Set the cookie with a new expiry time (this occurs even if we
    # already have one. This allows for automatic expiry if noone
    # reloads the page
    $c->setCookie( $self->_get_exp_time, %cookie );

    # Print HTML header
    $self->_write_header();

    $form_content->($q, %cookie);

    $self->_write_footer();
  }
}

=item B<write_page_noauth>

Creates the page but doesn't do a login.  This is for CGI scripts
that call functions which don't require project authentication.

  $cgi->write_page_noauth( \&form_content, \&form_output );

=cut

sub write_page_noauth {
  my $self = shift;
  my ($form_content, $form_output) = @_;

  $self->write_page($form_content, $form_output, 1);
}

=item B<write_page_staff>

Do a staff authentication login, then create pages as normal.

  $cgi->write_page_staff( \&form_content, \&form_output, $noauth );

If the optional third argument is true, no project login authentication
is done.

=cut

sub write_page_staff {
  my $self = shift;
  my @args = @_;
  my $noauth = defined $args[2] ? pop @args : undef;
  my $q = $self->cgi;

  # Initialize the cookie
  $self->_set_cookie(name=>"OMPSTAFF");
  my $cookie = $self->_get_cookie("OMPSTAFF");
  my %cookie;

  # Use cookie parameters if they exist
  %cookie = $cookie->getCookie if (defined $cookie);
  my $userid = $cookie{userid};
  my $password = $cookie{password};

  # If we just came from the login form override the cookie
  # contents with the query parameters.
  if ($q->param('login_form')) {
    $userid = $q->param('userid');
    $password = $q->param('password');
  }

  my $verifyuser;
  my $verifypass;
  if ($userid and $password) {
    try {
      $verifyuser = OMP::UserServer->verifyUser($userid);
      $verifypass = OMP::Password->verify_staff_password($password);
    } catch OMP::Error::Authentication with {
      # Login failed...
      my $E = shift;
      $self->_write_staff_login(1);
      return;
    } otherwise {
      my $E = shift;
      croak "Error: $E";
    };
  } else {
    # User hasn't provided login details yet
    $self->_write_staff_login;
    return;
  }

  if (defined $verifyuser and defined $verifypass) {
    # The user ID and password have been verified.  Update the
    # cookie and continue as normal.
    $cookie{userid} = $userid;
    $cookie{password} = $password;
    $self->_set_cookie(name=>"OMPSTAFF", params=>\%cookie);

    # Only write page with  project authentication if the noauth
    # argument is false
    if (! $noauth) {
      $self->write_page(@args);
    } else {
      $self->write_page_noauth(@args);
    }
  } else {
    # Login details were incorrect
    $self->_write_staff_login(1);
  }
}

=item B<write_page_admin>

Like write_page_staff but takes the admin password instead.

  $cgi->write_page_admin( \&form_content, \&form_output );

In order for the output subroutine to be called, the form that submits
parameters should also contain a CGI query parameter called B<show_output>:

  $query->start_form;

  $query->textfield(name=>'name', value=>'Bob');

  $query->hidden(name=>'show_output', value=>'true');

  $query->submit;

  $query->end_form;

=cut

sub write_page_admin {
  my $self = shift;
  my ($form_content, $form_output) = @_;

  my $q = $self->cgi;

  my $c = new OMP::Cookie( CGI => $q, );
  $self->cookie( $c );

  my %cookie = $c->getCookie;

  # If we just came from the login form override the cookie contents with
  # the query parameters.
  if ($q->param('login_form')) {
    $cookie{userid} = $q->param('userid');
    $cookie{password} = $q->param('password');
  }

  my $verifyuser;
  my $verifypass;
  if ($cookie{userid} and $cookie{password}) {
    $verifyuser = OMP::UserServer->verifyUser($cookie{userid});
    $verifypass = OMP::Password->verify_administrator_password($cookie{password});
  }

  $self->_make_theme;

  if ($verifyuser and $verifypass) {
    # The user ID and password have been verified.  Continue as normal.
    $c->setCookie( $self->_get_exp_time, %cookie );

    $self->_write_header();

    if ($q->param('show_output')) {
      $form_output->($q, %cookie);
    } else {
      $form_content->($q, %cookie);
    }

      $self->_write_footer();

  } else {
    # The user ID and password were not verified.  This could be because
    # we haven't attempted to log in yet, or because the password or user ID
    # provided on the login page were incorrect.

    if ($q->param('login_form')) {
      # The login form was filled out, but atleast some of the information provided
      # was incorrect

      if (! $verifyuser or ! $verifypass) {
	$self->_write_admin_login();
      }

    } else {

      # We haven't been to the login page yet so let's go there
      $self->_write_admin_login;
    }
  }

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

  my $c = new OMP::Cookie( CGI => $q,);
  $self->cookie( $c );

  $c->flushCookie();

  $self->_make_theme;
  $self->_write_header();

  $content->($q);

  $self->_write_footer();
}

=back

=head2 Internal Methods

=over 4

=item B<_call_method>

Given a method name or code reference, call the method or code reference.

  $cgi->($method_name);

=cut

sub _call_method {
  my $self = shift;
  my $method = shift;

  if (ref($method) eq 'CODE') {
    # It's a code reference; call it with query and cookie arguments
    my $q = $self->cgi;
    my $c = $self->_get_cookie;
    my %cookie = $c->getCookie;
    $method->($q, %cookie);
  } else {
    # It's a method name, run it on self
    $self->$method;
  }
  return;
}

=item B<_get_cookie>

Retrieve a C<CGI::Cookie> object from the internal cookie cache (not from
the browser).

  $cookie = $cgi->_get_cookie($name);

Argument is the name of the cookie.  Returns undef if the cookie could
not be retrieved.  Returns the default cookie if no name argument is
provided

=cut

sub _get_cookie {
  my $self = shift;
  my $name = shift || OMP::Cookie->default_name;

  # If we've got the cookie in our object, return it
  my @cookies = $self->cookie;
  for my $cookie (@cookies) {
    return $cookie if ($cookie->name eq $name);
  }

  return undef;
}

=item B<_get_cookie_hash>

Return the key=value contents of a cookie.

  $cookie = $cgi->_get_cookie_hash($name);

Argument is the name of the cookie.  Returns undef if the cookie could
not be retrieved.  Returns the contents of the default cookie if no
name argument is provided.

=cut

sub _get_cookie_hash {
  my $self = shift;
  my $name = shift || OMP::Cookie->default_name;

  my $cookie = $self->_get_cookie($name);
  return (defined $cookie ? $cookie->getCookie : undef);
}

=item B<_get_default_cookie_params>

Return a hash containing key/value pairs of query parameters to store to
the default cookie.

  %params = $cgi->_get_default_cookie_params()

=cut

sub _get_default_cookie_params {
  my $self = shift;
  my $q = $self->cgi;
  my %params;

  # If a 'user' field has been filled in store that value in the cookie
  if ($q->param('user')) {
    $params{user} = $q->param('user');
  }

  if ($q->param('projectid')) {
    $params{projectid} = $q->param('projectid');
  }

  if ($q->url_param('urlprojid')) {
    $params{projectid} = $q->url_param('urlprojid');
  }

  if ($q->param('password')) {
    $params{password} = $q->param('password');
  }

  return %params;
}

=item B<_get_param>

Return the value of the named parameter from the cookie.  If the value
does not exist in the cookie, attempt to get it from the query parameter
list.

  $value = $cgi->_get_param($name);

Argument is a string that is the name of a parameter. Returns undefined
value if the parameter could not be found.

=cut

sub _get_param {
  my $self = shift;
  my $name = shift;
  my @cookies = $self->cookie;
  my $value = undef;

  if ($cookies[0]) {
    for my $cookie (@cookies) {
      my %cookie = $cookie->getCookie;
      $value = $cookie{$name}
	if (exists $cookie{$name});
    }
  }

  if (! defined $value) {
    # Didn't get param from cookies.  Try query parameter list now
    my $q = $self->cgi;
    $value = $q->param($name) || $q->url_param($name);
  }

  return $value;
}


=item B<_set_cookie>

Update a cookie's parameters and reset its expiration date.

  $cgi->_set_cookie(name=>$name, params=>\%params);

Arguments are provided in hash format.  The following keys are
accepted:

  name   - Name of the cookie.  Defaults to name of the default
           cookie if not defined.
  params - The key=value pairs to store to the cookie as a hash
           reference. If not provided, cookie will retain its
           current values.

=cut

sub _set_cookie {
  my $self = shift;
  my %args = @_;
  my $name = $args{name};
  my %params = (defined $args{params} ? %{$args{params}} : undef);

  # Try to obtain the cookie from our cache first
  my $cookie;
  $cookie = $self->_get_cookie($name);

  if (! defined $cookie) {
    $cookie = new OMP::Cookie(CGI => $self->cgi);
    $cookie->name($name) if (defined $name);
  }

  my %curr_params = $cookie->getCookie;

  # Merge current and new parameters
  %params = (%params ? (%curr_params, %params) : %curr_params);

  # Now set and store the cookie
  $cookie->setCookie( $self->_get_exp_time, %params );
  $self->cookie( $cookie );

  return;
}

=item B<_get_exp_time>

Return the cookie expiry time in minutes.

=item B<_get_style>

Return the URL of the style-sheet

=item B<_set_exp_time>

Set the cookie expiry time in minutes.

=item B<_set_style>

Set the URL of the style-sheet

=cut

{
  my $EXPTIME = 40;
  my $STYLE = OMP::Config->getData('omp-url') . OMP::Config->getData('www-css');

  sub _get_exp_time {
    return $EXPTIME;
  }

  sub _get_style {
    return $STYLE;
  }

  sub _set_exp_time {
    my $self = shift;
    $EXPTIME = shift;
  }

  sub _set_style {
    my $self = shift;
    $STYLE = shift;
  }
}

=item B<_sidebar>

Create and display a sidebar with a 'logout' link

  $cgi->_sidebar();

=cut

sub _sidebar {
  my $self = shift;
  my $theme = $self->theme;
  my $q = $self->cgi;
  my $c = $self->_get_cookie;
  my %cookie = $c->getCookie;

  my $projectid = uc($self->_get_param('projectid'));

  my $ompurl = $self->public_url;
  my $cgidir = OMP::Config->getData('cgidir');

  $theme->SetMoreLinksTitle("<font color=#ffffff>Project $projectid</font>");

  my @sidebarlinks = ("<a class='sidemain' href='projecthome.pl'>$cookie{projectid} Project home</a>",
		      "<a class='sidemain' href='feedback.pl'>Feedback entries</a>",
		      "<a class='sidemain' href='fbmsb.pl'>Program details</a>",
		      "<a class='sidemain' href='fbcomment.pl'>Add comment</a>",
		      "<a class='sidemain' href='msbhist.pl'>MSB History</a>",
		      "<a class='sidemain' href='projusers.pl'>Contacts</a>",
		      "<a class='sidemain' href='/'>OMP home</a>",);

  # If there are any faults associated with this project put a link up to the
  # fault system and display the number of faults.
  my $faultdb = new OMP::FaultDB( DB => OMP::DBServer->dbConnection, );
  my @faults = $faultdb->getAssociations(lc($projectid), 1);
  push (@sidebarlinks, "<a class='sidemain' href='fbfault.pl'>Faults</a>&nbsp;&nbsp;(" . scalar(@faults) . ")")
    if ($faults[0]);

  push (@sidebarlinks, "<br><a class='sidemain' href='fblogout.pl'>Logout</a></font>");
  $theme->SetInfoLinks(\@sidebarlinks);
}

=item B<_verify_login>

Return 1 if login details (project ID and project password) are correct.

  $cgi->_verify_login()

Returns 2 if no login details could be found.  Returns 0 otherwise.

=cut

sub _verify_login {
  my $self = shift;
  my $q = $self->cgi;
  my $c = $self->_get_cookie;
  my %cookie = $c->getCookie;

  # Use URL parameter projectid if it's available
  my $projectid = $q->url_param('urlprojid');
  my $password;

  if (exists $cookie{projectid} and exists $cookie{password}) {
    # Use cookie detials
    $projectid = $cookie{projectid}
      unless (defined $projectid);
    $password = $cookie{password};
  } elsif (defined $q->param('projectid') and defined $q->param('password')) {
    # Use query parameter details
    $projectid = $q->param('projectid')
      unless (defined $projectid);
    $password = $q->param('password');
  } else {
    # No login details exist
    return 2;
  }
  my $verify = OMP::ProjServer->verifyPassword($projectid, $password);
  return ($verify ? 1 : 0);
}

=item B<_write_header>

Create the document header (and provide the cookie).

  $cgi->_write_header();

The header will also link the created document to the style sheet and
RSS feed.

=cut

sub _write_header {
  my $self = shift;

  my $style = $self->_get_style;
  my %rssinfo = $self->rss_feed;

  my $q = $self->cgi;
  my $cookie = $self->cookie;
  my $theme = $self->theme;

  # Convert the OMP::Cookie objects to CGI::Cookie objects
  for my $c (@$cookie) {
    $c = $c->cookie;
  }

  # Print the header info
  # Make sure there is atleast one cookie if we're going to provide
  # them in the header

  if ($cookie->[0]) {
    print $q->header( -cookie => $cookie,
		      -expires => '-1d' );
  } else {
    print $q->header( -expires => '-1d' );
  }

  my $title = $self->html_title;

  # HTML start string
  my $start_string = "<html><head><title>$title</title>";

  # Link to style sheet
  $start_string .= "<link rel=\"stylesheet\" type=\"text/css\" href=\"$style\" title=\"ompstyle\">"
    unless (! $style);

  # Link to RSS feed
  $start_string .= "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"$rssinfo{title}\" href=\"$rssinfo{href}\" />"
    unless (! exists $rssinfo{title});

  # Add omp icon and javascript
  my $jscript_url = OMP::Config->getData('omp-url') . OMP::Config->getData('www-js');
  my $favicon_url = OMP::Config->getData('omp-url') . OMP::Config->getData('www-favicon');
  $start_string .= "<link rel='icon' href='${favicon_url}'/><script type='text/javascript' src='${jscript_url}'></script>";

  # Close start string
  $start_string .= "</head>";

  $theme->SetHTMLStartString($start_string);

  $theme->SetSideBarTop("<a class='sidemain' href='http://www.jach.hawaii.edu/'>Joint Astronomy Centre</a>");

  # These links will go under the 'JAC Divisions' heading
  my @links = ("<a class='sidemain' HREF='http://www.jach.hawaii.edu'>JAC Home</a>",
	       "<a class='sidemain' HREF='http://www.jach.hawaii.edu/JCMT/'>JCMT</a>",
	       "<a class='sidemain' HREF='http://www.jach.hawaii.edu/UKIRT/'>UKIRT</a>",
	       "<a class='sidemain' HREF='http://www.jach.hawaii.edu/divisions.html'>JAC Divisions</a>",
	       "<a class='sidemain' HREF='http://www.jach.hawaii.edu/staff_wiki'>Staff Wiki</a>",
	       "<a class='sidemain' HREF='http://outreach.jach.hawaii.edu/'>Outreach</a>",
	       "<a class='sidemain' HREF='http://www.jach.hawaii.edu/weather/'>Weather</a>",
	       "<a class='sidemain' HREF='http://www.jach.hawaii.edu/Seminars/seminars.html'>JAC Seminars</a>",
	       "<a class='sidemain' HREF='http://www.jach.hawaii.edu/admin/contact.html'>Contact info</a>",

);

  # Get the location of blank.gif
  my $blankgif = OMP::Config->getData('omp-url') . OMP::Config->getData('blankgif');
  $theme->SetSideBarMenuLinks(\@links);
  $theme->SetBlankGif($blankgif);

  print $theme->StartHTML(),
        $theme->MakeHeader(),
	$theme->MakeTopBottomBar();

}

=item B<_write_login>

Create a page with a login form.

$cgi->_write_login($failed);

If the optional argument is true, a message is displayed informing
the user that their login attempt failed.

If the URL query parameter 'urlprojid' exists, it will be the default
value for the project ID text field.

=cut

sub _write_login {
  my $self = shift;
  my $failed = shift;
  my $q = $self->cgi;
  my $c = $self->cookie;
  my $projectid = $q->url_param('urlprojid');

  $self->_write_header();

  print "<img src='/images/banner_white.gif'><p><p>";
  print $q->h1('Login');

  if (defined $failed) {
    print "<strong>The login details you provided were incorrect</strong><br><br>";
  }

  if ($projectid) {
    print "Please enter the password required for access to project information and data.";
  } else {
    print "Please enter the project ID and password. These are required for access to project information and data.";
  }

  print 'Passwords are project-specific, not user-specific. If you have lost your password and you are the PI, you can get <a href="/cgi-bin/issuepwd.pl"> generate a new password </a>.';

  print "<table><tr valign='bottom'><td>";
  print $q->startform,

    # This hidden field contains the 'login_form' param that lets us know we've just come
    # from the login form, so we'll be sure to run the form_content callback and not
    # form_output.
        $q->hidden(-name=>'login_form',
		   -default=>1,),
	$q->hidden(-name=>'show_content',
		   -default=>1),
        $q->br,
	"Project ID: </td><td colspan='2'>",
	$q->textfield(-name=>'projectid',
		      -default=>$projectid,
		      -size=>17,
		      -maxlength=>30),
	$q->br,
	"</td><tr><td>Password: </td><td>",
	$q->password_field(-name=>'password',
			   -size=>17,
			   -maxlength=>30),
	"</td><td>",
	$q->submit("Submit"),
	$q->endform;
  print "</td></table>";

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
along with this program (see SLA_CONDITIONS); if not, write to the 
Free Software Foundation, Inc., 59 Temple Place, Suite 330, 
Boston, MA  02111-1307  USA


=cut

1;



