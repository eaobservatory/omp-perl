package OMP::CGI;

=head1 NAME

OMP::CGI - Content for the OMP Feedback system CGI scripts

=head1 SYNOPSIS

use OMP::CGI;

$cgi = new OMP::CGI( CGI => $q );

$cgi->write_page(\&form_content, \&form_ouptut);

=head1 DESCRIPTION

This class provides the functions and content that are common to all of the
OMP feedback system CGI scripts, such as cookie management and look and feel.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use lib qw(/jac_sw/omp/msbserver);
use OMP::Cookie;
use OMP::Error;
use HTML::WWWTheme;

our $VERSION = (qw$ Revision: 1.2 $ )[1];

# Expiry time for cookies
our $EXPTIME = 2;

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

=back

=head2 General Methods

=over 4

=item B<_write_header>

Create the document header (and provide the cookie).  Cookie is optional.

  $cgi->_write_header;

=cut

sub _write_header {
  my $self = shift;
  my $q = $self->cgi;
  my $c = $self->cookie;

  # Print the header info
  if (defined $c) {
    print $q->header( -cookie => $c->cookie)
  } else {
    print $q->header();
  }


  # Retrieve the theme or create a new one
  my $theme = $self->theme;
  unless (defined $theme) {
    # Use the OMP theme and make some changes to it.
    $theme = new HTML::WWWTheme("/WWW/JACpublic/JAC/software/omp/LookAndFeelConfig");
    croak "Unable to instantiate HTML::WWWTheme object" unless $theme;
    $self->theme($theme);
  }

  $theme->SetHTMLStartString("<html><head><title>OMP Feedback Tool</title></head>");
  $theme->SetSideBarTop("<a href='http://jach.hawaii.edu/'>Joint Astronomy Centre</a>");

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

  print $q->h1('Login'),
    "Please enter enter the project ID and password. These are required for access to the feedback system.";

  print "<table><tr valign='bottom'><td>";
  print $q->startform,
        $q->br,
	"Project ID: </td><td colspan='2'>",
	$q->textfield(-name=>'projectid',
		      -size=>10,
		      -maxlength=>15),
	$q->br,
	"</td><tr><td>Password: </td><td>",
	$q->password_field(-name=>'password',
			   -size=>10,
			   -maxlength=>15),
	"</td><td>",
	$q->submit("Submit"),
	$q->endform;
  print "</td></table>";

  $self->_write_footer();
}

=item B<write_page>

Create the page with the login form if the projectid and password are
needed.  If the projectid and password have already been provided create
the form and its output using the code references provided to this method.

  $cgi->write_page( \&form_content, \&form_output );

Currently if the page does not contain a form the &form_content code
reference should be given twice, and the &form_output should not be given
at all.

=cut

sub write_page {
  my $self = shift;
  my ( $form_content, $form_output ) = @_;

  my $q = $self->cgi;
  # Check to see that they are defined...
#  throw OMP::Error::BadArgs("Code reference not given")
#    unless defined($form_content);
#  throw OMP::Error::BadArgs("Code reference not given")
#    unless defined($form_output);

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

  # See if we are reading a form or not
  if ($q->param) {

    # Does this form include a password field?
    if ($q->param('password')) {
      # Okay need to get user name and password and
      # set the cookie
      my $projectid = $q->param('projectid');
      my $password = $q->param('password');
      %cookie = (projectid=>$projectid, password=>$password);

    } elsif (! exists $cookie{password}) {
      # Else no password at all (even in the cookie) so put up log in form
      # Just put up the password form

      $self->_write_login;

      # Dont want to do any more so return immediately
      return;

    }

    # Set the cookie with a new expiry time (this occurs even if we
    # already have one. This allows for automatic expiry if noone
    # reloads the page
    $c->setCookie( $EXPTIME, %cookie );

    # Print HTML header (including sidebar)
    $self->_write_header();

    # Now everything is ready for our output. Just call the
    # code ref with the cookie contents
    $form_output->( %cookie );

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

      # Write the header
      $self->_write_header();

      # Run the callback
      $form_content->( %cookie );

      # Write the footer
      $self->_write_footer();

    } else {
      # Pop up a login box instead
      $self->_write_login();

    }

  }

}


=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;



