package OMP::CGI;

=head1 NAME

OMP::CGI - Content and functions for the MOP Feedback system CGI scripts

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

use OMP::Config;
use OMP::ProjServer;
use OMP::Cookie;
use OMP::Error qw(:try);
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultServer;
use OMP::CGIFault;
use OMP::General;
use OMP::UserServer;

use HTML::WWWTheme;

our $VERSION = (qw$ Revision: 1.2 $ )[1];

# Expiry time for cookies
our $EXPTIME = 10;

# Stylesheet
our $STYLE = "<style><!--
               body{font-family:arial,sans-serif}
               div.black a:link, div.black a:visited {
                 color: #000;
                 font-style: italic;
                 text-decoration: underline;
	       }
               b.white, b.white a:link, b.white a:visited {
                 color: #fff;
                 font-style: normal;
                 text-decoration: none;
               }
               div.footer, div.footer a:link, div.footer a:visited {
                 font-size: 11pt;
                 color: #ffffff;
               }
               HR {
                 height : 1;
                 color  : #babadd;
               }
               A {
                 font-family:arial,sans-serif;
               }
               //--></style>";


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
	   PublicURL => 'http://omp.jach.hawaii.edu/cgi-bin',
	   PrivateURL => 'http://omp-private.jach.hawaii.edu/cgi-bin',
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

Returns an array reference containing objects of class C<OMP::Cookie>.  If called with a cookie object as an argument the object is stored with the rest
of the cookies.  When called with an array reference all cookies are
replaced.

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
      for (@$cookie) {
	croak "Incorrect type. Must be a OMP::Cookie object"
	  unless UNIVERSAL::isa( $cookie, "OMP::Cookie");
      }

      @cookies = @$cookie;

    } else {
      # Single cookie.  Place it in our cookie array.
      croak "Incorrect type. Must be a OMP::Cookie object"
	unless UNIVERSAL::isa( $cookie, "OMP::Cookie");

      ($self->{Cookie}) and @cookies = @{$self->{Cookie}};
      push(@cookies, $cookie);
    }

    # Get rid of duplicate cookies
    my %no_dupes = map {$_->name, $_} @cookies;
    @cookies = map {$_} values %no_dupes;
    $self->{Cookie} = \@cookies;

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

=back

=head2 General Methods

=over 4

=item B<_sidebar_logout>

Put a logout link in the sidebar, and some other feedback links under
the title "Feedback Links"

  $cgi->_sidebar_logout(%cookie);

=cut

sub _sidebar_logout {
  my $self = shift;
  my $theme = $self->theme;
  my %cookie = @_;
  my $q = $self->cgi;

  my $projectid = $q->url_param('urlprojid');
  ($projectid) or $projectid = $cookie{projectid};

  $theme->SetMoreLinksTitle("Project: $projectid");

  my @sidebarlinks = ("<a href='projecthome.pl'>$cookie{projectid} Project home</a>",
		      "<a href='feedback.pl'>Feedback entries</a>",
		      "<a href='fbmsb.pl'>Program details</a>",
		      "<a href='fbcomment.pl'>Add comment</a>",
		      "<a href='msbhist.pl'>MSB History</a>",
		      "<a href='http://omp.jach.hawaii.edu/'>OMP home</a>",);

  # If there are any faults associated with this project put a link up to the
  # fault system and display the number of faults.
  my $faultdb = new OMP::FaultDB( DB => OMP::DBServer->dbConnection, );
  my @faults = $faultdb->getAssociations(lc($projectid), 1);
  push (@sidebarlinks, "<a href=fbfault.pl>Faults</a>&nbsp;&nbsp;(" . scalar(@faults) . ")")
    if ($faults[0]);

  push (@sidebarlinks, "<br><font size=+1><a href='fblogout.pl'>Logout</a></font>");
  $theme->SetInfoLinks(\@sidebarlinks);
}

=item B<_sidebar_fault>

Put fault system links in the sidebar.

  $cgi->_sidebar_fault($category);

Optional argument is a valid fault category.  If the category isnt specified put up a
list of links to the available categories.

=cut

sub _sidebar_fault {
  my $self = shift;
  my $cat = shift;
  my $theme = $self->theme;

  my $title = (defined $cat ? "$cat Faults" : "Select a fault system");
  $theme->SetMoreLinksTitle($title);

  my @sidebarlinks = ("<a href='queryfault.pl?cat=csg'>CSG Faults</a>",
		      "<a href='queryfault.pl?cat=omp'>OMP Faults</a>",
		      "<br><a href='http://omp.jach.hawaii.edu/'>OMP home</a></font>",);
  if (defined $cat) {
    unshift (@sidebarlinks, "<a href='filefault.pl?cat=$cat'>File a fault</a>",
	                    "<a href='queryfault.pl?cat=$cat'>View faults</a><br><br>",);
  }

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

    my @themefile = ("/WWW/omp/LookAndFeelConfig",
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

=item B<_write_header>

Create the document header (and provide the cookie).  Cookie is optional.

  $cgi->_write_header([$style]);


Optional argument is style sheet tags to be embedded in the HTML header

=cut

sub _write_header {
  my $self = shift;
  my $style = shift;
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

  if (@$cookie[0]) {
    print $q->header( -cookie => $cookie,
		      -expires => '-1d' );
  } else {
    print $q->header( -expires => '-1d' );
  }

  my $title = $self->html_title;

  $theme->SetHTMLStartString("<html><head><title>$title</title>$style<link rel='icon' href='http://www.jach.hawaii.edu/JACpublic/JAC/software/omp/favicon.ico'/></head>");

  $theme->SetSideBarTop("<a href='http://www.jach.hawaii.edu/'>Joint Astronomy Centre</a>");

  # These links will go under the 'JAC Divisions' heading
  my @links = ("<a HREF='http://www.jach.hawaii.edu/JACpublic/JCMT'>JCMT</a>",
	       "<a HREF='http://www.jach.hawaii.edu/JACpublic/UKIRT'>UKIRT</a>",
	       "<a HREF='http://www.jach.hawaii.edu/JACpublic/JAC/ets'>Engineering & Technical Services</a>",
	       "<a HREF='http://www.jach.hawaii.edu/JACpublic/JAC/cs'>Computing Services</a>",
	       "<a HREF='http://www.jach.hawaii.edu/JAClocal/admin'>Administration</a>",);

  # Get the location of blank.gif
  my $blankgif = OMP::Config->getData('blankgif');
  $theme->SetSideBarMenuLinks(\@links);
  $theme->SetBlankGif($blankgif);

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
        "<div class='footer'>This system provided by the <a href='http://www.jach.hawaii.edu/JAC/software'>Joint Astronomy Centre Software Group</a></div>",
	$theme->EndHTML();

}

=item B<_write_login>

Create the login form.

$cgi->_write_login($projectid);

Optional parameter is a project ID to appear as the default in the project ID text box.

=cut

sub _write_login {
  my $self = shift;
  my $projectid = shift;
  my $q = $self->cgi;
  my $c = $self->cookie;

  $self->_write_header($STYLE);

  print "<img src='http://www.jach.hawaii.edu/JACpublic/JAC/software/omp/banner.gif'><p><p>";
  print $q->h1('Login');
  
  if ($projectid) {
    print "Please enter the password required for access to project information and data.";
  } else {
    print "Please enter the project ID and password. These are required for access to project information and data.";
  }

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

=item B<_write_login_fault>

Create the login form.

$cgi->_write_login_fault(%args);

Optional paramter is a hash whos values indicate which fields (represtented by the keys) were incorrect.  Valid keys are B<password>.  A true value indicates that the field was incorrect.

=cut

sub _write_login_fault {
  my $self = shift;
  my %args = @_;
  my $q = $self->cgi;

  $self->_write_header($STYLE);

  print $q->h1('Fault System Login');
  # If the password was incorrect tell them so
  ($args{password}) and print "<b>The password you provided was incorrect.</b><br>";

  print "If you are accessing the fault system from outside the JAC network you must provide the staff password in order to gain access.";

  print "<table><tr valign='bottom'>";
  print $q->startform,

    $q->hidden(-name=>'login_form',
	       -default=>1,),
	$q->hidden(-name=>'show_content',
		   -default=>1),
        $q->br,
	"<td>Password: </td><td>",
	$q->password_field(-name=>'login_password',
			   -size=>17,
			   -maxlength=>30),
	"</td><tr><td colspan=2 align=right>",
	$q->submit("Submit"),
	$q->endform;
  print "</td></table>";

  $self->_write_footer();
}


=item B<_write_staff_login>

Create a login page that takes an OMP user id and staff password.

  $self->_write_staff_login();

=cut

sub _write_staff_login {
  my $self = shift;

  my $q = $self->cgi;

  $self->_write_header($STYLE);

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

=item B<_write_staff_login>

Create a login page that takes an OMP user id and administrator password.

  $self->_write_admin_login();

=cut

sub _write_admin_login {
  my $self = shift;

  my $q = $self->cgi;

  $self->_write_header($STYLE);

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

  # If a 'user' field has been filled in store that value in the cookie
  if ($q->param('user')) {
    $cookie{user} = $q->param('user');
  }

  # Retrieve the theme or create a new one
  $self->_make_theme;

  # Store the password and project id for verification
  if ($q->param('login_form')) {
    $cookie{projectid} = $q->param('projectid');
    $cookie{password} = $q->param('password');
  }

  $cookie{projectid} = $q->url_param('urlprojid')
    if ($q->url_param('urlprojid'));

  # Check to see if any login information has been provided. If not then
  # put up a login page.  If there is login information verify it and put
  # up a login page if it is incorrect.
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

  # Set the cookie with a new expiry time (this occurs even if we
  # already have one. This allows for automatic expiry if noone
  # reloads the page
  $c->setCookie( $EXPTIME, %cookie );

  # Put a logout link on the sidebar
  $self->_sidebar_logout(%cookie);

  # Print HTML header (including sidebar)
  $self->_write_header($STYLE);

  # Now everything is ready for our output. Just call the
  # code ref with the cookie contents

  # See if we should show content (display forms)
  if ($q->param('show_content') or $q->url_param('content')) {
    $form_content->($q, %cookie);
  } elsif ($q->param('show_output') or $q->url_param('output')) {
    $form_output->($q, %cookie);
  } else {
    $form_content->($q, %cookie);
  }

  # Write the footer
  $self->_write_footer();

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
  $self->_write_header($STYLE);

  if ($q->param) {
    $form_output->($q, %cookie);
  } else {
    $form_content->($q, %cookie);
  }

  $self->_write_footer();
}

=item B<write_page_staff>

Creates the page and does a staff login if necessary.  Also checks the username and password for authenticity each time a page is displayed.

  $cgi->write_page_staff( \&form_content, \&form_output );

=cut

sub write_page_staff {
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
    $verifypass = OMP::General->verify_staff_password($cookie{password});
  }

  $self->_make_theme;

  if ($verifyuser and $verifypass) {
    # The user ID and password have been verified.  Continue as normal.
    $c->setCookie( $EXPTIME, %cookie );

    $self->_write_header($STYLE);

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
	$self->_write_staff_login();
      }

    } else {

      # We haven't been to the login page yet so let's go there
      $self->_write_staff_login;
    }
  }

}

=item B<write_page_admin>

Like write_page_staff but takes the admin password instead.

  $cgi->write_page_admin( \&form_content, \&form_output );

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
    $verifypass = OMP::General->verify_administrator_password($cookie{password});
  }

  $self->_make_theme;

  if ($verifyuser and $verifypass) {
    # The user ID and password have been verified.  Continue as normal.
    $c->setCookie( $EXPTIME, %cookie );

    $self->_write_header($STYLE);

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
  $self->_write_header($STYLE);

  $content->($q);

  $self->_write_footer();
}

=item B<write_page_fault>

Creates a page for the fault system.  Authenticates only when a user attempts to connect
from outside the JAC network.  This  function is becoming more and more like write_page.

  $cgi->write_page_fault( \&content, \&output );

In order for params to be passed in the URL a hidden field called B<show_output> must 
be embedded in the cgi form being submitted for the B<&output> code reference to be called.

=cut

sub write_page_fault {
  my $self = shift;
  my ($form_content, $form_output) = @_;

  my $q = $self->cgi;

  my $c = new OMP::Cookie( CGI => $q, Name => "OMPFAULT" );
  $self->cookie( $c );

  my %cookie = $c->getCookie;

  $self->_make_theme;

  if ($q->param('user')) {
    $cookie{user} = $q->param('user');
  }

  if ($q->url_param('cat')) {
    my %categories = map {uc($_), $_} OMP::Fault->faultCategories;
    my $cat = uc($q->url_param('cat'));
    (defined $categories{$cat}) and $cookie{category} = $cat;
  }

  # If there is a fault ID in the URL get the fault and set the 
  # cookie category to whatever category the fault is
  my $fault;
  if ($q->url_param('id')) {
    # Display an error if we're unable to retrieve the fault.
    # We do this here since this class sets up the fault viewing
    # environment and nothing higher up will work anyway if we
    # can't retrieve the fault
    my $faultid = $q->url_param('id');
    my $E;
    try {
      $fault = OMP::FaultServer->getFault($faultid);
    } otherwise {
      $E = shift;
      print "Unable to retrieve fault $faultid [$E]";
    };
  }

  $cookie{category} = $fault->category
    if ($fault);

  if (defined $cookie{category}) {
    $self->_sidebar_fault($cookie{category});
  } else {
    $self->_sidebar_fault;
  }

  $c->setCookie( $EXPTIME, %cookie);

  $self->_write_header($STYLE);

  if (!$cookie{category}) {

    my $publicurl = $self->public_url;
    my $privateurl = $self->private_url;

    # Create a page body with some links to fault categories
    print $q->h2("You may search for and file faults in the following categories:");
    print "<ul>";
    print "<h3><li><a href='$publicurl/queryfault.pl?cat=CSG'>CSG Faults</a> for faults relating to JAC computer services</h3>";
    print "<h3><li><a href='$publicurl/queryfault.pl?cat=OMP'>OMP Faults</a> for faults relating to the Observation Management Project</h3>";
    print "</ul>";
    
    $self->_write_footer();
    return;
  }

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

=item B<write_page_fault_auth>

Same as write_page_fault described elsewhere in this document, but
with authentication.

  $cgi->write_page_fault_auth( \&content, \&output );

=cut

sub write_page_fault_auth {
  my $self = shift;
  my ($form_content, $form_output) = @_;

  my $q = $self->cgi;

  # Attempt to get the password cookie
  my $p = new OMP::Cookie( CGI => $q, Name => "OMPFAULTAUTH" );
  my %auth = $p->getCookie;


  # Didn't get it from the cookie, try getting it from the login form
  (! $auth{password}) and $auth{password} = $q->param('login_password');

  # Verify the password
  if ($auth{password}) {
    my $verify = OMP::General->verify_staff_password($auth{password}, 1);

    # Password fails, put up login form explaining that password
    # was incorrect
    if (! $verify) {
      $self->_write_login_fault(password => 1);
      return;
    }
  } else {

    # Still wasn't able to get the password; put up the login form
    $self->_write_login_fault;
    return;
  }

  # Password authenticates so store the password to the auth cookie and
  # write the fault page
  $p->setCookie('+24h', %auth);

  # Add the auth cookie to our cookies
  $self->cookie($p);


  $self->write_page_fault($form_content, $form_output);
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



