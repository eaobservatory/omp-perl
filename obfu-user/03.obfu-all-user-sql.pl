#!/local/perl/bin/perl

use strict; use warnings;
use 5.016;  # for fc() & say().

use Carp   qw[ carp croak confess ];
use Try::Tiny;

our $VERSION = '0.01';

select STDERR ; $| = 1;
select STDOUT ; $| = 1;

use DBI;
use File::Basename  qw[ fileparse ];
use File::Slurp     qw[ read_file ];

use Getopt::Long    qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;
use List::MoreUtils qw[ any all natatime ];
use List::Util      qw[ first min max sum ];

use JAC::ErrExit;
use JAC::Setup      qw[ omp jsa ];

use JSA::LogInitialize qw[ init_logger ];
use JSA::DB::Sybase qw[ connect_to_db ];

use OMP::User;

my $log = q[/home/agarwal/src/jac-git/omp-perl/obfu-user/obfu-user.log];
unlink( $log );
init_logger( $log );

my $cred =
  q[/jac_sw/etc/ompsite.cfg]
  #q[/jac_sw/etc/ompsite-dev.cfg]
  ;
my $dbquery_chunk = 1;

my ( $verbose , $help );
GetOptions( 'h|help|man' => \$help,
            'verbose=i'  => \$verbose
          )
  or pod2usage( '-exitval'  => 2 , '-verbose'  => 1 ) ;

$help and pod2usage( '-exitval' => 0 , '-verbose' => 3 );

my $file = $ARGV[0]
  or die sprintf "Give %s\n"
          , 'a userid list for whom to keep the data as is'
          ;

my %keep = parse_file( $file );

my $dbh_id = connect_to_db( $cred );
my $sth_id = $dbh_id->prepare( select_userid() );
$sth_id->execute();

my $dbh_up = connect_to_db( $cred );
my $update = update_sql();

my @sql;
#userid , name , alias
while ( my $row = $sth_id->fetchrow_hashref() )
{
  exists $keep{ $row->{'userid'} } and next;

  my @obfu = rot13( @{ $row }{qw[ userid name alias ]} )
    or next;

  @obfu[1,2] = quote_or_null( @obfu[1,2] );

  my $info = join qq[\n] ,
                sprintf( qq[print "-- %s\n"] , join ' ; ' , rot13( @obfu ) ) ,
                sprintf( qq[print "-- %s\n"] , join ' ; ' , @obfu )
                ;

  # For actaul SQL, to be able to use single quotes in strings.
  tr/[]/""/ for @obfu;

  push @sql , $info
              . sprintf $update ,
                  $obfu[0] ,
                  $row->{'userid'} ,
                  $obfu[1] ,
                  $obfu[2] ;
}

my $iter = natatime( $dbquery_chunk , @sql );
my $k = 1;
while( my @chunk = $iter->() )
{
  printf qq[-- %d-chunk: %d\n] , $dbquery_chunk , $k++ ;
  printf qq[begin tran\n%s\ngo\n\ncommit\ngo\n] ,
    join qq/\n/ , @chunk;
}

exit;

sub quote_or_null
{
  my @out;
  for ( @_ )
  {
    push @out ,
      defined $_ ?  q/[/ . $_ . q/]/ : q/null/ ;
  }
  return @out;
}

sub parse_file
{
  my ( $file ) = @_;

  my %keep;
  open my $fh , '<' , $file or die qq[Cannot open $file to read: $!\n];

  while ( my $line = <$fh> )
  {
    $line =~ /^\s*#/ || $line =~ /^\s*$/
      and next;

    for ( $line ) { s/^\s+//; s/\s+$//; }
    undef $keep{ uc $line };
  }

  close $fh or die qq[Could not close $file: $!\n];
  return %keep;
}

sub rot13
{
  my ( @in ) = @_;

  for ( @in )
  {
    defined $_ && fc( $_ ) ne fc( 'null' )
      and tr/A-Za-z/N-ZA-Mn-za-m/;
  }
  return @in;
}

sub select_userid
{
  return <<'_SELECT_';
    SELECT UPPER( userid ) AS userid , uname AS name , alias
    FROM ompuser
    WHERE obfuscated = 0 AND userid IS NOT NULL
    ORDER BY userid
_SELECT_

}

sub make_update
{
  my ( $dbh , @arg ) = @_;

  $verbose and show_mess( q[ ... ] . join q[, ] , @arg );

  $verbose > 1  and show_mess( q[Starting transaction ...] );
  $dbh->{'AutoCommit'} and $dbh->begin_work();

  my $sth = $dbh->prepare( update_sql() );

  my $any = 0;
  for my $arg ( @arg ) {

    my $affected = $sth->execute( $arg );
    if ( $dbh->err() ) {

      show_mess( qq[ERROR in UPDATE query execution for "$arg":\n], $dbh->errstr() );
      $dbh->rollback();
      return;
    }

    $any += $affected;
    ( $verbose > 1 && $affected ) and show_mess( qq[Update happened for: $arg] );
  }

  if ( $any > 0 ) {

    $verbose and show_mess( q[At least one row affected; comitting ...] );
    $dbh->commit();
    return;
  }

  $verbose and show_mess( q[No rows were affected; rolling back ...]);
  $dbh->rollback();
  return;
}

sub update_sql
{
  return <<'_UPDATE_';

    DECLARE @keep VARCHAR(32) , @remove VARCHAR(32)

    SELECT @keep = '%s' , @remove = '%s'

    UPDATE  omp..ompfaultbody     SET     author        = @keep WHERE author        = @remove
    UPDATE  omp..ompfaultbodypub  SET     author        = @keep WHERE author        = @remove
    UPDATE  omp..ompfeedback      SET     author        = @keep WHERE author        = @remove
    UPDATE  omp..ompshiftlog      SET     author        = @keep WHERE author        = @remove
    UPDATE  omp..ompobslog        SET     commentauthor = @keep WHERE commentauthor = @remove
    UPDATE  omp..ompproj          SET     pi            = @keep WHERE pi            = @remove
    UPDATE  omp..ompmsbdone       SET     userid        = @keep WHERE userid        = @remove

    UPDATE  omp..ompprojuser
      SET  userid = @keep , contactable = 0
    WHERE  userid = @remove

    UPDATE omp..ompuser
      SET obfuscated = 1 , email = null ,
          userid = @keep , uname = %s , alias = %s
    WHERE userid = @remove
_UPDATE_

}



__END__

=pod

=head1 NAME

  obfu-user.pl - Obfuscate user information.

=head1 SYNOPSIS

  obfu-user.pl list-in-file

=head1  DESCRIPTION

B<Currently it does only sanity check. obfuscation is coming soon.>

This program obfuscate OMP user data for users who are missing from the user
list in a file. Data for a user is lister per line; file format is ...

  UPDATEDOMPDATA <name> <address>

...where C<UPDATEDOMPDATA> is literal text; C<E<lt>nameE<gt>> is user name; and
C<E<lt>addressE<gt>> is email address.

I<Ideally, a list would be given with only the user ids for whom to obfuscate
the data.> That is not the current situation.

=head2  OPTIONS

NOTHING HELPFUL YET.

=over 2

=item *


=item *


=back

=head1 COPYRIGHT

Copyright (C) 2015 Science and Technology Facilities Council.
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

=cut


