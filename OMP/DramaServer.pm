package OMP::DramaServer;

=head1 NAME

OMP::DramaServer - SOAP server gateway to DRAMA land

=head1 SYNOPSIS

  $value = OMP::DramaServer->getParam( $task, $param );

=head1 DESCRIPTION

This class provides a SOAP server interface for interacting with
DRAMA without requiring DRAMA in the remote system.

All methods are class methods. No state is retained.

=cut

use strict;
use warnings;
use Carp;

# Drama infrastructure
use DRAMA qw/ pgetw /;

# OMP dependencies
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer /;

use vars qw/ $VERSION /;
$VERSION = sprintf("%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/);


=head1 METHODS

=over

=item B<getParams>

For the named task (which may include a host name specification if 
supplied as TASK@host), retrieve the value of the named parameter(s).

  $xml = OMP::DramaServer->getParam( $task, $param );
  $xml = OMP::DramaServer->getParam( $task, \@params );

Parameters are specified in an array (reference to array in perl land),
although a single parameter can be specified as a scalar.

Data returned as an XML string. For scalar parameters the 
XML will be of the form:

  <DRAMA TASK="task">
    <param>value</param>
    <param2>val2</param2>
  </DRAMA>

SDS (structured) parameters are not yet supported.

=cut

sub getParams {
  my $class = shift;
  my $task = shift;
  my $param = shift;

  my @params = ( ref $param ? @$param : $param );

  my $E;
  my $sds;
  try {
    my $errmsg = '';
    $sds = pgetw( $task, @params,{ -error => sub {
				     $errmsg = $_[1];
				   } } );
    throw OMP::Error::FatalError("DRAMA Error: $errmsg")
      unless defined $sds;
  } catch OMP::Error with {
    $E = shift;
  } otherwise {
    $E = shift;
  };

  $class->throwException( $E ) if defined $E;

  my %param;
  tie %param, "Sds::Tie",$sds;

  my $xml = "<?xml version=\"1.0\" encoding=\"US-ASCII\"?>\n";
  $xml .= "<DRAMA TASK=\"$task\">\n";

  for my $key (keys %param) {
    my $val = $param{$key};
    $xml .= "   <$key>";
    if (not ref $val) {
      $xml .= $val;
    } elsif (ref($val) eq 'ARRAY') {
      $xml .= join(" ",@$val);
    } else {
      throw OMP::Error::FatalError("Complex parameters not yet supported\n");
    }
    $xml .= "</$key>\n";
  }

  $xml .= "</DRAMA>\n";
  return $xml;
}

=item B<getEnviroParam>

Retrieve a single parameter value from the JCMT environment task.

  $pressure = OMP::DramaServer->getEnviroParam("Pressure");

=cut

sub getEnviroParam {
  my $class = shift;
  my $in = shift;

  my $task = 'ENVIRO@jaux';
  my $param = "STATE.$in";

  # Need to catch exceptions and rethrow using SOAP infrastructure
  my $E;
  my $sds;
  try {
    my $errmsg = '';
    $sds = pgetw( $task, $param,{ -error => sub {
				    $errmsg = $_[1];
				  } } );

    throw OMP::Error::FatalError("DRAMA Error: $errmsg")
      unless defined $sds;
  } catch OMP::Error with {
    $E = shift;
  } otherwise {
    $E = shift;
  };

  $class->throwException( $E ) if defined $E;

  my %param;
  tie %param, "Sds::Tie",$sds;

  return $param{$in};
}


=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=head1 SEE ALSO

L<DRAMA>, L<Jit>

=cut

1;
