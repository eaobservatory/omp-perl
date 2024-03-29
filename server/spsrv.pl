#!/local/perl/bin/perl -XT

=head1 NAME

spsrv - Science Program Server

=head1 SYNOPSIS

    my $sp = SOAP::Lite->new(
        uri => 'https://www.eao.hawaii.edu/OMP::SpServer',
        proxy => 'https://www.whereever.edu/cgi-bin/spsrv.pl');

    $sp->storeProgram($xml, $password);

=head1 DESCRIPTION

This program implements a CGI-based SOAP server publishing the methods
found in the C<OMP::SpServer> perl class.

=cut

use 5.006;
use warnings;
use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
    my $retval = do './omp-srv-init.pl';
    unless ($retval) {
        warn "couldn't parse omp-srv-init.pl: $@" if $@;
        warn "couldn't do omp-srv-init.pl: $!" unless defined $retval;
        warn "couldn't run omp-srv-init.pl" unless $retval;
        exit;
    }
}

use OMP::SpServer;

use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to(qw/
    OMP::SpServer::SpInsertCat
    OMP::SpServer::fetchProgram
    OMP::SpServer::storeProgram
    OMP::SpServer::getOTVersionInfo
/)->options({compress_threshold => 500})->handle;

__END__

=head1 INSTALLATION

Copy this program into the CGI directory on your web server.

=head1 SEE ALSO

L<OMP::SpServer>

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
