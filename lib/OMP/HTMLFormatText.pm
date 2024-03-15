package OMP::HTMLFormatText;

=head1 NAME

OMP::HTMLFormatText - Local subclass of HTML::FormatText

=head1 DESCRIPTION

This is a subclass of C<HTML::FormatText> which limits the width of the
rule generated by the E<lt>hrE<gt> HTML element.  This is to allow a very
wide text width to be specified (via right margin) such that the output
text can be wrapped separately.

Separate wrapping might help avoid some of the issues mentioned in
fault 20181130.008.

=cut

use parent HTML::FormatText;

sub hr_start {
    my $self = shift;

    # Save "rm" (right margin) value.
    my $rm = $self->{'rm'};

    # Set "rm" to give a width of 8, then call the superclass method.
    $self->{'rm'} = $self->{'lm'} + 8;
    $self->SUPER::hr_start(@_);

    # Restore "rm".
    $self->{'rm'} = $rm;
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

=cut