#!/usr/local/bin/perl

# Populates user database with initial details

# Input: text file containing user details
#
# CSV file containing:
#   userid [optional]
#   name
#   email address

# The userid is optional - if it is not present the userid
# will be derived from the name by taking the first letter
# of  the first name and the surname.

# All science program User ids should be SURNAMEI (eg JENNESST).

# cat user.details | perl mkuser.pl

# Uses the infrastructure classes so each user is inserted
# independently rather than as a single transaction

# If a user already exists, the current details will be displayed
# for comparison

use warnings;
use strict;

use OMP::UserDB;
use OMP::User;
use OMP::UserServer;
use OMP::Error qw/ :try /;

while (<>) {
  chomp;
  my $line = $_;

  # Remove comments
  $line =~ s/\#.*$//;

  next unless $line;

  # We have to guess the order
  my @details  = split(/,/,$line);

  my ( $userid, $name, $email);
  my %user;
  if (scalar(@details) == 3) {
    $user{userid} = $details[0];
    $user{name} = $details[1];
    $user{email} = $details[2];
  } else {
    $user{name} = $details[0];
    $user{email} = $details[1];
  }

  # Derive user id
  unless (defined $user{userid}) {
    # Split the name on space
    my @parts = split /\s+/, $user{name};
    $user{userid} = $parts[-1] . uc(substr($parts[0],0,1) );
  }

  # Create new object
  my $ompuser = new OMP::User( %user );

  print $ompuser->userid . ":" . $ompuser->name ."," . $ompuser->email ."\n";

  # More efficient to do the add and catch the failure rather than
  # do an explicit verify
  try {
    OMP::UserServer->addUser( $ompuser );
  } otherwise {
    # Get the user
    my $exist = OMP::UserServer->getUser( $ompuser->userid );
    print "\n*** ";
    print "Failed to add user. Existing entry retrieved for comparison:\n";
    print "#" .$exist->userid . ":" . $exist->name ."," . $exist->email ."\n";
    print "***\n";

  }

}
