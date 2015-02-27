#!/local/perl/bin/perl

use strict; use warnings; use Carp qw[ carp croak confess ];
use 5.010;
$| = 1;

our $VERSION = '0.01';

use DBI;
use Getopt::Long    qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;
use List::MoreUtils qw[ natatime ];

use JAC::Setup      qw[ omp ];
use JSA::DB::Sybase qw[ connect_to_db ];

my $cred =
  q[/jac_sw/etc/ompsite.cfg]
  ;
my $dbquery_chunk = 200;


my ( $verbose , $mail , $help );
GetOptions( 'h|help|man' => \$help,
            'mail!'      => \$mail,
            'verbose=i'  => \$verbose
          )
  or pod2usage( '-exitval'  => 2 , '-verbose'  => 1 ) ;

$help and pod2usage( '-exitval' => 0 , '-verbose' => 3 );

my $file = $ARGV[0]
  or die sprintf "Give *%s* file %s\n" ,
          'a CSV file' ,
          'to generate email address update SQL.'
          ;

my @data = parse_file( $file );
my $iter = natatime( $dbquery_chunk , @data );
my $update = update_sql();
while( my @chunk = $iter->() )
{
  print qq[begin tran\n];
  for my $pair ( @chunk )
  {
    my ( $id , $addr ) = @{ $pair };
    printf $update , $addr , $addr , $id ;
  }
  print qq[\ngo\n\ncommit\ngo\n\n];
}

exit;

sub parse_file
{
  my ( $file ) = @_;

  my @out;
  open my $fh , '<' , $file
    or croak( qq[Cannot open $file to read: $!] );

  while ( my $line = <$fh> )
  {
    $line =~ /^\s*$/ || $line =~ /^\s*#/
      and next;

    my ( $id , $name , $addr ) = split /\s*[,;]+\s*/ , $line ;
    $id && $addr or next;
    push @out , [ map { s/^\s+// ;  s/\s+$//; $_ }  $id , $addr ];
  }

  close $fh or croak( qq[Could not close $file: $!] );

  return @out;
}

sub update_sql
{
  return <<'_UPDATE_';
    UPDATE omp..ompuser
    SET   email = '%s'
    WHERE email <> '%s' AND userid = '%s'

_UPDATE_

}

