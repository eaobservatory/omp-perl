#!/local/perl/bin/perl

use strict; use warnings; use Carp qw[ carp croak ];
use 5.016;
$|= 1;

use File::Path    qw[ make_path ];
use Getopt::Long  qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;
use Text::Wrap    qw[ wrap ];
use Time::Moment;

use FindBin;

use constant OMPLIB => "$FindBin::RealBin/..";

BEGIN {
    $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "cfg")
        unless exists $ENV{OMP_CFG_DIR};
}

use lib OMPLIB;

use OMP::NightRep;


use lib '/home/agarwal/comp/perl5/lib';
use Anubhav::Debug qw[ epl eph errt ];

my $ROOT   = q[/export/data/obslog-dump];
my %OK_TEL = ( 'jcmt' => undef , 'ukirt' => undef );

my $noisy = 1;
my ( $tel , $start , $end );
GetOptions( 'help'      => \( my $help ) ,
            'verbose=i' => \$noisy ,

            'root=s' => \$ROOT ,

            'start=s' => \$start ,
            'end=s'   => \$end ,
            'tel=s'   => \$tel ,
          )
          or die;

$tel   = check_telescope( $tel );
$start = $start ? string_to_time_start( $start ) : today_start() ;
$end   =  $end  ? string_to_time_end( $end )     : today_end() ;

$noisy and warn sprintf "Telescope: %s  Start: %s  End: %s\n" ,
                  $tel , map time_to_datetime_string( $_ ) , $start , $end
                  ;


while ( $start <= $end )
{
  my $date_str = time_to_date_string( $start );

  $noisy and warn qq[=> $date_str\n];

  my $dir   = make_dir( $ROOT , $tel , $start ) or last;
  my $store = join '/' , $dir , $date_str;
  $noisy and warn qq[==> outout: $store\n];

  open my $fh , '>' , $store or die qq[Cannot open $store to write: $!\n];
  print $fh list_nightrep( $date_str , $tel );
  close $fh or die qq[Could not close $store after writing: $!\n];

  $start = $start->plus_days( 1 );
}
exit;

sub make_dir
{
  my ( $root , $tel , $time ) = @_;

  my $dir = join q[/] , $root , lc( $tel ) , $time->strftime( '%Y' );

  my $err;
  make_path( $dir , { 'error' => \$err , 'verbose' => 1 , 'group' => 'jcmt_data' } );
  ( $err && scalar @{ $err } ) or return $dir;

  croak qq[make_path( $dir ) failed: ] , join "\n" , @{ $err };
}

sub check_telescope
{
  my ( $tel ) = @_;

  $tel or die qq[No telescope given (see "-tel" option).\n];

  for my $t ( keys %OK_TEL )
  {
    fc( $t ) eq fc( $tel ) and return uc( $tel );
  }

  die qq[Unknown telescope, $tel, given.\n];
}

sub time_to_datetime_string
{
  my ( $t ) = @_;
  return $t->strftime( '%Y-%m-%dT%H:%M:%S%Z' );
}
sub time_to_date_string
{
  my ( $t ) = @_;
  return $t->strftime( '%Y-%m-%d' );
}
sub string_to_time_start { return string_to_time( $_[0] , 'T00:00:00Z' ); }
sub string_to_time_end   { return string_to_time( $_[0] , 'T23:59:59Z' ); }
sub string_to_time
{
  my ( $date , $time ) = @_;

  $date or croak( qq[No date specified.\n] );

  unless ( $time )
  {
    warn qq[No time given; using start of the day (UTC).\n];
    $time = 'T00:00:00Z';
  }

  $date =~ tr{/}/-/;

  #  Time::Moment needs no separator in time if lacking in date.
  $date =~ m/^[0-9]{8}$/ and $time =~ tr/://d ;
  #  Needed to have Time::Moment generate object from the string.
  return Time::Moment->from_string( $date . $time );
}
sub today_start
{
  my $t = Time::Moment->now_utc();
  return $t->with_hour( 0 )
            ->with_second( 0 )
            ->with_minute( 0 ) ;
}
sub today_end
{
  my $t = Time::Moment->now_utc();
  return $t->with_hour( 23 )
            ->with_second( 59 )
            ->with_minute( 59 ) ;
}

sub list_nightrep
{
  my ( $date , $tel ) = @_;

  my $nr = OMP::NightRep->new ( date => $date, telescope => $tel );
  unless( $nr )
  {
    carp( $tel . qq[::$date: Could not find night report.\n] );
    return;
  }
  return
    join( qq[\n] , map { s/\s+$// ; $_ } $nr->astext() ) ,
    qq[\n\n] ,
    proj_faults( $nr )
    ;
}

sub proj_faults
{
  my ( $nr ) = @_;

  local $Text::Wrap::columns = 72;

  my $indent = q[  ];
  my $out = qq[** Faults Related to Projects:\n];

  my @fault = $nr->faults();
  scalar @fault or
    return $out . $indent . qq[No faults were filed.\n];

  my @list;
  for my $faults ( @fault )
  {
    for my $f ( $faults->faults() )
    {
      my @proj = $f->projects() or next;
      push @list , join q[: ] , $f->faultid() , join q[, ] , sort @proj;
    }
  }
  return $out .= scalar @list
                  ? join qq[\n] , map( wrap( $indent , $indent , $_ ) , @list )
                  : $indent . qq[No associated projects found.\n]
                  ;
}
