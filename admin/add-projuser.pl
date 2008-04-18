#!/usr/local/bin/perl

#  Given a CSV file, with each record on one line, in format of ...
#
#    <project id>,<user id>,<role>,<contactable>
#
#  ... where,
#
#     projectid : project id in ompproj table,
#        userid : user id in ompuser table,
#           role: one of 'COI', 'PI', or 'SUPPORT' (any case),
#    contactable: 1 or 0 to indicate if user is contactable
#
# ... users are added to the ompprojuser table.

use warnings;
use strict;
use Carp qw/ carp /;

use OMP::Error qw/ :try /;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::UserServer;

#  Known user roles for a project.
my @roles = map { uc $_ } qw/ coi pi support /;

my $projdb = OMP::ProjDB->new( 'DB' => OMP::DBServer->dbConnection );

for my $file ( @ARGV ) {

  my %file = process_file( $file );

  $projdb->_db_begin_trans;
  my $err;
  try {

    #  Sort by line number.
    for my $line ( sort { $a <=> $b } keys %file ) {

      add_user( $file{ $line } )
        or warn "Due to errors, skipped line $line in file $file\n";
    }

    $projdb->_db_commit_trans;
  }
  catch OMP::Error with {

    $err = shift;
  };

  if ( $err ) {

    warn qq/Rolling back changes due to error while processing file '$file':\n  $err/;
    $projdb->_db_rollback_trans;
  }
}

sub add_user {

  my ( $proj, $input ) = @_;

  return unless verify_record( $proj );

  my ( $projid, $role ) = @{ $proj }{qw/ projectid role /};

  printf "Adding %s as %s with project %s\n", $proj->{'userid'}, $role, $projid;

  $proj->{'capacity_order'} =
    1 + $projdb->_get_max_role_order( $projid, $role );

  $projdb->_insert_project_user( %{ $proj } );
  return 1;
}

sub verify_record {

  my ( $proj ) = @_;

  my $err = '';
  unless ( verify_role( $proj->{'role'} ) ) {

    $err++;
    warn 'Unknown role ', $proj->{'role'}, "\n";
  }

  unless ( verify_user( $proj->{'userid'} ) ) {

    $err++;
    warn 'Unknown user ', $proj->{'userid'}, "\n";
  }

  unless ( OMP::ProjServer->verifyProject( $proj->{'projectid'} ) ) {

    $err++;
    warn 'Cannot verify project ', $proj->{'projectid'}, "\n";
  }

  return ! $err;
}

#  Return a truth value indicating if the given userid is known to OMP.
sub verify_user {

  my ( $user ) = @_;

  my $ok;
  try {
     $ok =  OMP::UserServer->verifyUser( $user );
  }
  catch OMP::Error with {

    my $err = shift;
    carp "Error when verifying '$user' userid: $err";
  };

  return $ok;
}

#  Returns a truth value indicating if the given role is ok.
sub verify_role {

  my ( $role ) = @_;

  return unless $role;
  return scalar grep { $role eq $_ } @roles;
}

sub process_file {

  my ( $file ) = @_;

  open my $fh , '<', $file or carp "Cannot open '$file' to read: $!";

  my %prop;
  while ( my $line = <$fh> ) {

    next if $line =~ /^\s*#/
          or $line =~ /^\s*$/;

    $prop{ $. } = parse( $line );
  }

  close $fh or die "Cannot close '$file': $!";

  return %prop ;
}

#  Given a line (or, record) as described above, returns a hash reference of
#  project id, user id, role, and contactable status.
sub parse {

  my ( $line ) = @_;

  my $sep = '\s*,\s*';
  my ( $proj, $user, $role, $contact ) =
    map { s/^\s+//; s/\s+$//; uc $_ } split /$sep/, $line, 4;

  #  Keys are same as expected by OMP::ProjDB->_insert_project_user().
  return
    { 'projectid' => $proj,
      'userid' => $user,
      'role' => $role,
      'contactable' => $contact ? 1 : 0,
    };
}

