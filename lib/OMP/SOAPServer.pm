package OMP::SOAPServer;

=head1 NAME

OMP::SOAPServer - base class for SOAP-based servers

=head1 SYNOPSIS

  package OMP::MyServer;
  use base OMP::SOAPServer;


=head1 DESCRIPTION

This is a base class for our OMP SOAP servers. This class allows
us to do server specific things in a single class without interfering
with the real work of the class. In order to change server we simply
inherit from another class.

Main reason to use this class is to generate exceptions in the
correct manner.

=cut

use strict;
use warnings;

# External dependencies
use SOAP::Lite;
use OMP::Auth;
use OMP::AuthDB;
use OMP::Config;
use OMP::Constants qw/ :status :logging /;
use OMP::Display;
use OMP::General;
use OMP::NetTools;

our $VERSION = '2.000';


=head1 METHODS

=over 4

=item B<get_verified_projectid>

Validate the given project ID, attempt to authenticate the user based on
the given credentials and check their authorization for the project.

  my ($projectid, $auth, @headers) = $class->get_verified_projectid(
      $provider, $username, $password, $rawprojectid);

The method may return additional SOAP headers which should be sent
to the client.

=cut

sub get_verified_projectid {
  my $class = shift;
  my $provider = shift;
  my $username = shift;
  my $password = shift;
  my $rawprojectid = shift;

  unless ((defined $provider) and (defined $username)
      and (defined $password) and (defined $rawprojectid)) {
    throw OMP::Error::BadArgs('Some of your identifying information is missing. ' .
      'You may need to update your OT to a newer version which supports user-based log in.');
  }

  # Authenticate user and check project authorization.
  my $projectid = OMP::General->extract_projectid($rawprojectid);
  throw OMP::Error::BadArgs('Project ID invalid.')
    unless defined $projectid;

  # Ensure project ID is upper case before attempting authorization.
  $projectid = uc $projectid;

  my $auth = OMP::Auth->log_in_userpass($provider, $username, $password);
  throw OMP::Error::Authentication($auth->message // 'Authentication failed.')
    unless defined $auth->user;

  # Issue token using "projects" attribute directly, because if there is no
  # project restriction, we do not wish to trigger fetching the user's projects.
  # This also has to be extracted before calling "has_project".
  my $rawproj = $auth->{'projects'};

  throw OMP::Error::Authentication('Permission denied.')
    unless $auth->is_staff or $auth->has_project($projectid);

  # If this was a new log in, generate an OMP token and return
  # via SOAP headers.
  my @headers;
  if ((exists $ENV{'HTTP_SOAPACTION'}) and ($provider ne 'omptoken')) {
    my (undef, $addr, undef) = OMP::NetTools->determine_host;
    my $adb = new OMP::AuthDB(DB => $class->dbConnection);
    my $token = $adb->issue_token($auth->user(), $addr, 'OMP::SOAPServer', $rawproj);
    push @headers, SOAP::Header->new(name => 'user', value => $auth->user()->userid());
    push @headers, SOAP::Header->new(name => 'token', value => $token);
  }

  return ($projectid, $auth, @headers);
}

=item B<throwException>

Throw a SOAP exception using an C<OMP::Error> object.
If we are not running in SOAP environment (determined by
looking at HTTP_SOAPACTION environment variable) we throw
the exception as is.

The faultcode is determined by looking at the class of the
exception. The class is split into its constituent parts and
the faultcode is obtained from a lookup table.

For example C<OMP::Error::Authentication> is thrown as a SOAP
C<Client.Authentication> fault.

The faultstring is determined directly from the string used
to throw the original exception (this will include the
line number and file name unless a newline is appended).

The faultdetail contains the contents of the error object itself
blessed into a new class where colons have been replaced by
dots. The error code is explcitly inserted into the hash with
key C<code> (the object already has it in C<-value>). A code
of OMP__ERROR is used if an error number was not supplied with the
initial throw.

The faultactor is specified as a simple URL to the OMP home page.
Have not figured out yet what people want in that.

=cut

sub throwException {
  my $class = shift;
  my $E = shift;

  $E->throw
    unless (exists $ENV{HTTP_SOAPACTION});

  # Get the fault class
  my $Eclass = ref($E);

  # Get the faultcode associated with this exception
  my $Ecode = $class->_get_faultcode( $Eclass );

  # Sanitized class must be without ::
  $Eclass =~ s/::/\./g;

  # Get the error message and remove trailing newlines
  my $Estring = "$E";
  chomp($Estring);

  # it seems that we may need to sanitize the message
  $Estring = OMP::Display::escape_entity( $Estring );

  # Get the error number - defaulting to OMP__ERROR if required
  # Make sure we can invoke the value method.
  my $Enum = OMP__ERROR;
  $Enum = $E->value if $E->can("value") && defined $E->value;

  OMP::General->log_message("Rethrowing SOAP exception: $Estring\n", OMP__LOG_ERROR);

  # Throw the SOAP exception
  die SOAP::Fault->faultcode("$Ecode")
    ->faultstring("$Estring")
      # Rebless the error into a sanitized class and add code key
      ->faultdetail(bless {%$E, code => $Enum} => $Eclass)
        ->faultactor(OMP::Config->getData('omp-url') . '/');

}

=item B<_get_faultcode>

Translate an exception class into a SOAP faultcode. Standard
SOAP codes are divided into Client and Server categories.
This method decides which category an exception belongs in
and returns the fully qualified fault code.

For example, C<OMP::Error::Authentication> is translated to
a fault code of C<Client.Authentication>.

The distinction between C<Client> and C<Server> faults is that
a C<Client> fault indicates that the message will not ever succeed
(maybe because the password is wrong) but a C<Server> fault may succeed
if the client tries it again (for example, the database is currently locked).

=cut

sub _get_faultcode {
  my $class = shift;
  my $Eclass = shift;

  # Split the exception into bits
  my @parts = split /::/, $Eclass;

  # Translation table
  my %lut = (
             Authentication => 'Client.Authentication',
             BadArgs => 'Client.BadArgs',
             DBConnection => 'Server.DBConnection',
             DBError => 'Server.DBError',
             DBLocked => 'Server.DBLocked',
             DBMalformedQuery => 'Client.DBMalformedQuery',
             FatalError => 'Server.UnknownError',
             InvalidUser => 'Client.InvalidUser',
             MSBBadConstraint => 'Client.MSBBadConstraint',
             MSBMalformedQuery => 'Client.MSBMalformedQuery',
             MSBMissing => 'Client.MSBMissing',
             MSBMissingObserve => 'Client.MSBMissingObserve',
             ProjectExists => 'Client.ProjectExists',
             SpBadStructure => 'Client.SpBadStructure',
             SpChangedOnDisk => 'Server.SpChangedOnDisk',
             SpEmpty => 'Client.SpEmpty',
             SpRetrieveFail => 'Server.SpRetrieveFail',
             SpStoreFail => 'Server.SpStoreFail',
             TranslateFail => 'Server.TranslateFail',
             UnknownProject => 'Client.UnknownProject',
            );

  my $faultcode;
  if (exists $lut{$parts[-1]}) {
    $faultcode = $lut{$parts[-1]};
  } else {
    $faultcode = "Server.UnknownError";
  }

  return $faultcode;
}


=back

=head1 SEE ALSO

OMP document OMP/SN/003.

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


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

# Allow for a SOAP::Fault to be stringified so that it does
# the right thing even when we are not running this as a fault server

package SOAP::Fault;

no warnings 'redefine';
use overload '""' => "stringify";

sub stringify {
  my $self = shift;
  my $errstr = $self->faultcode . ': ' . $self->faultstring;
  chomp($errstr);
  return $errstr ."\n";
}



1;

