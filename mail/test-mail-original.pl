#!/local/perl/bin/perl

use strict; use warnings; use Carp qw[ carp croak confess ];
use 5.016;
select \*STDERR ; $| = 1;
select \*STDOUT ; $| = 1;

our $VERSION = '0.00';

#use Getopt::Long qw[ :config gnu_compat no_ignore_case require_order ];
#use Pod::Usage;
use Data::Dumper qw[ Dump ];

use JAC::Setup   qw[ omp ];

use OMP::User ;
use OMP::Mail::Original;
local $OMP::Mail::Original::DEBUG = 1;

my $flex = q[flex@eaobservatory.org];

my $some  = OMP::User->new( 'name'  => 'test-internal'
                          , 'email' => 'a.agarwal@eaobservatory.org'
                          );

my $mailer = OMP::Mail::Original->new();
my $mess = $mailer->build(  'to'   => [ $some ]
                          , 'from' => $some
                          , 'subject' => 'test mail, ' . lc( scalar localtime() )
                          , 'message' => qq[testing separate mailing code...\n]
                          , 'headers' => { 'Sender' => $flex }
                          );

warn Dumper( $mess );
# Send mail.
warn Dumper( $mailer->send( $mess ) );

__END__

=pod

=head1 NAME


=head1 SYNOPSIS


=head1  DESCRIPTION



=head2  OPTIONS

=over 2

=item *


=item *


=back

=head1 COPYRIGHT

Copyright (C) 2015 East Asian Observatory.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut


