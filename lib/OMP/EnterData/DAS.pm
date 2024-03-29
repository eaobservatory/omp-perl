package OMP::EnterData::DAS;

use strict;
use warnings;

use parent 'OMP::EnterData::ACSIS';

=head1 NAME

OMP::EnterData::DAS - DAS specific methods

=head1 SYNOPSIS

    # Create new object, with specific header dictionary.
    my $enter = OMP::EnterData::DAS->new();

    my $name = $enter->instrument_name();

    my @cmd = $enter->get_bound_check_command;
    system(@cmd) == 0
        or die "Problem with running bound check command for $name.";

    # Use table in a SQL later.
    my $table = $enter->instrument_table();


=head1 DESCRIPTION

JAS::EnterData::DAS is a object oriented module, having instrument specific
methods.

It inherits from L<OMP::EnterData::ACSIS>.

=head2 METHODS

=over 4

=cut

=item B<new>

Constructor, returns an I<OMP::EnterData::DAS> object.

    $enter = OMP::EnterData::DAS->new();

Currently, no extra arguments are handled.

=cut

sub new {
    my ($class, %args) = @_;

    my $obj = $class->SUPER::new(%args);
    return bless $obj, $class;
}

=item B<instrument_name>

Returns the name of the backend involved.

    $name = $enter->instrument_name();

=cut

sub instrument_name {
    return 'DAS';
}


=item B<raw_basename_regex>

Returns the regex to match base file name, with array, date and run
number captured ...

    qr{ [ah]
        (\d{8})
        _
        (\d{5})
        _\d{2}_\d{4}[.]sdf
      }x;

    $re = OMP::EnterData::DAS->raw_basename_regex();

=cut

sub raw_basename_regex {
    return
        qr{ \b
            [ah]
            ([0-9]{8})       # date,
            _
            ([0-9]{5})       # run number,
            _[0-9]{2}        # subsystem.
            _[0-9]{4}[.]sdf
            \b
          }x;
}

1;

__END__

=back

Copyright (C) 2013, Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place,Suite 330, Boston, MA  02111-1307,
USA

=cut
