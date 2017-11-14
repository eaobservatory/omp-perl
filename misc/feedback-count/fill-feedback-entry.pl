#!/local/perl/bin/perl

use strict; use warnings;
use 5.010;
use autodie         qw[ :2.13 ];
use Carp            qw[ carp croak confess ];
use Try::Tiny;

$| = 1;

our $VERSION = '0.01';

use Config::IniFiles  ;
use DateTime;
use DateTime::Duration;
use DBI             qw[ :sql_types ];
use File::Slurp     qw[ read_file ];
use List::Util      qw[ min max ];
use List::MoreUtils qw[ natatime ];

my $sql_xact_chunk = 200;

my $work_dir  = '/home/agarwal/src/jac-git/omp-perl/feedback-count' ;
my ( $cred  ) = map { join '/' , $work_dir , $_ }
                                qw[ .db-omp.cfg
                                  ];

my $proj_list = $ARGV[0]
  or die qq[Give a file with one project lister per line.\n];
my @proj =
  map
  {
    $_ =~ s/^\s+//; $_ =~ s/\s+$//;
    ( /^\s*$/ || /^\s*#/ ) ? () : $_
  }
  read_file( $proj_list )
    or die qq[No project list found in file "$proj_list".\n];

my $read_dbh  = connect_to_db( 'proddb' => $cred );
my $write_dbh = connect_to_db( 'proddb'  => $cred );

for my $proj ( @proj )
{
  warn qq[#  processing ${proj} ...\n];

  my $data_it = get_date( $read_dbh , $proj );
  # Each @data element is an array ref of commid, count to set, & date.
  while ( my @data = $data_it->() )
  {
    make_update( $write_dbh , \@data );
  }
}
$read_dbh->disconnect();
$write_dbh->disconnect();

exit;

{
  my ( $date_sth );
  sub get_date
  {
    my ( $dbh , $proj ) = @_;

    $date_sth ||= $dbh->prepare( select_date_sql() );

    my @data;
    my $count = 1;
    $date_sth->execute( $proj );
    while ( my ( $date , $comm ) = $date_sth->fetchrow_array() )
    {
      #  $comm datatype is NUMERIC and returned as string by DBD::Sybase, but
      #  used as integer. So convert it to that.
      push @data , { 'comm' => $comm , 'count' => $count++ , 'date' => $date };
    }
    my $iter = natatime( $sql_xact_chunk , @data );
    return $iter;
  }
}
sub select_date_sql
{
  return <<'_SELECT_';
    SELECT CONVERT( CHAR(19) , date , 23 ) AS date , commid
    FROM  omp..ompfeedback
    WHERE projectid in ( ? )
    ORDER BY date ASC , commid ASC
_SELECT_

}

{
  my ( $sql , $sql_format , $update_sth );
  sub make_update
  {
    my ( $dbh , $data ) = @_;

    $sql ||= update_entry_sql();

    my ( $comm , $count , $date );
    my ( $affected , $tried) =  ( 0 ) x2 ;

    $dbh->trace( 0);

    $dbh->{'AutoCommit'} and $dbh->begin_work();
    for my $i ( 0 .. $#{ $data } )
    {
      $tried++;
      ( $comm , $count , $date ) = map $data->[ $i ]{ $_ } , qw[ comm count date ];

      $update_sth = $dbh->prepare( sprintf $sql , $count );
      $affected += $update_sth->execute( $comm );

      if ( $dbh->err() )
      {
        $dbh->trace(0);
        carp( qq[** WTF?! ** For some reason DBI{RaiseError} did not cause exit!\n]
              . $dbh->errstr()
            );
        $dbh->rollback();
        return;
      }
    }
    $dbh->trace(0);
    warn qq[#  updates: $affected/$tried\n];
    if ( $affected > 0 )
    {
      warn qq[#  commiting...\n];
      $dbh->commit();
    }
    else
    {
      warn qq[#  rolling back...\n];
      $dbh->rollback();
    }
    return;
  }
}
sub update_entry_sql
{
  # Placeholder in SET clause for "usingined int" datatype column producess
  # error. Directly embedding the value is the only solution that I have found.
  return <<'_UPDATE_';
    UPDATE omp..ompfeedback
    SET entrynum = %d WHERE commid = ?
_UPDATE_

}

sub connect_to_db
{
  my ( $section , $cred ) = @_;

  my $cf = Config::IniFiles->new( '-file' => $cred );

  my ( $server , $db , $user , $pass ) =
    map $cf->val( $section , $_ ) , 'server' , 'database' , 'user' , 'password' ;

  my $dbh =
    DBI->connect( qq[dbi:Sybase:server=$server]
                  , $user
                  , $pass
                  , { 'RaiseError' => 1,
                      'PrintError' => 0,
                      'AutoCommit' => 0,
                    }
                )
      or Carp::croak( "Error making connection to database: " , $DBI::errstr );

  for ( $dbh )
  {
    $_->{'syb_show_sql'} = 1 ;
    $_->{'syb_show_eed'} = 1 ;

    $_->do( "use $db" ) or Carp::croak( $_->errstr );
  }

  return $dbh;
}

