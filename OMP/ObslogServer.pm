package OMP::ObslogServer;

=head1 NAME

OMP::ObslogServer - Obslog comment information Server class

=head1 SYNOPSIS

  OMP::ObslogServer->addObslogComment( $userid, $password, $obsid,
                                       $commentstatus, $commenttext );

=head1 DESCRIPTION

This class provides the public server interface for the OMP obslog
information database server.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::Info::Comment;
use OMP::ObslogDB;
use OMP::ArchiveDB;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = '0.01';

=head1 METHODS

=over 4

=item B<addObslogComment>

Add an obslog comment to the shiftlog database.

 OMP::ObslogServer->addObslogComment( $userid, $password, $telescope,
                                      $obsid, $commentstatus,
                                      $commenttext );

Telescope is needed to determine which database to use to locate
the obsid.

=cut

sub addObslogComment {
  my $class = shift;
  my $userid = shift;
  my $password = shift;
  my $telescope = shift;
  my $obsid = shift;
  my $commentstatus = shift;
  my $commenttext = shift;

  # Verify the password
  my $E;
  try {
    OMP::Password->verify_staff_password( $password );
  } catch OMP::Error with {
    $E = shift;
  } otherwise {
    $E = shift;
  };

  $class->throwException( $E ) if defined $E;

  # Because of history the obslog system needs to know the telescope
  # and potentially other bits of information concerning the observation.
  # This was done before obsid were common. The simplest thing is to
  # now query the observation database for this obsid. Note that older
  # databases and UKIRT don't have OBSID fields so this is not really
  # a good general solution
  try {

    my $adb = new OMP::ArchiveDB( DB => OMP::DBbackend::Archive->new() );
    my $obs = $adb->getObs( obsid => $obsid, telescope => $telescope, );

    my $odb = new OMP::ObslogDB( DB => $class->dbConnection );

    # Create a comment object
    my $comment = OMP::Info::Comment->new( text => $commenttext,
                                           status => $commentstatus,
                                         );
    $odb->addComment( $comment, $obs, $userid );
  } catch OMP::Error with {
    $E = shift;
  } otherwise {
    $E = shift;
  };

  $class->throwException( $E ) if defined $E;

  return 1;
}


=back

=head1 COPYRIGHT

Copyright (C) 2011 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
