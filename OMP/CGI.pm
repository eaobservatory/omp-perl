package OMP::CGI;

=head1 NAME

OMP::CGI - Content and functions for the OMP Feedback system CGI scripts

=head1 SYNOPSIS

use OMP::CGI;

$cgi = new OMP::CGI( CGI => $q );

$cgi->write_page(\&form_content, \&form_ouptut);

=head1 DESCRIPTION

This class generates the content of the OMP feedback system CGI scripts by
piecing together code from different places.  It also handles cookie
management and look and feel.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::ProjServer;
use OMP::Cookie;
use OMP::Error;
use HTML::WWWTheme;

our $VERSION = (qw$ Revision: 1.2 $ )[1];

# Expiry time for cookies
our $EXPTIME = 10;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::CGI> object.

  $cgi = new OMP::CGI( CGI => $q );

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  my $c = {
	   Theme => undef,
	   CGI => undef,
	   Cookie => undef,
	   Title => 'OMP Feedback System',
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

  $theme = $c->theme;
  $c->theme( $theme);

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

Return the CGI object associated with the cookies.

  $cgi = $c->cgi;
  $c->cgi( $q );

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

Return the cookie object.  This is of class C<OMP::Cookie>.

  $cookie = $c->cookie;
  $c->cookie( $cookie );

=cut

sub cookie {
  my $self = shift;
  if (@_) {
    my $cookie = shift;

    croak "Incorrect type. Must be a OMP::Cookie object"
      unless UNIVERSAL::isa( $cookie, "OMP::Cookie");

    $self->{Cookie} = $cookie;
  }
  return $self->{Cookie};
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

=back

=head2 General Methods

=over 4

=item B<_sidebar_logout>

Put a logout link in the sidebar, and some other feedback links under
the title "Feedback Links"

  $cgi->_sidebar_logout;

=cut

sub _sidebar_logout {
  my $self = shift;
  my $theme = $self->theme;
  my $c = $self->cookie;
  my $q = $self->cgi;

  my %cookie = $c->getCookie;

  my $projectid = $cookie{projectid};
  ($projectid) or $projectid = $q->param('projectid');

  $theme->SetMoreLinksTitle("Project: $projectid");

  my @sidebarlinks = ("<a href='feedback.pl'>Feedback entries</a>",
		      "<a href='fbmsb.pl'>Program details</a>",
		      "<a href='fbcomment.pl'>Add comment</a>",
		      "<a href='msbhist.pl'>MSB History</a>",
		      "<br><font size=+1><a href='fblogout.pl'>Logout</a></font>");
  $theme->SetInfoLinks(\@sidebarlinks);
}

=item B<_sidebar_fault>

Put fault system links in the sidebar

  $cgi->_sidebar_fault;

=cut

sub _sidebar_fault {
  my $self = shift;
  my $theme = $self->theme;

  $theme->SetMoreLinksTitle("Fault System");

  my @sidebarlinks = ("<font size=+1><a href='filefault.pl'>File a fault</a>",
		      "<a href='queryfault.pl'>Query faults</a>",
		      "<a href='viewfault.pl'>View/Respond to a fault</a></font>",);

  $theme->SetInfoLinks(\@sidebarlinks);
}

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

    my @themefile = ("/JACpublic/JAC/software/omp/LookAndFeelConfig", "/jac_sw/omp/etc/LookAndFeelConfig", "/WWW/JACpublic/JAC/software/omp/LookAndFeelConfig");
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

=item B<_write_header>

Create the document header (and provide the cookie).  Cookie is optional.

  $cgi->_write_header([$style]);


Optional argument is style sheet tags to be embedded in the HTML header

=cut

sub _write_header {
  my $self = shift;
  my $style = shift;
  my $q = $self->cgi;
  my $c = $self->cookie;
  my $theme = $self->theme;

  # Print the header info
  if (defined $c) {
    print $q->header( -cookie => $c->cookie,
		      -expires => '-1d' );
  } else {
    print $q->header( -expires => '-1d' );
  }

  my $title = $self->html_title;

  $theme->SetHTMLStartString("<html><head><title>$title</title>$style<link rel='icon' href='http://www.jach.hawaii.edu/JACpublic/JAC/software/omp/favicon.ico'/></head>");

  $theme->SetSideBarTop("<a href='http://jach.hawaii.edu/'>Joint Astronomy Centre</a>");

  # These links will go under the 'JAC Divisions' heading
  my @links = ("<a HREF='/JACpublic/JCMT'>JCMT</a>",
	       "<a HREF='/JACpublic/UKIRT'>UKIRT</a>",
	       "<a HREF='/JACpublic/JAC/ets'>Engineering & Technical Services</a>",
	       "<a HREF='/JACpublic/JAC/cs'>Computing Services</a>",
	       "<a HREF='http://www.jach.hawaii.edu/JAClocal/admin'>Administration</a>",);

  $theme->SetSideBarMenuLinks(\@links);

  print $theme->StartHTML(),
        $theme->MakeHeader(),
	$theme->MakeTopBottomBar();

}

=item B<write_footer>

Create the footer of the HTML document.

  $cgi->_write_footer;

=cut

sub _write_footer {
  my $self = shift;
  my $q = $self->cgi;
  my $theme = $self->theme;


  print $theme->MakeTopBottomBar(),
        $theme->MakeFooter(),
	$theme->EndHTML();

}

=item B<_write_login>

Create the login form.

$cgi->_write_login;

=cut

sub _write_login {
  my $self = shift;
  my $q = $self->cgi;
  my $c = $self->cookie;

  $self->_write_header();

  print "<img src='http://www.jach.hawaii.edu/JACpublic/JAC/software/omp/banner.gif'><p><p>";
  print $q->h1('Login'),
    "Please enter the project ID and password. These are required for access to project information and data.";

  print "<table><tr valign='bottom'><td>";
  print $q->startform,

    # This hidden field contains the 'login_form' param that lets us know we've just come
    # from the login form, so we'll be sure to run the form_content callback and not
    # form_output.
        $q->hidden(-name=>'login_form',
		   -default=>1,),
        $q->br,
	"Project ID: </td><td colspan='2'>",
	$q->textfield(-name=>'projectid',
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

=item B<write_page>

Create the page with the login form if the project ID and password are
needed.  If the projectid and password have already been provided create
the form and its output using the code references provided to this method.

  $cgi->write_page( \&form_content, \&form_output );

The subroutines passed to this method should shift off the first
element of @_ as that is the C<CGI> query object.  The rest of the elements
should be dumped to a hash as they contain the cookie contents:

  sub form_output {
    my $query = shift;
    my %cookie = @_;
    ...
  }

=cut

sub write_page {
  my $self = shift;
  my ( $form_content, $form_output ) = @_;

  my $q = $self->cgi;
  # Check to see that they are defined...
  # Check that they are code refs
  foreach ($form_content, $form_output) {
    throw OMP::Error::BadArgs("Code reference not given")
      unless defined($_);

    my $type = ref($_);
    croak "Must be a code reference."
      unless $type eq 'CODE';
  }

  # First thing to do is read the cookie and store the object
  my $c = new OMP::Cookie( CGI => $q );
  $self->cookie( $c );

  my %cookie = $c->getCookie;

  # Retrieve the theme or create a new one
  $self->_make_theme;

  # See if we are reading a form or not

  if ($q->param) {
    # Does this form include a password field?
    if ($q->param('password')) {
      # Okay need to get user name and password and
      # set the cookie

      my $projectid = $q->param('projectid');
      my $password = $q->param('password');

      # Verifying the password here to decide whether or not we want to set the
      # cookie with it.
      my $verify = OMP::ProjServer->verifyPassword($projectid, $password);

      ($verify) and %cookie = (projectid=>$projectid, password=>$password) or
	throw OMP::Error::Authentication("Password or project ID are incorrect");

    } elsif (! exists $cookie{password} and !$q->url_param('urlprojid')) {
      # Else no password at all (even in the cookie) so put up log in form
      # Just put up the password form

      $self->_write_login;

      # Dont want to do any more so return immediately
      return;

    }

    if ($q->url_param('urlprojid')) {

      # The project ID is in the URL.  If the URL project ID doesn't
      # match the project ID in the cookie (or there is no cookie) set
      # the cookie with the URL project ID since the user just clicked
      # a link to get here.

      if ($q->url_param('urlprojid') ne $cookie{projectid}) {
	%cookie = (projectid=>$q->url_param('urlprojid'), password=>'***REMOVED***');
      }
    }

    # Set the cookie with a new expiry time (this occurs even if we
    # already have one. This allows for automatic expiry if noone
    # reloads the page
    $c->setCookie( $EXPTIME, %cookie );

    # Put a logout link on the sidebar
    $self->_sidebar_logout;

    # Print HTML header (including sidebar)
    $self->_write_header();

    # Now everything is ready for our output. Just call the
    # code ref with the cookie contents
    if ($q->param('login_form') or $q->param('show_content')) {
      # If there's a 'login_form' param then we know we just came from
      # the login form.  Also, if there is a 'show_content' param, call
      # the content code ref.

      $form_content->( $q, %cookie);


    } else {
      $form_output->( $q, %cookie);
    }

    # Write the footer
    $self->_write_footer();

  } else {
    # We are creating forms, not reading them.  Or we might just be
    # creating output.

    # If the cookie contains a password field just put up the
    # HTML content
    if (exists $cookie{password}) {

      # Set the cookie with a new expiry time (this occurs even if we
      # already have one. This allows for automatic expiry if noone
      # reloads the page
      $c->setCookie( $EXPTIME, %cookie );

      # Put a logout link on the sidebar
      $self->_sidebar_logout;

      # Write the header
      $self->_write_header();

      # Run the callback
      $form_content->( $q, %cookie );

      # Write the footer
      $self->_write_footer();

    } else {
      # Pop up a login box instead
      $self->_write_login();

    }

  }

}

=item B<write_page_noauth>

Creates the page but doesnt do a login.  This is for cgi scripts that call functions
which dont require a password and/or project ID.

  $cgi->write_page_noauth( \&form_content, \&form_output );

=cut

sub write_page_noauth {
  my $self = shift;
  my ($form_content, $form_output) = @_;

  my %cookie = $self->cookie;
  my $q = $self->cgi;

  $self->_make_theme;
  $self->_write_header();

  if ($q->param) {
    $form_output->($q, %cookie);
  } else {
    $form_content->($q, %cookie);
  }

  $self->_write_footer();
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

  my $c = new OMP::Cookie( CGI => $q );
  $self->cookie( $c );

  $c->flushCookie();

  $self->_make_theme;
  $self->_write_header();

  $content->($q);

  $self->_write_footer();
}

=item B<write_page_fault>

Creates a page for the fault system.  This system requires the use of URL parameters which
the other write_page functions do not allow.

  $cgi->write_page_fault( \&content, \&output );

In order for this to work a hidden field called B<show_output> must be embedded in the cgi form
for the B<&output> code reference to be called.

=cut

sub write_page_fault {
  my $self = shift;
  my ($form_content, $form_output) = @_;

  my %cookie = $self->cookie;
  my $q = $self->cgi;

  $self->_make_theme;

  $self->_sidebar_fault;

  my $style = "<style><!--
  body{font-family:arial,sans-serif}
  //--></style>";

  $self->_write_header($style);

  if ($q->param) {
    if ($q->param('show_output')) {
      $form_output->($q, %cookie);
    } else {
      $form_content->($q, %cookie);
    }
  } else {
    $form_content->($q, %cookie);
  }

  $self->_write_footer();
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;



