package OMP::CommentServer;

=head1 NAME

OMP::CommentServer - Shiftlog comment information Server class

=head1 SYNOPSIS

  OMP::CommentServer->addShiftLog( $comment, $telescope );
  @comments = OMP::CommentServer->getShiftLog( $utdate, $telescope );

=head1 DESCRIPTION

This class provides the public server interface for the OMP shiftlog
information database server.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::Info::Comment;
use OMP::ShiftDB;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = (qw$REVISION: $)[1];

=head1 METHODS

=over 4

=item B<addShiftLog>

Add a shiftlog comment to the shiftlog database.

OMP::CommentServer->addShiftLog( $comment, $telescope );

The first passed parameter must be an C<OMP::Info::Obs> object,
and the second may be either an C<Astro::Telescope> object or
a string.

=cut

sub addShiftLog {
  my $class = shift;
  my $comment = shift;
  my $telescope = shift;

  my $E;

  try {
    my $sdb = new OMP::ShiftDB( DB => $class->dbConnection );
    $sdb->enterShiftLog( $comment, $telescope );
  } catch OMP::Error with {
    $E = shift;
  } otherwise {
    $E = shift;
  };

  $class->throwException( $E ) if defined $E;

  return 1;
}

=item B<getShiftLog>

Returns all comments for a given UT date.

  @comments = OMP::CommentServer->getShiftLog( $utdate, $telescope );

The first argument is a string of the form 'yyyymmdd'. The second
argument is optional and can be either an C<Astro::Telescope> object
or a string. The function returns an array of C<OMP::Info::Comment>
objects.

=cut

sub getShiftLog {
  my $class = shift;
  my $utdate = shift;
  my $telescope = shift;
  my @result;
  my $E;
  try {
    $utdate =~ /(\d{4})\-?(\d\d)\-?(\d\d)/;
    my $xml = "<ShiftQuery><date delta=\"1\">$1-$2-$3</date>";
    if(defined($telescope)) {
      $xml .= "<telescope>";
      if(UNIVERSAL::isa($telescope, "Astro::Telescope")) {
        $xml .= uc($telescope->name);
      } else {
        $xml .= uc($telescope);
      }
      $xml .= "</telescope>";
    }
    $xml .= "</ShiftQuery>";
    my $query = new OMP::ShiftQuery( XML => $xml );
    my $sdb = new OMP::ShiftDB( DB => $class->dbConnection );
    @result = $sdb->getShiftLogs( $query );

  } catch OMP::Error with {
    $E = shift;
  } otherwise {
    $E = shift;
  };

  $class->throwException( $E ) if defined $E;

  return @result;
}

=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Council.
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


=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=cut

1;
