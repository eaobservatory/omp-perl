#!perl

# Given the project list (from the alloation file rather than reading from
# disk), read the original tex and extract out the PI information for
# comparison with user lists.

use Config::IniFiles;
use OMP::UserServer;
use OMP::User;
use Data::Dumper;
use File::Spec;

# Location of files
my $texdir = "/net/iliahi/export/data/jcmtprop/newprop/latex";

# hard-wire for testing
my $file = "data/alloc02b_jcmt.ini";
$file="data/alloc03a_jcmt.ini";

my %alloc;
tie %alloc, 'Config::IniFiles', ( -file => $file );

my @newuser;
for my $proj (sort keys %alloc ) {
  next if $proj =~ /info|support/;

  # Need to find the corresponding filename
  my $found;
  for (my $n = 10; $n > 0; $n--) {
    my $file = File::Spec->catfile( $texdir,
				    sprintf("%s.%03d.tex",lc($proj),$n ));
    if (-e $file && ! -z _) {
      $found = $file;
      last;
    }
  }

  if (!defined $found) {
    print "Unable to find file for project $proj. Skipping.\n";
    next;
  }

  # Read the file
  open(my $fh, "<$found") or do { print "Error opening file $found: $!"; next};

  my %data;
  my @keys = qw/ PIfirstname PIlastname email/;
  while (defined (my $line = <$fh>)) {
    for my $text (@keys) {
      if (!exists $data{$text}) {
	$line =~ /$text\s+\{(.*)\}/ && ($data{$text} = $1);
      }
    }

    # Since most of the information is at the start of the file
    # abort if we have everything
    my $notthere = 0;
    for my $text (@keys) {
      if (!exists $data{$text}) {
	$notthere = 1;
	last;
      }
    }
    last unless $notthere == 1;
  }

  close($fh);

  # Now need to convert the name to a user ID
  my $name = "$data{PIfirstname} $data{PIlastname}";
  $name =~ s/~//g; # Remove latexism
  my $piuser = new OMP::User( name => $name,
			      email => $data{email},
			    );

  print lc($proj) . ": " . $piuser->infer_userid ." cf $alloc{$proj}{pi}\n";
  if ($piuser->infer_userid ne $alloc{$proj}{pi}) {
    print "**DISCREPANT** [".$piuser->name."]\n";
    next;
  }

  # Now get the details from the database
  my $isthere = OMP::UserServer->verifyUser( $alloc{$proj}{pi});
  if ($isthere) {
    my $user = OMP::UserServer->getUser( $alloc{$proj}{pi} );
    print "\tProp: $name vs DB: ". $user->name ."\n";
    if ($piuser->email ne $user->email) {
      print "\t---Discrepant--- email: '".$piuser->email ."'[prop] vs. '".
	$user->email ."'[DB]\n";

      # Set the email
      #$user->email( $piuser->email );
      #OMP::UserServer->updateUser( $user );
    }

  } else {
    print "*** NOT IN DATABASE ***: $name \n";

    # Play it safe and store for later
    push(@newuser,{userid=>$piuser->infer_userid,name=> $name, 
		   email=>$piuser->email});

  }

}

# print out user details
for my $u (@newuser) {
  print $u->{userid},",",$u->{name},",",$u->{email},"\n";
}

exit;
