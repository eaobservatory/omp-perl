#!perl

use Test::More tests => 63;
use strict;
require_ok("OMP::User");


# Create a simply user object
my $user = new OMP::User( name => "Frossie Economou",
			  email => 'frossie@frossie.net',
			  userid => 'FROSSIE',
			);

isa_ok( $user, "OMP::User" );
is( $user->name, "Frossie Economou", "Check name");
is( $user->email, 'frossie@frossie.net', "Check email");
is( $user->userid, "FROSSIE", "Check userid");
is( $user->domain, "frossie.net", "Check email domain");
is( $user->addressee, "frossie", "Check email addressee");

# see if we can guess some user ids
my %guessed = (
	       VANDERHUCHTK => "Karel van der Hucht",
	       JENNESST => " Tim Jenness ",
	       ECONOMOUF => "Frossie Economou",
	       MORIARTYSCHIEVENG => "Gerald Moriarty-Schieven",
	       PERSONA => "A. Person Jr",
	       PERSONB => "Person Sr, B",
	       PERSONC => "Person Sr., C",
	       FULLERG => "Dr. G. Fuller",
	       STEVENSJ=> "Dr J. A. Stevens",
	       PERSOND => "Prof. D. Person",
	       PERSONE => "Mrs E. Person",
	       PERSONF => "Mr. F Person",
	       PERSONG => "Mrs. G. Person",
	       PERSONH => "Person, Ms. H",
	       PERSONI => "Person, Prof I",
	       ADAMSONA => "Adamson, Andy",
	       BARNUMP => 'P. T. Barnum',
	       VANBEETHOVENL => "Ludwig van Beethoven",
	       MOZARTW => 'Wolfgang Gottlieb Mozart',
	       LEGUINU => 'Ursula K Le Guin',
	       LEPERSONA => 'Le Person, A.',
	       CDEA    => 'A.B.CDE',
	       DELOREYK => 'K.Delorey',
	       DEWITTS => 'Shaun de Witt',
	      );

for my $userid (keys %guessed) {
  print "# $guessed{$userid}\n";
  is(OMP::User->infer_userid( $guessed{$userid} ), $userid, "Infer userid" );
}


# Now extract User information from emails and HTML
my @extract = (
	       {
		href => '<A href="mailto:timj@jach.hawaii.edu">Tim Jenness</a>',
		email => 'Tim Jenness <timj@jach.hawaii.edu>',
		output => new OMP::User( userid=> 'JENNESST',
					 name => 'Tim Jenness',
					 email => 'timj@jach.hawaii.edu'),
	       },
	       {
		href => '<A href="mailto:t.jenness@jach">t.jenness@jach</a>',
		email => 't.jenness@jach',
		output => new OMP::User( userid=> 'JENNESST',
					 name => 'T.Jenness',
					 email => 't.jenness@jach'),
	       },
	    );

for my $test ( @extract ) {

  # First explicitly
  my $emailuser = OMP::User->extract_user_from_email( $test->{email} );
  my $hrefuser = OMP::User->extract_user_from_href( $test->{href} );

  # then implictly
  my $guess1 = OMP::User->extract_user( $test->{email} );
  my $guess2 = OMP::User->extract_user( $test->{href} );


  for my $user ($emailuser, $hrefuser, $guess1, $guess2) {
    isa_ok($user, "OMP::User");

    if (defined $user) {
      # now loop over user information
      # and compare (all lower case)
      for my $method (qw/ userid name email /) {
	is( lc($user->$method), lc($test->{output}->$method), "Compare $method");
      }
    } else {
      for (1..3) {
	ok(0, "Did not get valid user");
      }
    }
  }
}
