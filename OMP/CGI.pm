package OMP::CGI;

=head1 NAME

OMP::CGI - Functions for the OMP Feedback pages

=head1 SYNOPSIS

use OMP::CGI(qw/:feedback/);

=head1 DESCRIPTION

This class provides functions for use with the OMP Feedback CGI scripts.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Cookie;
use HTML::WWWTheme;

our $VERSION = (qw$ Revision: 1.2 $ )[1];

# Expiry time for cookies
our $EXPTIME = 2;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::CGI> object.

  $c = new OMP::CGI( CGI => $q );

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
    croak "Incorrect type. Must be a HTML::WWWTheme object"
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

=item B<sideBar>

  sideBar();

=cut

sub sideBar {
  my $self = shift;
  my $cgi = shift;

  print "This is a sidebar.\n";
  return;
}

=item B<ompHeader>

  ompHeader();

=cut

sub ompHeader {
  my $self = shift;
  my $cgi = shift;
  # throw an error here if it isn't a cgi object.

  $cgi->header();
  return;
}

=item B<write_header>

Cookie is optional.

=cut

sub write_header {
  my $self = shift;
  my $q = $self->cgi;
  my $c = $self->cookie;

  # Retrieve the theme or create a new one
  my $theme = $self->theme;
  unless (defined $theme) {
    # Use the OMP theme and make some changes to it.
    $theme = new HTML::WWWTheme("/WWW/JACpublic/JAC/software/omp/LookAndFeelConfig");
    $self->theme($theme);
  }

  $theme->SetHTMLStartString("<html><head><title>OMP Feedback Tool</title></head>");
  $theme->SetSideBarTop("<a href='http://jach.hawaii.edu/'>Joint Astronomy Centre</a>");

  print $theme->StartHTML(),
    $theme->MakeHeader(),
      $theme->MakeTopBottomBar();

}

=item B<write_footer>

=cut

sub write_footer {
  my $self = shift;
  my $q = $self->cgi;
  my $theme = $self->theme;


  print $theme->MakeTopBottomBar(),
    $theme->MakeFooter(),
      $theme->EndHTML();

}

=item B<write_login>

=cut

sub write_login {
  my $self = shift;
  my $q = $self->cgi;
  my $c = $self->cookie;

  $self->write_header();

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

  $self->write_footer();
}

=item B<write_page>

  $cgi->write_page( \&form_content, \&form_output );

=cut

sub write_page {
  my $self = shift;
  my ( $form_content, $form_output ) = @_;

  my $q = $self->cgi;

  # Check to see that they are defined...
  # KYNAN Does this. Check that they are code refs

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

      $self->write_login;

      # Dont want to do any more so return immediately
      return;

    }

    # Set the cookie with a new expiry time (this occurs even if we
    # already have one. This allows for automatic expiry if noone
    # reloads the page
    $c->setCookie( $EXPTIME, %cookie );

    # Print HTML header (including sidebar)
    $self->write_header();

    # Now everything is ready for our output. Just call the
    # code ref with the cookie contents
    $form_output->( %cookie );

    # Write the footer
    $self->write_footer();

  } else {
    # We are creating forms, not reading them

    # If the cookie contains a password field just put up the 
    # HTML content
    if (exists $cookie{password}) {

      # Write the header
      $self->write_header();

      # Run the callback
      $form_content->( %cookie );

      # Write the footer
      $self->write_footer();

    } else {
      # Pop up a login box instead
      $self->write_login();

    }

  }

}


=back

=cut

1;



