#!/usr/local/bin/perl

use warnings;
use strict;

use Getopt::Long qw(:config gnu_compat no_ignore_case no_debug);
use Pod::Usage;
use List::MoreUtils qw[ uniq ];

use OMP::Error qw[ :try ];
use OMP::DBbackend;
use OMP::ProjDB;
use OMP::ProjServer;

# Increase in the number increases the verbose output.
my $VERBOSE = 0;

my ( $push, $help, @other );
GetOptions( 'help' => \$help,

            'push=s'   => \$push,
            'verbose+' => \$VERBOSE,
          )
    or die pod2usage( '-exitval' => 2, '-verbose' => 1 );

$help and pod2usage( '-exitval' => 1, '-verbose' => 2 );

( $push, @other ) = uniq( map { $_ ? uc : () } $push, @ARGV );

$push && 0 < scalar @other
  or die <<_NO_DATA_;
Need both a project id in "-push" option and at least one another project id.
Please run with -help option for details.
_NO_DATA_

process( $push, @other );

$VERBOSE > 2 and make_noise( "d o n e\n" );
exit;

sub process {

  my ( $push, @other ) = @_;

  return
    unless $push && 0 < scalar @other;

  my $db = OMP::DBbackend->new;

  add_link( $db, $push, @other )
    or print "All the projects might not have been linked.\n";

  make_noise( "Disconnecting with database\n" );

  my $dbh = $db->handle;
  $dbh->disconnect if $dbh;
}

sub add_link {

  my ( $db, $push, @other ) = @_;

  make_noise( 'Projects to be linked: ', join( ', ', $push, @other ), "\n" );

  my @valid = verify_projid( $push, @other );

  make_noise( 'Validated projects: ', join( ', ', @valid ), "\n" );

  unless ( $push eq $valid[0] ) {

    warn "Replacement project id, '$push', could not be validated; skipping\n";
    return;
  }

  return if 2 > scalar @valid;

  ( $push, @other ) = @valid;

  # Sybase component (or DBD::Sybase) does not allow place holder for a
  # value|column name in SELECT clause.
  my $sql = <<'_ADD_LINK_';
    INSERT %s
    ( projectid, isprimary, country, tagpriority, tagadj )
    ( SELECT '%s' , 0, country, tagpriority, tagadj
      FROM %s
      WHERE projectid = ? AND isprimary = 1
    )
_ADD_LINK_

  $sql = sprintf $sql,
            $OMP::ProjDB::PROJQUEUETABLE,
            $push,
            $OMP::ProjDB::PROJQUEUETABLE ;

  my $err;
  try {

    my $dbh = $db->handle;
    $db->begin_trans;

    for ( @other ) {

      make_noise( "Linking $push with $_:\n" );

      $dbh->do( $sql, undef, $_ )
        or $err++, warn join ' ', make_lineno( __LINE__, $VERBOSE ), $dbh->errstr;
    }

    $db->commit_trans;
  }
  catch OMP::Error with {

    $err = join ' ', make_lineno( __LINE__, $VERBOSE ), shift;

    warn "Rolling back transaction:\n$err";
    $db->rollback_trans;
    return;
  }
  otherwise {

    $err = join ' ', make_lineno( __LINE__, $VERBOSE ), shift;
    warn $err if $err;
  } ;

  return if $err;
  return 1;
}

{
  my ( %valid, %invalid );
  sub verify_projid {

    my ( @projid ) = @_;

    my ( @valid );
    for ( @projid ) {

      next if exists $invalid{ $_ };

      if ( exists $valid{ $_ } || OMP::ProjServer->verifyProject( $_ )) {

        $VERBOSE > 1 and make_noise( "$_ is ok\n" );

        $valid{ $_ }++;
        push @valid, $_;
        next;
      }

      $invalid{ $_ }++;
      warn "'$_' is not a valid project id, will be skipped\n";
    }

    return @valid;
  }
}

sub make_lineno {

  my ( $n, $verbose ) = @_;

  $n = "(line $n)" if defined $n;

  return $n if $verbose or 2 > scalar @_;
  return;
}

sub make_noise {

  return unless $VERBOSE;

  print $_ for @_;
  return;
}

__END__

=pod

=head1 NAME

link-projqueue.pl - Make one project queue to appear in other queues

=head1 SYNOPSIS

To have "projectid" appear in "projectid-1" & "projectid-2" queues ...

  link-projqueue.pl   \
    [ -verbose ]      \
    -push projectid   \
    projectid-1 projectid-2

=head1 DESCRIPTION

This program makes the one project turn up in other project (given as
plain arguments) queues.

=head2 OPTIONS

=over 2

=item B<-help>

Shows this message.

=item B<-verbose>

Specify multiple times to increase verbosity.

=item B<-push> projectid

Specify a projectid which should appear in another project's queue.

This option is B<required>.

=back

=head1 EXAMPLE

Say M10BU08 need to show up in M10BC07 queue; the project queue table
has ...

  projectid   country   tagpriority isprimary tagadj
  ----------- --------- ----------- --------- -----------
  M10BC07     CA                364         1           0
  M10BU08     UK                244         1           0

To have M10BU08 project appear in M10BC07 queue ...

  link-project.pl -push M10BU08  M10BC07

... afterword the table entries would be ...

  projectid   country   tagpriority isprimary tagadj
  ----------- --------- ----------- --------- -----------
  M10BC07     CA                364         1           0
  M10BU08     UK                244         1           0
  M10BU08     CA                364         0           0

=head1 BUGS

Please notify the OMP group if there are any.

=head1 AUTHORS

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

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
USA.

=cut

