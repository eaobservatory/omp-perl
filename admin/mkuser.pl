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

# cat user.details | perl mkuser.pl

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

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

  print join("--",values %user),"\n";

  # Password should be supplied by user
  try {
    OMP::UserServer->addUser( $ompuser );
  } otherwise {
    my $E = shift;
    print "Error: $E\n";
  }

}
