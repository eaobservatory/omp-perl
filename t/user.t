#!perl

use Test::More tests => 13;
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
