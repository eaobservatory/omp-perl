#!/local/perl-5.6/bin/perl

=head1 NAME

forcedone - Fixup MSB done after the fact.

=head1 DESCRIPTION

This routine allows for 'manual' upload of MSB acceptance after the
observing. Science programmes are adjusted but time accounting is not
affected since in general this routine is run after the night report
has been verified.

Accepts information from standard input. Each line must have the
following format (comma separated):

  YYYY-MM-DDTHH:MM:SS,PROJECTID,CHECKSUM,ACCEPT,USERID,COMMENT

where the ACCEPT is a 1 or 0. 1 indicates the MSB was accepted
and 0 indicates that it is to be rejected. A hash mark indicates
a comment line.

This routine does not try to clear previous entries.

=cut

use 5.006;
use strict;
use warnings;

use OMP::MSBDB;
use OMP::MSBDoneDB;
use OMP::DBbackend;
use OMP::General;
use OMP::Info::Comment;
use OMP::UserServer;
use OMP::Constants ':done';

# Connect to database
my $msbdb = new OMP::MSBDB( DB => new OMP::DBbackend );
my $msbdone = new OMP::MSBDoneDB( DB => new OMP::DBbackend );

# Loop over info for modification
for my $line (<>) {
  next if $line !~ /\w/;
  next if $line =~ /^\s*\#/;

  my ($date,$proj,$checksum,$accept,$user,$comment) = split /,/, $line;

  $date = OMP::General->parse_date( $date );
  $user = OMP::UserServer->getUser( $user );

  my $status = ($accept ? OMP__DONE_DONE : OMP__DONE_REJECTED );

  my $c = new OMP::Info::Comment( text => $comment,
				  author => $user,
				  date=> $date,
				  status => $status,
				);

   print $date->datetime, ": $proj : $checksum : $user - $status\n";

  if ($accept) {
    # Force project ID
    $msbdb->projectid( $proj );

    # Mark it as done
    $msbdb->doneMSB( $checksum, $c, { adjusttime => 0 });
  } else {
    # Force project ID
    $msbdone->projectid( $proj );

    # Create reject text (this should be done with a proper rejectMSB method)
    my $rejtext = "MSB Rejected";
    $rejtext .= ": $comment" if defined $comment && $comment =~ /\w/;
    $c->text($rejtext);
    # Reject it
    $msbdone->addMSBcomment( $checksum, $c );
  }
}
