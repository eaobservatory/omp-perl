package OMP::CommentServer;

=head1 NAME

OMP::CommentServer - Shiftlog comment information Server class

=head1 SYNOPSIS

  OMP::CommentServer->addShiftLog( $comment );
  @comments = OMP::CommentServer->getShiftLog( $utdate );

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

OMP::CommentServer->addShiftLog( $comment );

The passed parameter must be an C<OMP::Info::Obs> object.

=cut

sub addShiftLog {
  my $class = shift;
  my $comment = shift;

  my $E;

  try {
    my $sdb = new OMP::ShiftDB( DB => $class->dbConnection );
    $sdb->enterShiftLog( $comment );
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

  @comments = OMP::CommentServer->getShiftLog( $utdate );

The UT date is a string of the form 'yyyymmdd'. The function returns
an array of C<OMP::Info::Comment> objects.

=cut

sub getShiftLog {
  my $class = shift;
  my $utdate = shift;

  my @result;
  my $E;
  try {
    $utdate =~ /(\d{4})(\d\d)(\d\d)/;
    my $xml = "<ShiftQuery><date delta=\"1\">$1-$2-$3</date></ShiftQuery>";
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

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Council.
All Rights Reserved.

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=cut

1;
