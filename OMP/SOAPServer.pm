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
use OMP::Constants qw/ :status /;
use OMP::General;

our $VERSION = (qw$Revision$)[1];


=head1 METHODS

=over 4

=item B<throwException>

Throw a SOAP exception using an C<OMP::Error> object.
If we are not running in SOAP environment (determined by
looking at HTTP_SOAPACTION encironment variable) we throw
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

  # Get the error number - defaulting to OMP__ERROR if required
  my $Enum = $E->value;
  $Enum = OMP__ERROR unless defined $Enum;

  OMP::General->log_message("Rethrowing SOAP exception: $Estring\n");

  # Throw the SOAP exception
  die SOAP::Fault->faultcode("$Ecode")
    ->faultstring("$Estring")
      # Rebless the error into a sanitized class and add code key
      ->faultdetail(bless {%$E, code => $Enum} => $Eclass)
	->faultactor('http://www.jach.hawaii.edu/JACpublic/software/OMP');

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
	     MSBMalformedQuery => 'Client.MSBMalformedQuery',
	     MSBMissing => 'Client.MSBMissing',
	     MSBMissingObserve => 'Client.MSBMissingObserve',
	     SpBadStructure => 'Client.SpBadStructure',
	     SpChangedOnDisk => 'Server.SpChangedOnDisk',
	     SpEmpty => 'Client.SpEmpty',
	     SpRetrieveFail => 'Server.SpRetrieveFail',
	     SpStoreFail => 'Server.SpStoreFail',
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

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

# Allow for a SOAP::Fault to be stringified so that it does
# the right thing even when we are not running this as a fault server

package SOAP::Fault;

use overload '""' => "stringify";

sub stringify {
  my $self = shift;
  my $errstr = $self->faultcode . ': ' . $self->faultstring;
  chomp($errstr);
  return $errstr ."\n";
}



1;

