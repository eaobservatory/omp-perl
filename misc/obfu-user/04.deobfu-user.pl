#!/local/perl/bin/perl

use strict; use warnings; use Carp qw[ carp croak confess ];
use 5.016;
$| = 1;

our $VERSION = '0.01';

use DBI;
use File::Slurp     qw[ read_file ];
use Getopt::Long    qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;

use JAC::Setup qw[ omp ];
use OMP::General;
use OMP::User;

my $contactable = 1;
GetOptions( 'help' => \(my $help) ,
            'show' => \(my $show) ,

            'contactable!' => \$contactable
          )
          or pod2usage( '-exitval' => 2 , '-verbose'  => 1 );

$help and pod2usage( '-exitval' => 0 , '-verbose' => 3 );

my $file = $ARGV[0]
    or pod2usage( '-exitval' => 1 , '-verbose'  => 0 ,
                  '-message' =>
                    qq[Give a file with ";"-separated (unobfuscated) user id, name, & email address.\n]
                );


my @list = fill_userid( parse_list( $file ) );
$show and show_list( @list );

my $update = update_sql_deobfu();
for my $user ( @list )
{
  my $userid = $user->[0];
  my ( $obfu_id ) = OMP::General->rot13( $userid );

  print qq[begin tran\n] ;
  print map { make_sql_print( $_ ) } ( $user , [ $obfu_id ] );
  printf $update ,
    $userid ,
    $obfu_id ,
    $contactable ,
    ( $user->[2] ? q/"/ . $user->[2] . q/"/ : 'null' ) ,
    $user->[1]
    ;
  print qq[\ngo\n\ncommit\ngo\n\n];
}


exit;

sub make_sql_print
{
  my ( $user ) = @_;

  return sprintf qq[print "-- %s\n"] ,
          join q/ ; / , map { $_ || '' } @{ $user } ;
}

sub show_list
{
  my ( @list ) = @_;

  my $format = qq[%s  ;  %s  ;  %s\n];

  for my $user ( @list )
  {
    printf $format , @{ $user };
  }
  return;
}

sub fill_userid
{
  my ( @list ) = @_;

  for my $user ( @list )
  {
    my $id = $user->[0];
    $user->[0] =
     $id && length $id
     ? uc( $id )
     : OMP::User->infer_userid( $user->[1] )
     ;
  }
  return @list;
}

sub parse_list
{
  my ( $file ) = @_;

  my @out;
  for my $line ( read_file( $file ) )
  {
    $line =~ m/^\s*#/ || $line =~ m/^\s*$/
      and next;

    my @store;
    # userid (if any); name; email address
    for my $el ( split /\s*[,;]\s*/ , $line , 3 )
    {
      $el =~ s/^\s+// ;
      $el =~ s/\s+$// ;
      push @store , $el ;
    }
    push @out , [ @store ];
  }
  return @out;
}

sub update_sql_deobfu
{
  return <<'_UPDATE_';

    DECLARE @keep VARCHAR(32) , @remove VARCHAR(32)

    SELECT @keep = '%s' , @remove = '%s'

    UPDATE  omp..ompfaultbody     SET     author        = @keep WHERE author        = @remove
    UPDATE  omp..ompfeedback      SET     author        = @keep WHERE author        = @remove
    UPDATE  omp..ompshiftlog      SET     author        = @keep WHERE author        = @remove
    UPDATE  omp..ompobslog        SET     commentauthor = @keep WHERE commentauthor = @remove
    UPDATE  omp..ompproj          SET     pi            = @keep WHERE pi            = @remove
    UPDATE  omp..ompmsbdone       SET     userid        = @keep WHERE userid        = @remove

    UPDATE  omp..ompprojuser
      SET  userid = @keep , contactable = %d
    WHERE  userid = @remove

    UPDATE omp..ompuser
      SET obfuscated = 0 , email = %s ,
          userid = @keep , uname = "%s"
    WHERE userid = @remove
_UPDATE_

}

__END__

=pod

=head1 NAME

04.deobfu-user.pl - Generate SQL to unobfuscate user data

=head1 SYNOPSIS

  04.deobfu-user.pl userid-name-email.csv

=head1  DESCRIPTION

This program generates SQL query to update data for an obfuscated user
id.  Note that given data should be in unobfuscated form. Obfuscated
user id is generated from the given one or inferred from the name.

Data of a user is listed on a line ...

  USERID ; Name ; email@ddress

... empty lines & lines with comments (marked with C<#>) are ignored.


=head2  OPTIONS

=over 2

=item B<-help>

Show this message.

=item B<-show>

Show parsed user data, with generated user id if missing.

=item B<-contactable> < 1 | 0 >

Specify default value for all the users to mark as "contactable". See <>.

=back

=head2 SEE ALSO

=over 2

=item L<OMP::User>

=item L<OMP::Project>

=back

=head1 COPYRIGHT

Copyright (C) 2015 East Asian Observatory.
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

