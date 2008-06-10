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

  next if /^\s*#/ or /^\s*$/;

  chomp;
  my $line = $_;

  # Remove comments
  $line =~ s/\#.*$//;

  next unless $line;

  # We have to guess the order
  # Force a split into three so we can distinguish between a
  # missing email address
  #  userid,name,
  # and a missing userid
  #  name,email
  # If a single name is supplied this is fine it it ends in a ,
  my @details  = split(/\s*,\s*/,$line,3);

  for ( @details ) {

    s/^\s+//;
    s/\s+$//;
  }

  my ($userid, $name, $email);
  my %user;
  if (scalar(@details) == 3) {
    $user{userid} = $details[0];
    $user{name} = $details[1];
    $user{email} = $details[2];
  } else {
    $user{name} = $details[0];
    $user{email} = $details[1];
  }


  # Convert broken email to undef. Define broken as an email address
  # that does not have an @
  $user{email} = undef unless $user{email} =~ /\@/;

  # remove spaces from email address
  $user{email} =~ s/\s//g if defined $user{email};


  # Derive user id
  $user{userid} = OMP::User->infer_userid( $user{name} )
    unless defined $user{userid} && length $user{userid};

  # Create new object
  my $ompuser = new OMP::User( %user );

  die "Error creating user object: $user{userid}\n"
    unless $ompuser;

  print $ompuser->userid . ":" . $ompuser->name ."," . 
    (defined $ompuser->email ? $ompuser->email  : "EMPTY" )."\n";

  # More efficient to do the add and catch the failure rather than
  # do an explicit verify
  try {
    OMP::UserServer->addUser( $ompuser );
  } otherwise {
    # Get the user
    my $exist = OMP::UserServer->getUser( $ompuser->userid );
    if ($exist) {
      print "\n*** ";
      print "Failed to add user. Existing entry retrieved for comparison:\n";
      print "#" .$exist->userid . ":" . $exist->name ."," . 
	(defined $exist->email ? $exist->email : "EMPTY" )."\n";
      print "***\n";
    } else {
      print "ERROR ADDING USER $user{userid}\n";
      my $E= shift;
      print $E;
    }

  }

}
