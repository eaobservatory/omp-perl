#!perl

use Test::More tests => 31;
use strict;
require_ok("OMP::User");

# see if we can guess some user ids
my %guessed = (
	       JENNESST => " Tim Jenness ",
	       ECONOMOUF => "Frossie Economou",
	       MORIARTYSCHIEVENG => "Gerald Moriarty-Schieven",
	       PERSONA => "A. Person Jr",
	       PERSONB => "Person Sr, B",
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
  is(OMP::User->infer_userid( $guessed{$userid} ), $userid, "Infer userid" );
}


# Now extract User information from emails
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

  my $emailuser = OMP::User->extract_user_from_email( $test->{email} );
  my $hrefuser = OMP::User->extract_user_from_href( $test->{href} );

  for my $user ($emailuser, $hrefuser) {
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
