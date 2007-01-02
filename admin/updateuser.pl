#!/local/perl/bin/perl -X

=head1 NAME

updateuser - Update user DB information

=head1 SYNOPSIS

  echo USERID,NEWNAME,NEWEMAIL | updateuser

  cat updatefile | updateuser

  echo USERID,,NEWEMAIL | updateuser
  echo USERID,NEWNAME,  | updateuser

=head1 DESCRIPTION

Modify all the user information piped in from standard input.  Each
line of the input must be a comma-separated list with the user id of
the entry to be changed and optionally the new email or new name. If
an entry is blank the contents are not changed (ie they are not
blanked).  This allows easy changes to addresses without having to
remember the full name.

Comment lines are skipped.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2002-2003 Particle Physics and Astronomy
Research Council. All Rights Reserved.

=cut

use OMP::User;
use OMP::UserServer;

foreach my $line (<>) {
  # Skip blank lines
  next unless $line =~ /\w/;
  next unless $line =~ /,/;
  next if $line =~ /^\#/;
  chomp($line);

  # Extract information
  my ($user, $newname, $newemail) = split(/,/, $line);

  print "USERID: $user\n";
  my $user = OMP::UserServer->getUser( $user );

  if (!defined $user) {
    print "********* NOT IN DATABASE ********\n";
    next;
  }

  # Before
  print "\t" . $user->as_email_hdr ."\n";

  # Update email and name as required
  $user->email($newemail) if $newemail =~ /\w/;
  $user->name($newname) if $newname =~ /\w/;

  # Update the information
  print "Update:\t".$user->as_email_hdr."\n\n";
  OMP::UserServer->updateUser( $user );
}
