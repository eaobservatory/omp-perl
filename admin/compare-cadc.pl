#!/local/perl/bin/perl

use strict;
use warnings;
use Data::Dumper;

use DBI;
use FindBin;
use Getopt::Long qw[ :config gnu_compat no_ignore_case no_debug ];
use List::Util qw[ max first ];
use MIME::Lite;
use Pod::Usage;

use lib "$FindBin::RealBin/..";
use OMP::Config;

$ENV{'SYBASE'} = qw[/local/progs/sybase];

BEGIN{ our $DEBUG = 0; }
our $DEBUG;

my @cadc_cf =
  qw[ /jac_sw/etc/jcmtmd-db.cfg
      /jac_sw/etc/jcmtmd-standby-db.cfg
    ];

my ( $help, %config, @addr, @cadc );

@config{qw[ jcmt omp ]} =
  qw[
      /jac_sw/etc/jcmt-db.cfg
      /jac_sw/etc/ompsite.cfg
    ];

GetOptions(
    'help'   => \$help,
    'debug+' => \$DEBUG,

    'omp=s'         => \$config{'omp'},
    'jcmt=s'        => \$config{'jcmt'},
    'cadc|jcmtmd=s@' => \@cadc,

    'mail=s' => \@addr,
  )
    or pod2usage( '-exitval' => 2, '-verbose' => 1 );

pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;

#pod2usage( '-exitval' => 2, '-verbose' => 1,
#            '-msg' => 'Need readable configuration files.'
#          )
#  if scalar values %config > scalar grep { -f $_ && -r _ } values %config;
@cadc_cf = @cadc if scalar @cadc;

my @jcmt =
  sort qw[ ACSIS SCUBA2 FILES COMMON ];

my @omp =
  sort
  qw[
      ompfaultassoc
      ompfaultbodypub
      ompfaultpub
      ompmsbdone
      ompproj
      ompprojuser
      ompuser
      ompobslog
      ompshiftlog
    ];

#  Tables are currently empty, at least on JAC side.
my @skip = sort qw[ ompfaultbodypub ompfaultpub ];

my $omp_cf = OMP::Config->new;

my $one_diff = 0;
for my $file ( @cadc_cf ) {

  $config{'jcmtmd'} = $file;

  my %stat =
    connect_and_get_db_stats( $omp_cf, \%config, \@jcmt, \@omp, @skip );

  my $diff = any_diff( \%stat, @skip );
  $one_diff++ if $diff;

  $omp_cf->configDatabase( $file );
  my $server = $omp_cf->getData( "database.server" );

  my $result =
    sprintf "%s\n==============\nAny difference: %s\n\nSkipped tables: %s\n\n%s",
      $server,
      $diff ? 'yes' : 'no',
      join( ', ', @skip),
      make_diff_status( max( map { length $_ } @jcmt, @omp ), %stat )
    ;

  if ( $DEBUG || ! scalar @addr ) {

    print $result;
    print "\n";
  }
  else {

    MIME::Lite->send("smtp", "mailhost", Timeout => 30);
    my $mail =
      MIME::Lite->new( 'From' => 'jcmtarch@jach.hawaii.edu',
                        'to'  => join( ', ', @addr ),
                        'Subject' =>
                          ( $diff ? 'Different count' : 'OK' ) . qq[ - $server replication],
                        'Data'    => $result,
                      );

    $mail->send or die "Error sending message: $!\n";
  }
}

exit $one_diff;

# Returns a hash with table as the keys, and hash references of database server
# name and row count as values.
#
# It accepts a hash reference of database names with configuration files as
# keys; an array reference of 'jcmt' database tables; an array reference
# of 'omp' database tables; and a combined list of tables to skip.
sub connect_and_get_db_stats {

  my ( $omp_cf, $config, $jcmt, $omp, @skip ) = @_;

  #  "jcmtmd" database, present at CADC, contains all of the tables.
  $omp_cf->configDatabase( $config->{'jcmtmd'} );

  my $jcmtmd_dbh = make_connection( $omp_cf );

  $omp_cf->configDatabase( $config->{'jcmt'} );

  my $jcmt_dbh = make_connection( $omp_cf );

  my %stat = get_table_stats( { 'cadc' => $jcmtmd_dbh, 'jac' => $jcmt_dbh },
                              $jcmt, @skip
                            );

  $DEBUG and warn "Disconnecting from SYB_JAC*.jcmt";
  $jcmt_dbh->disconnect;

  $omp_cf->configDatabase( $config->{'omp'} );

  my $omp_dbh = make_connection( $omp_cf );
  {
    my %tmp = get_table_stats( { 'cadc' => $jcmtmd_dbh, 'jac' => $omp_dbh },
                                $omp, @skip
                              );
    @stat{ keys %tmp } = values %tmp;
  }

  $DEBUG and warn "Disconnecting from SYB_JAC*.omp";
  $omp_dbh->disconnect;

  $DEBUG and warn "Disconnecting from CADC*.jcmtmd";
  $jcmtmd_dbh->disconnect;

  return %stat;
}

# Returns 1 if there is any difference in row count on two servers, else returns
# 0, given a hash reference with table as the keys, and hash references of
# database server name and row count as values.
sub any_diff {

  my ( $stats, @skip ) = @_;

  for my $table ( keys %{ $stats } )
  {
    next if scalar @skip && first { $table eq $_ } @skip;

    local $_ = $stats->{ $table };
    next unless defined;
    return 1 if 0 != $_->{ 'jac' } - $_->{ 'cadc' };
  }

  return 0;
}

# Returns a string listing the table rows & differences.
sub make_diff_status {

  my ( $max, %stat ) = @_;

  # 2: indent spaces.
  $max += 2;
  my $format = "%${max}s: %5d (%7d  %7d)\n";

  ( my $header = $format ) =~ tr/d/s/;
  my $text = sprintf $header, qw/ table diff JAC CADC /;
  $text .= ( '-' ) x length $text;
  $text .= "\n";

  for my $t  ( sort keys %stat )
  {
    local $_ = $stat{ $t };
    next unless defined;
    my $diff = $_->{ 'jac' } - $_->{ 'cadc' };
    $text .= sprintf $format, $t, $diff, $_->{ 'jac' }, $_->{ 'cadc' };
  }

  return $text;
}

# Returns a hash with table as the keys, and hash references of database server
# name and row count as values.
#
# It takes in a hash reference of server names as keys and database handles as
# values; array references of table to count the rows for; list of tables to
# skip.
sub get_table_stats {

  my ( $dbhs, $tables, @skip ) = @_;

  my %stat;
  for my $table ( @{ $tables } ) {

    $DEBUG and warn "Current table: $table";
    next if first { $table eq $_ } @skip;

    for my $server ( keys %{ $dbhs } )
    {
      $DEBUG and warn "Getting count from $server";
      $stat{ $table }->{ $server } = get_count( $dbhs->{ $server }, $table );
    }
  }
  return %stat;
}

# Actually do the work of getting row count.
sub get_count {

  my ( $dbh, $table ) = @_;

  local ( $!, $@ );

  defined $dbh
    or die_via_disconnect( undef, 'Database handle has become undefined.' );

  die_via_disconnect( undef, 'Need db handle & a table name' ) unless scalar @_ > 1;

  my $sql = qq[SELECT COUNT(*) FROM $table];

  my $count = $dbh->selectrow_arrayref( $sql )
    or die_via_disconnect( undef,
                            qq[Error occurred while getting count from table $table: ]
                            . _make_errtext( 'DBI ERROR'   => $DBI::errstr,
                                              'EVAL ERROR' => $@,
                                              'OS ERROR'   => $!,
                                            )
                          );

  return unless defined $count;
  return $count->[0];
}

sub _make_errtext {

  my ( %type ) = @_;

  return
    join "\n",
      map
      { defined $type{ $_ } && length $type{ $_ }
        ? sprintf( '(%s) %s', $_ => $type{ $_ } )
        : ()
      }
      keys %type;
}

{
  my %dbcache;

  # Given a OMP::Config object containing database connection data, returns a
  # database handle.
  sub make_connection {

    my ( $cf ) = @_;

    my ( $server, $db, $user, $pass ) =
      map
        { $cf->getData( "database.$_" ) }
        qw[ server  database  user  password ];

    die_via_disconnect( undef, "No database log in data found" )
      if grep { ! defined }  $server, $db, $user, $pass;

    my $connection = qq[${server}.${db}:${user}];

    $DEBUG and warn "Connecting to $connection";
    my $dbh =
      DBI->connect( "dbi:Sybase:server=$server;timeout=300" , $user, $pass
                    , { 'RaiseError' => 1
                      , 'PrintError' => 0
                      , 'AutoCommit' => 1
                      }
                  )
        or do { disconnect_all(); croak $DBI::errstr; };

    $dbcache{ $connection } = $dbh;

    for ( $dbh )
    {
      $_->{'syb_show_sql'} = 1 ;
      $_->{'syb_show_eed'} = 1 ;

      $_->do( "use $db" ) or die_via_disconnect( $_ );
    }

    return $dbh ;
  }

  sub disconnect_all {

    for my $con ( sort keys %dbcache ) {

      my $dbh = delete $dbcache{ $con };
      if ( defined $dbh ) {

        $DEBUG and warn 'Disconnecting from ', "$con", "\n";

        $dbh->disconnect()
          or warn 'Error during disconnect: ', $dbh->errstr(), "\n";
      }
    }

    return;
  }
}


sub die_via_disconnect {

  my ( $dbh, $text ) = @_;

  $text and warn $text, "\n";

  if ( defined $dbh ) {

    unless ( $text ) {

      my $err = $dbh->errstr();
      $err and warn $err, "\n";
    }

    $dbh->disconnect();
  }

  disconnect_all();
  exit 1;
}

=pod

=head1 NAME

compare-cadc.pl - Compare rows in tables at CADC and JAC

=head1 SYNOPSIS

Result is printed on standard output, debug output on standard error
...

  compare-cadc [-debug]

Send output via mail ...

  compare-cadc -mail 'somebody@example.org'

Specify database connection file ...

  compare-cadc -omp '/omp-db/ini/file'


=head1 DESCRIPTION

This program compares rows in a database at CADC and two databases at
JAC, as an estimate of status of replication.

=head2 OPTIONS

=over 4

=item B<help>

Show this message.

=item B<debug>

Run in debug mode.  Specify multiple times to increase output.

Output is printed on standard error.  No email is sent in this mode.

=item B<jcmt> file

Specify configuration file ("ini" file) for connection to "jcmt"
database (at JAC).

=item B<jcmtmd> | B<cadc> file

Specify configuration file ("ini" file) for connection to "jcmtmd"
database (at CADC).

=item B<mail> email-address

Send email to the given address instead of printing the result on
standard output.  Specify multiple time to send mail to multiple
addresses.

=item B<omp> file

Specify configuration file ("ini" file) for connection to "omp"
database (at JAC).

=back

=head1 AUTHOR

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2008 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place,Suite 330, Boston, MA  02111-1307,
USA

=cut

