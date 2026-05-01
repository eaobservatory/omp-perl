package OMP::Translator::Headers::ACSIS;

=head1 NAME

OMP::Translator::Headers::ACSIS - Derived header configuration for ACSIS

=head1 SYNOPSIS

    use OMP::Translator::Headers::ACSIS;
    $msbid = OMP::Translator::Headers::ACSIS->getMSBID($cfg, \%info);

=head1 DESCRIPTION

This class contains ACSIS specific header configurations. Methods
are invoked from the JCMT translator.

Some header values are determined through the invocation of methods
specified in the header template XML. These methods are flagged by
using the DERIVED specifier with a task name of TRANSLATOR.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use parent qw/OMP::Translator::Headers::Heterodyne/;

=head1 METHODS

=head2 Helper Methods

=over 4

=item B<default_project>

Returns default E&C project.

=cut

sub default_project {
    return "EC19";
}

=back

=head2 Translation Methods

The following methods are in the OMP::Translator::Headers::JCMT
namespace. They are all given the observation summary hash as argument
and the current Config object, and they return the value that should
be used in the header.

    $value = OMP::Translator::Headers::ACSIS->getProject($cfg, \%info);

An empty string will be recognized as a true UNDEF header value. Returning
undef is an error.

=over 4

=item B<getRPRecipe>

Reduce process recipe requires access to the file name used to read
the recipe This should be stored in the Cfg object.

=cut

sub getRPRecipe {
    my $self = shift;
    my $cfg = shift;

    # Get the acsis config
    my $acsis = $cfg->acsis;

    if (defined $acsis) {
        my $red = $acsis->red_config_list;

        if (defined $red) {
            my $file = $red->filename;

            if (defined $file) {
                # just give file name, not path
                return File::Basename::basename($file);
            }
        }
    }

    return '';
}

1;

__END__

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2007-2008 Science and Technology Facilities Council.
Copyright 2003-2007 Particle Physics and Astronomy Research Council.
All Rights Reserved.

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
