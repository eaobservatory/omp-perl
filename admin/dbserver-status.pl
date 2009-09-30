#!/local/perl/bin/perl

$ENV{'LC_ALL'} = $ENV{'LANG'} = 'C';
$ENV{'SYBASE'} = qw[/local/progs/sybase];

use strict; use warnings;

use Carp qw[ carp cluck ];
use DBI;
use FindBin;
use Getopt::Long qw[ :config gnu_compat no_ignore_case no_debug ];
use List::Util qw[ first ];
use MIME::Lite;
use Pod::Usage;

use lib "$FindBin::RealBin/..";
use OMP::Config;

# Check servers both at JAC & CADC by default.
my ( $cadc, $jac ) = ( 1, 1);
my ( $help, $short, $err_only, @addr );
GetOptions(
    'help'   => \$help,
    'e|error' => \$err_only,
    's|short' => \$short,
    'm|mail=s' => \@addr,
    'cadc!' => \$cadc,
    'jac!' => \$jac,
  )
    or pod2usage( '-exitval' => 2, '-verbose' => 1 );

pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;

my %jac =
  ( 'db-server' => [ qw[ SYB_JAC SYB_JAC2 ] ] ,
    'db' => [ sort qw[ jcmt jcmt_tms ukirt omp ] ] ,
    'config' =>
        { 'file' => '/jac_sw/etc/ompsite.cfg' ,
          'section' => 'hdr_database' ,
        } ,
  );

my %cadc =
  ( 'db-server' => [ qw[ CADC_MAS CADC_STANDBY ] ] ,
    'db' => [ qw[ jcmtmd ] ] ,
    'config' =>
        { 'file' => '/jac_sw/etc/jcmtmd-db.cfg' ,
          'section' => 'database' ,
        } ,
  );

$jac = format_server_status( $err_only, check_server( %jac ) )
 if $jac;

$cadc = format_server_status( $err_only, check_server( %cadc ) )
  if $cadc;

my $title = make_title( $err_only, $jac, $cadc );

my $report =
  $short
  ? ''
  : join "\n",
      ( $jac ? $jac : () ),
      ( $cadc ? $cadc : () )
  ;

if ( ! scalar @addr ) {

  printf "%s\n", $title if $title;
  print $report if $report;

}
elsif ( $title || $report ) {

  MIME::Lite->send("smtp", "mailhost", Timeout => 30);
  my $mail =
    MIME::Lite->new( 'From' => 'jcmtarch@jach.hawaii.edu',
                      'to'  => join( ', ', @addr ),
                      'Subject' => $title,
                      'Data'    => $report,
                    );

  $mail->send or die "Error sending message: $!\n";
}

# Given a hash of server names as keys & array references of status messages as
# values, returns a formatted string as ...
#
#   SERVER_NAME
#       OK connected
#       OK database is up
#       ERR could not run "use database": ...
#
sub format_server_status {

  my ( $err_only, $status ) = @_;

  my $msg = '';
  for my $server ( sort keys %{ $status } ) {

    my $tmp = format_db_status( $err_only, $status->{ $server } )
      or next;

    $msg .= sprintf "%s\n%s\n", $server, $tmp;
  }

  return $msg;
}

BEGIN {

  my $err_re = qr[^ \s* ERR \b]mix;

  # Given an array reference of status strings, returns a joined string, each
  # line is prefixed with two spaces.
  sub format_db_status {

    my ( $err_only, $status ) = @_;

    return unless scalar @{ $status };

    my $prefix = ' ' x 2;
    my $joiner = qq[\n${prefix}];

    return $prefix . join $joiner, @{ $status }
      unless $err_only;

    my @err;
    for ( @{ $status } ) {

      push @err, $_ if /$err_re/;
    }

    return unless scalar @err;

    return $prefix . join $joiner, @err;
  }

  sub make_title {

    my ( $err_only, $jac, $cadc ) = @_;

    if ( ! $jac && ! $cadc ) {

      return if $err_only;

      return '(mu) Received no status messages';
    }

    # Using "first" directly as the condition results in "Useless use of private
    # variable in void context".
    my $err =
      first { /$err_re/ }
        map { defined $_ ? $_ : () } ( $jac, $cadc );

    return
      $err
      ? 'Problem - Server, database status'
      : 'OK Server, database status'
      ;
  }
}

# Given a hash with server names, database names, log-in data, checks if servers
# are serving & databases are available.  Returns a list of strings prefixed
# with "OK" if a server or a database is up. Else, returned strings are
# prefixed with "ERR" with actual error text where possible.
sub check_server {

  my ( %place ) = @_;

  my ( $file, $section ) = extract_config( \%place );

  my $cf = OMP::Config->new;
  $cf->configDatabase( $file );

  my $cadc = qr{CADC};
  my $jac = qr{JAC};

  my %out;
  SERVER:
  for my $server ( @{ $place{'db-server'} } ) {

    unless ( $server =~ $cadc || $server =~ $jac ) {

      $out{ $server } = [ qq[ERR UNKNOWN SERVER: $server] ];
      next SERVER;
    }

    my $dbh;
    eval { $dbh = make_connection( $cf, $section, $server ) };
    if ( $@ ) {

      push @{ $out{ $server } }, qq[ERR could not connect to $server: $@];
      next SERVER;
    }

    my @server;
    push @server , 'OK connected';

    push @server, check_db_use( $dbh, $place{'db'} );

    if ( $server =~ $jac ) {

      push @server, check_db_repagent( $dbh, $place{'db'} );
    }

    $dbh->disconnect;

    $out{ $server } = [ @server ];
  }

  return \%out;
}

# Given a hash reference, returns a list with values of "file" & "section".
sub extract_config {

  my ( $hash ) = @_;

  return
    map { $hash->{'config'}->{ $_ } } qw[ file section ];
}

# Given a database handle and an array reference of database names, checks if a
# database is up.  Returns a list of messages prefixed with "OK" when database
# is available. Else, returns the list of string(s) are prefixed with "ERR" and
# the actual database error text.
sub check_db_use {

  my ( $dbh, $databases ) = @_;

  my @msg;
  for my $db ( @{ $databases } ) {

    eval{ $dbh->do( qq[use $db] ) };
    if ( $@ ) {

      push @msg, qq[ERR could not run 'use $db': $@];
      next;
    }
    push @msg, qq[OK $db is up];
  }

  return @msg;
}

# Given a database handle and an array reference of database names, checks if
# database option of rep agent thread has been enabled for each database.
# Returns a list of messages prefixed with "OK" when replication agent has been
# enabled, else with "ERR".
sub check_db_repagent {

  my ( $dbh, $databases ) = @_;

  my @msg;
  for my $db ( @{ $databases } ) {

    my $rep;
    eval { $rep = run_parse_repagent_opt( $dbh, $db ) };
    if ( $@ ) {

      push @msg, qq[ERR could not run $db..sp_configure: $@];
      next;
    }

    push @msg,
      # For on going replication, need to have "run value" of 1.
      ( defined $rep && $rep >= 1 ? 'OK ' : 'ERR ' )
      . join ': ', $db, 'rep agent enabled',  $rep
      ;
  }

  return @msg;
}

# Given a database handl and the database name, returns the run time value of
# "enable rep agent threads" parameter (Sybase database option) as a list.  1
# means threads are enabled; 0 means not.
sub run_parse_repagent_opt {

  my ( $dbh, $db ) = @_;

  # Columns|Keys of command output.
  my ( $param, $runval ) = ( 'Parameter Name', 'Run Value' );
  my $rep_agent_opt = qq[$db..sp_configure 'enable rep agent threads'];

  my $old = $dbh->{'AutoCommit'};
  # Turn off transactions.
  $dbh->{'AutoCommit'} = 1;

  my $result = $dbh->selectrow_hashref( $rep_agent_opt );

  $dbh->{'AutoCommit'} = $old;

  for ( values %{ $result } ) {

    s/^\s+//;
    s/\s+$//;
  }

  return $result->{ $runval };
}

# Given a OMP::Config object containing database connection data, returns a
# database handle.  Pass in a optional server name to override default one.
sub make_connection {

  my ( $cf, $section, $server_in ) = @_;

  my ( $server, $user, $pass ) =
    map
      { $cf->getData( "$section.$_" ) }
      qw[ server user password ];

  die "No database log in data found"
    if grep { ! defined }  $server, $user, $pass;

  #  Override default server.
  $server = $server_in if $server_in;

  my $dbh =
    DBI->connect( "dbi:Sybase:server=$server", $user, $pass,
                  { 'RaiseError' => 1 ,
                    'PrintError' => 0 ,
                    'AutoCommit' => 0 ,
                  }
                )
      or croak $DBI::errstr;

  for ( $dbh )
  {
    $_->{'syb_show_sql'} = 1 ;
    $_->{'syb_show_eed'} = 1 ;
  }

  return $dbh ;
}

=pod

=head1 NAME

dbserver-status.pl - Check datbaser server status

=head1 SYNOPSIS

Send output via mail ...

  dbserver-status.pl -mail 'somebody@example.org'

Check only servers at JAC (output goes to standard out, no email is
sent) ...

  dbserver-status.pl -jac

Check only servers at CADC ...

  dbserver-status.pl -cadc


=head1 DESCRIPTION

This program checks if the databases and database servers are up at
JAC & CADC.  For a database at JAC, it also checks if replication
agent has been enabled.

=head2 OPTIONS

=over 4

=item B<-help>

Show this message.

=item B<-nocadc>

Skip database & servers at CADC.

=item B<-nojac>

Skip databases & servers at JAC.

=item B<-error>

Print|Email only the errors, if any.

=item B<-mail> email-address

Send email to the given address instead of printing the result on
standard output.  Specify multiple time to send mail to multiple
addresses.

No email is sent by default.

=item B<-short>

Specify to produce only one line status message, instead of a detailed
report.

=back

=head1 AUTHOR

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2009 Science and Technology Facilities Council.  All
Rights Reserved.

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
USA.

=cut

