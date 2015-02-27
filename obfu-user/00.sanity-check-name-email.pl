#!/local/perl/bin/perl

use strict; use warnings;
use 5.016;  # for fc() & say().

use Carp   qw[ carp croak confess ];

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

my $cred =
  q[/jac_sw/etc/ompsite.cfg]
  #q[/jac_sw/etc/ompsite-dev.cfg]
  ;
my $dbquery_chunk = 200;

my $my_name = ( fileparse( $0 , '.p[lm]' ) )[0];
my $mismatches = join '-' , $my_name , 'MISMATCH' ;
my $list_to_userids = join '-' , $my_name , 'USERID.CSV' ;


my ( $verbose , $help );
GetOptions( 'h|help|man' => \$help,
            'verbose=i'  => \$verbose
          )
  or pod2usage( '-exitval'  => 2 , '-verbose'  => 1 ) ;

$help and pod2usage( '-exitval' => 0 , '-verbose' => 3 );

my @file = @ARGV
  or die sprintf "Give %s file %s\n"
          , 'a'
          , 'to do hide user details.'
          ;

my $log = q[/home/agarwal/src/jac-git/omp-perl/obfu-user/x.obfu.log];
unlink( $log );
init_logger( $log );

my $dbh_sel = connect_to_db( $cred );

my @data = process_user_list( @file );
my $data = to_userid( $dbh_sel , @data );

show_mismatch( $mismatches , $data );
show_userid( $list_to_userids , $data );

exit;


BEGIN
{
  my @field = qw[ userid name addr ];

  sub show_mismatch
  {
    my ( $file , $data ) = @_;

    my ( $max_in , @max ) = max_length( $data );

    my $col_div = q[  ] ;
    my $column = join $col_div ,
                    sprintf( q[%%-%ds] , $max_in ) ,
                    map
                    { sprintf q[%%-%ds : %%-%ds] , ($_) x 2 }
                    @max
                    ;
    $column .= "\n";

    my $div = sum 2 * length( $col_div ) ,
                  2 , scalar( @max ) ,
                  $max_in , map {; 1 , $_ * 2 } @max
                  ;
    $div = join '' , ('#') x $div;
    $div .= "\n";

    my $header =
      $div
      . sprintf( $column , 'list input' , ( qw[ list database ] ) x3 )
      . sprintf( $column , '' , map { ( $_ ) x 2 } qw[ userid name email ] )
      . $div
      ;

    my $out = $header;
    for my $key ( sort keys %{ $data } )
    {
      exists $data->{ $key }{'MISMATCH'} or next;

      my ( $id , $name , $addr ) = map { $data->{ $key }{'MISMATCH'}{ $_ } } @field;
      $out .=
        sprintf $column ,
                  $key ,
                  map
                  { $_->{'list' } // '' , $_->{'db'} // '' }
                  ( $id , $name , $addr)
                  ;
      $out .= "\n";
    }
    $out .= $header;
    for ( $out )
    {
      s/^[ ]/./mg;
      s/[ ]+$/ /mg;
    }
    warn qq[saving mismatches in file $file ...\n];
    return print_buffer( $file , $out );
  }

  sub max_length
  {
    my ( $data  ) = @_;

    my ( @key , @name , @id , @addr );
    for my $key ( keys %{ $data } )
    {
      exists $data->{ $key }{'MISMATCH'} or next;

      push @key , length $key ;

      my ( $id , $name , $addr ) = map { $data->{ $key }{'MISMATCH'}{ $_ } } @field;
      $id   and push @id   , map length( $id->{ $_ }   ) , qw[ list db ] ;
      $name and push @name , map length( $name->{ $_ } ) , qw[ list db ] ;
      $addr and push @addr , map length( $addr->{ $_ } ) , qw[ list db ] ;
    }

    return ( max( @key ) , max( @id ) , max( @name ) , max( @addr ) );
  }
}

sub show_userid
{
  my ( $file , $data ) = @_;

  # input;
  # userid , name, email
  my $format = qq[#  %s\n%s%s ; %s ; %s\n];

  my $div = join( '' , ('#' ) x 80 ) . "\n";

  my $header = sprintf $format ,
                  q[given name ; addr ; derived-userid] ,
                  q[#  ],
                  qw[ db-userid db-name db-addr ]
                  ;
  $header = $div . $header . $div;

  my $out = $header;
  for my $given ( sort
                  {
                    ( $data->{ $a }{'userid'} cmp $data->{ $b }{'userid'} )
                    ||
                    ( $data->{ $a }{'name'} cmp $data->{ $b }{'name'} )
                    ||
                    ( $a cmp $b )
                  }
                  keys %{ $data }
              )
  {
     $out .= sprintf $format ,
                $given ,
                '   ' ,
                map
                { $data->{ $given }{ $_ } // '' }
                qw[ userid name email ]
                ;
    $out .= "\n";
  }

  warn qq[saving userid;name;addr in file $file ...\n];
  return print_buffer( $file , $out . $header );
}

sub print_buffer
{
  my ( $file , $buf ) = @_;

  open my $fh , '>' , $file or croak( qq[Cannot open $file to write: $!] );
  print $fh $buf;
  close $fh  or croak( qq[Could not close $file after writing: $!] );

  return;
}


sub to_userid
{
  my ( $dbh , @data ) = @_;

  my $sth = $dbh->prepare( select_any() );

  my ( %out );
  for my $d ( sort
                  { $a->{'userid-infer'} cmp $b->{'userid-infer'}
                    ||
                    $a->{'name'} cmp $b->{'name'}
                  }
                  @data
                )
  {
    my ( $name , $addr , $infer_id ) =
      map  { $d->{ $_ } } qw[ name addr userid-infer ];

    # To make issues with name|email address obvious.
    my $key = user_hash( $addr , $name , $infer_id );
    $out{ $key } = {};

    my $res = make_select( $dbh , $sth , 0 , $addr , $name , $infer_id );
    for my $ref ( $res ? @{ $res } : () )
    {
      my %ref = %{ $ref };
      $out{ $key } = { map {; $_ => $ref{ $_ } } keys %ref };

      my %mis = get_mismatch( # From list;
                              { 'addr' => $addr ,
                                'name' => $name ,
                                'userid' => $infer_id
                              } ,
                              # from database;
                              { 'addr' => $ref{'email'} // '' ,
                                'name' => $ref{'name'} // '' ,
                                'userid' => $ref{'userid'}
                              }
                            );
      if ( scalar keys %mis )
      {
        $out{ $key }->{'MISMATCH'} = { %mis };
        if ( ! exists $mis{'name'} && ! exists $mis{'userid'} )
        {
          warn qq[** Changing email address ...\n];
          $out{ $key }->{'email'} = $mis{'addr'}->{'list'};
        }
      }
    }

    $out{ $key } or warn qq[NO DATA found for "$key".\n];
  }

  return { %out };
}

sub get_mismatch
{
  my ( $list , $db ) = @_;

  my %mis;
  for my $type ( qw[ addr name userid ] )
  {
    my ( $x , $y ) = map
                      { _exist_val( $_ , $type ) // qq[<no $type>] }
                      ( $list , $db )
                      ;
    fc( $x ) eq fc( $y )
      or $mis{ $type } = { 'list' => $x , 'db' => $y };
  }
  return %mis;
}

sub _exist_val
{
  my ( $ref , $k ) = @_;

  exists $ref->{ $k } and return $ref->{ $k };
  return;
}

sub user_hash
{
  my ( $addr , $name , $id ) = @_;
  return join ' ; ' ,
            $id   // '<no userid>' ,
            $name // '<no name>' ,
            $addr // '<no email addr>'
            ;
}

sub process_user_list
{
  my ( @file ) = @_;

  my ( %stat , @data , %data , %check );
  #  Process user lists.
  for my $in ( @file )
  {
    warn "#  $in ...\n";

    for my $line ( read_file( $in ) )
    {
      $stat{ $in}->{'total'}++;
      my ( $addr , $name ) = parse_line( $line ) or next;
      $stat{ $in}->{'parsed'}++;

      unless ( exists $data{ $addr } )
      {
        $data{ $addr }++;
        my $id = OMP::User->infer_userid( $name );
        push @data , { 'addr' => $addr ,
                        'name' => $name ,
                        'userid-infer' => $id
                      };
      }
      elsif ( addr_with_multi_names( $addr , $data{ $addr } , $name ) )
      {
        warn sprintf qq[    skipped line %s for email address %s and name %s\n] ,
                $stat{ $in }->{'total'} ,
                $addr ,
                $name ;
      }

      unless ( exists $check{ $name } )
      {
        $check{ $name } = $addr;
      }
      elsif ( name_with_multi_addrs( $name , $check{ $name } , $addr ) )
      {
        delete $data{ $addr };
        warn sprintf qq[    skipped line %s for email address %s and name %s\n] ,
                $stat{ $in }->{'total'} ,
                $addr ,
                $name ;
      }
    }
  }
  parsed_summary( scalar( @data ) , %stat );

  return @data;
}

sub parsed_summary
{
  my ( $actual , %stat ) = @_;

  say qq[Lines Parsed Summary ...];
  printf qq[  %s ...\n    seen: %d, parsed: %s\n] ,
    $_ ,
    $stat{ $_ }->{'total'} ,
    $stat{ $_ }->{'parsed'} ,
      for sort keys %stat ;

   printf qq[  Total kept: %d\n] , $actual ;

  return;
}

sub name_with_multi_addrs
{
  my ( $name , $old , @new )  = @_;

  all{ fc( $old ) eq fc( $_ ) } @new
    and return;

  my $new_all = join ', ' , @new;
  warn sprintf qq[  OTHER EMAIL ADDRESSES, %s, for name "%s" found (old: %s)\n] ,
      $new_all ,
      $name ,
      $old ;
  return 1;
}

sub addr_with_multi_names
{
  my ( $addr , $old , @new )  = @_;

  my $new_all = join ', ' , @new;

  if ( all { fc( $old ) eq fc( $_ ) } @new )
  {
    if ( any { $old ne $_ } @new  )
    {
      warn sprintf qq[  DIFFERENT CASE in names used for "%s" email address: %s, %s.\n] ,
              $addr ,
              $old ,
              $new_all ;
    }
    else
    {
      #warn sprintf qq[  DUPLICATE NAMES (%s) found for "%s" email address (old: %s).\n] ,
      #        $new_all ,
      #        $addr ,
      #        $old ;
    }
    return ;
  }

  warn sprintf qq[  OTHER NAMES (%s) for "%s" email address found (old: %s)\n] ,
      $new_all ,
      $addr ,
      $old ;
  return 1;
}

sub parse_line
{
  my ( $line ) = @_;

  $line =~ m/^\s*$/ || $line =~ m/^\s*#/
    and return;

  my $marker = 'UPDATEDOMPDATA';
  $line =~ m/^$marker/
    or croak( qq["$marker" not found at the start of "$line".] );

  my $parser =
    qr{ (?<=^$marker)
        \s+
        (?<name> ['\w+] [-',.\s\w]* [.\w]+)
        \s+
        (?<addr> [^@]+\@\S+ )
      }ix;


  $line =~ $parser
    or croak( qq[Could not find name and email address in "$line".] );

  return ( lc $+{'addr'} , $+{'name'} );
}

sub make_select
{
  my ( $dbh , $sth , @arg ) = @_;

  $sth->execute( @arg )
    or Carp::croak( qq[Error in exectue( @arg ): ] , $dbh->errstr() );

  my @data;
  while ( my $data = $sth->fetchrow_hashref() )
  {
    $sth->err()
      and Carp::croak( qq[Error in SELECT: ] , $sth->errstr() );

    keys %{ $data } or next;
    push @data , $data;
  }

  return scalar @data ? [ @data ] : ();
}

sub select_any
{
  return <<'_SELECT_';
    SELECT DISTINCT userid , uname AS name , email , alias , obfuscated
    FROM ompuser
    WHERE obfuscated = ?
      AND (
            UPPER( email ) = UPPER( ? )
            --  expanded name search;
            OR UPPER( uname ) LIKE UPPER( ? )
            --   derived-userid search;
            OR UPPER( userid ) = UPPER( ? )
          )
    ORDER BY userid , uname , email
_SELECT_

}

sub select_userid
{
  return <<'_SELECT_';
    SELECT userid , uname AS name , email , alias , obfuscated
    FROM ompuser
    WHERE UPPER( userid ) = UPPER( ? ) AND obfuscated = ?
    ORDER BY userid , uname , email
_SELECT_

}

sub select_addr
{
  return <<'_SELECT_';
    SELECT userid , uname AS name , email , alias , obfuscated
    FROM ompuser
    WHERE UPPER( email ) = UPPER( ? ) AND obfuscated = ?
    ORDER BY userid , uname , email
_SELECT_

}

sub format_select_name
{
  my ( $n ) = @_;

  for ( $n )
  {
    #  Clear space.
    s/^\s+//;
    s/\s+$//;

    #s/^/%/;
    #s/$/%/;
    s/[. ]+/%/g;
  }
  return $n;
}
sub select_name
{
  return <<'_SELECT_';
    SELECT userid , uname , email , obfuscated
    FROM ompuser
    WHERE UPPER( uname ) LIKE UPPER( ? ) AND obfuscated = ?
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

    SELECT @remove = %s , @keep = %s

    UPDATE  ompfaultbody     SET     author        = @keep WHERE author        = @remove
    UPDATE  ompfaultbodypub  SET     author        = @keep WHERE author        = @remove
    UPDATE  ompfeedback      SET     author        = @keep WHERE author        = @remove
    UPDATE  ompshiftlog      SET     author        = @keep WHERE author        = @remove
    UPDATE  ompobslog        SET     commentauthor = @keep WHERE commentauthor = @remove
    UPDATE  ompproj          SET     pi            = @keep WHERE pi            = @remove
    UPDATE  ompmsbdone       SET     userid        = @keep WHERE userid        = @remove
    UPDATE  ompprojuser      SET     userid        = @keep WHERE userid        = @remove

    UPDATE ompuser
      SET   userid = @keep , uname = ? , obfuscated = 1 , email = null
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


