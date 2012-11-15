#!/local/perl/bin/perl

# Given OMP user ids on standard input, convert them to email addresses
# and names in email format "Name <email@doma.in>
#
#   cat users.txt | user2email.pl > emails.txt

use OMP::UserServer;

for my $userid (<>) {
  chomp($userid);
  next unless $userid =~ /\w/;
  $userid =~ s/\s+//;
  my $user = OMP::UserServer->getUser( $userid );
  next unless defined $user;
  print $user->as_email_hdr()."\n" if defined $user->email();
}
