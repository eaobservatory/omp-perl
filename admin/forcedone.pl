#!/local/perl-5.6/bin/perl

=head1 NAME

forcedone - Fixup MSB done after the fact.

=head1 DESCRIPTION

Reads the information from the DATA handle. This is clearly not
very extensible.

=cut

use 5.006;
use strict;
use warnings;

use OMP::MSBDB;
use OMP::DBbackend;
use OMP::General;
use OMP::Info::Comment;
use OMP::UserServer;

# Connect to database
my $msbdb = new OMP::MSBDB( DB => new OMP::DBbackend );

# Loop over info for modification
for my $line (<DATA>) {
  next if $line !~ /\w/;

  my ($date,$proj,$checksum,$user,$comment) = split /,/, $line;

  $date = OMP::General->parse_date( $date );
  $user = OMP::UserServer->getUser( $user );

  my $c = new OMP::Info::Comment( text => $comment,
				  author => $user,
				  date=> $date,
				);

  # Force project ID
  $msbdb->projectid( $proj );

  # Mark it as done
  $msbdb->doneMSB( $checksum, $c, { adjusttime => 0 });

}


__DATA__
2003-03-31T09:55,M03AN04,fb9cb2ff6b1b500b741a85cc80ff98ea,LUNDIN,
2003-03-31T08:00,M03AN04,8a3d436e01b8bb2afa095281148943bd,LUNDIN,
2003-03-31T15:45,M03AN12,00d593556c778ce124000fd04dffeeef,LUNDIN,
