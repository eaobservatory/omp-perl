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

# Increase in the number increases the debug output.
my $DEBUG = 0;
my $DEBUG_PREFIX = 'DEBUG:  ';

my ( $override, $help, @other );
GetOptions(
            'help'   => \$help,
            'debug+' => \$DEBUG,
            'override=s' => \$override
          )
    or die pod2usage( '-exitval' => 2, '-verbose' => 1 );

$help and pod2usage( '-exitval' => 1, '-verbose' => 2 );

( $override, @other ) = uniq( map { $_ ? uc : () } $override, @ARGV );

$override && 0 < scalar @other
  or die <<_NO_DATA_;
Need both a project id in "-override" option and at least one another project id.
Please run with -help option for details.
_NO_DATA_

process( $override, @other );

$DEBUG > 2 and debug_print( "d o n e\n" );
exit;

sub process {

  my ( $override, @other ) = @_;

  return
    unless $override && 0 < scalar @other;

  my $db = OMP::DBbackend->new;

  add_link( $db, $override, @other )
    or print "All the projects might not have been linked.\n";

  debug_print( "Disconnecting with database\n" );

  my $dbh = $db->handle;
  $dbh->disconnect if $dbh;
}

sub add_link {

  my ( $db, $override, @other ) = @_;

  debug_print( 'Projects to be linked: ', join( ', ', $override, @other ), "\n" );

  my @valid = verify_projid( $override, @other );

  debug_print( 'Validated projects: ', join( ', ', @valid ), "\n" );

  unless ( $override eq $valid[0] ) {

    warn "Replacement project id, '$override', could not be validated; skipping\n";
    return;
  }

  return if 2 > scalar @valid;

  ( $override, @other ) = @valid;

  # Sybase component (or DBD::Sybase) does not allow place holder for a
  # value|column name in SELECT clause.
  my $link = <<'_ADD_LINK_';
    INSERT %s
    ( projectid, isprimary, country, tagpriority, tagadj )
    ( SELECT '%s' , 0, country, tagpriority, tagadj
      FROM %s
      WHERE projectid = ? AND isprimary = 1
    )
_ADD_LINK_

  $link = sprintf $link,
            $OMP::ProjDB::PROJQUEUETABLE,
            $override,
            $OMP::ProjDB::PROJQUEUETABLE ;

  my $err;
  try {

    my $dbh = $db->handle;
    $db->begin_trans;

    for ( @other ) {

      debug_print( "Linking $override with $_:\n$link\n" );

      $dbh->do( $link, undef, $_ )
        or $err++, warn join ' ', make_lineno( __LINE__, $DEBUG ), $dbh->errstr;
    }

    $db->commit_trans;
  }
  catch OMP::Error with {

    $err = join ' ', make_lineno( __LINE__, $DEBUG ), shift;

    warn "Rolling back transaction:\n$err";
    $db->rollback_trans;
    return;
  }
  otherwise {

    $err = join ' ', make_lineno( __LINE__, $DEBUG ), shift;
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

        $DEBUG > 1 and debug_print( "$_ is ok\n" );

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

  my ( $n, $debug ) = @_;

  $n = "(line $n)" if defined $n;

  return $n if $debug or 2 > scalar @_;
  return;
}

sub debug_print {

  return unless $DEBUG;

  print STDERR join '', $DEBUG_PREFIX || (), @_;
  return;
}

__END__

=pod

=head1 NAME

link-projqueue.pl - Make one project queue to appear in other queues

=head1 SYNOPSIS

  link-projqueue.pl -help

  link-projqueue.pl \
    [ -debug ]      \
    -override source-projectid \
    projectid-1 [ projectid-2 projectid-3 ... ]

=head1 DESCRIPTION

This program makes the one project (specified by I<-override> option)
turn up in other projects' (given as plain I<arguments>) queues.

=head2 OPTIONS

=over 2

=item B<help>

Shows this message.

=item B<debug>

Show debugging information.  Specify multiple times to increase
verbosity.

=item B<override> projectid

Specify a projectid which should appear in another project's queue.

This option is B<required>.

=back

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

