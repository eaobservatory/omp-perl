#!/local/perl/bin/perl

=head1 NAME

setaffiliationalloc - Set affiliation allocation

=head1 SYNOPSIS

  perl admin/setaffiliationalloc.pl < allocation.csv

=head1 DESCRIPTION

Sets the allocation for affiliations.  Accepts a set of
affiliations and allocations on standard input, where each line
should contain a semester identifier, affiliation code and
allocation.

=cut

use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
  $ENV{OMP_CFG_DIR} = File::Spec->catdir( OMPLIB, "../cfg" )
    unless exists $ENV{OMP_CFG_DIR};
};

use OMP::DBServer;
use OMP::ProjAffiliationDB;

my $affiliation_db = new OMP::ProjAffiliationDB(
    DB => OMP::DBServer->dbConnection());

while (<>) {
    chomp;
    my ($semester, $affiliation, $allocation) = split ',';
    $affiliation_db->set_affiliation_allocation(
        $semester, $affiliation, $allocation);
}

__END__

=head1 COPYRIGHT

Copyright (C) 2017 East Asian Observatory. All Rights Reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=cut
