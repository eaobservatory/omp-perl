package OMP::Info::Preview;

=head1 NAME

OMP::Info::Preview - Preview image information

=cut

use strict;
use warnings;

use base qw/OMP::Info::Base/;

use overload '""' => 'stringify';

__PACKAGE__->CreateAccessors(
    date => 'Time::Piece',
    date_modified => 'Time::Piece',
    group => '$',
    filename => '$',
    filesize => '$',
    instrument => '$',
    md5sum => '$',
    runnr => '$',
    size => '$',
    subscan_number => '$',
    subsystem_number => '$',
    suffix => '$',
    telescope => '$',
);

sub stringify {
    my $self = shift;

    return sprintf '%s: %s %d-%d-%s-%d %s %s %s %d, %d %s %s',
        $self->filename,
        $self->telescope,
        $self->date->ymd(''),
        $self->runnr,
        ($self->subscan_number // 'undef'),
        $self->subsystem_number,
        $self->instrument,
        ($self->group ? 'group' : 'obs'),
        $self->suffix,
        $self->size,
        $self->filesize,
        $self->md5sum,
        $self->date_modified->strftime('%FT%T');
}

1;

__END__

=head1 COPYRIGHT

Copyright (C) 2024 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA
