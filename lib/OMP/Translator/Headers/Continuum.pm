package OMP::Translator::Headers::Continuum;

=head1 NAME

OMP::Translator::Headers::Continuum - Base continuum derived header class

=head1 SYNOPSIS

    use parent qw/OMP::Translator::Headers::Continuum/;

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use parent qw/OMP::Translator::Headers::JCMT/;

=head1 METHODS

=head2 Translation Methods

=over 4

=item B<getDRRecipe>

Default recipe can be supplied by the OT user or determined from context.

Uses the base class for user-supplied values.

=cut

sub getDRRecipe {
    my $self = shift;
    my $cfg = shift;
    my $info = shift;

    # See if the base class knows better
    my $recipe = $self->SUPER::getDRRecipe($cfg, $info);
    return $recipe if defined $recipe;

    # Get the observation type and the mapping mode
    my $obstype = $info->{'obs_type'};
    my $mapmode = $info->{'mapping_mode'};
    my $has_fts = scalar grep {$_ =~ /^fts/} @{$info->{'inbeam'}};
    my $has_pol = scalar grep {$_ =~ /^pol/} @{$info->{'inbeam'}};

    # if there was no DR component we have to guess
    if ($obstype eq 'pointing') {
        $recipe = $has_fts ? 'REDUCE_FTS_POINTING' : 'REDUCE_POINTING';
    }
    elsif ($obstype eq 'focus') {
        $recipe = $has_fts ? 'REDUCE_FTS_FOCUS' : 'REDUCE_FOCUS';
    }
    elsif ($obstype eq 'skydip') {
        $recipe = "REDUCE_SKYDIP";
    }
    elsif ($obstype eq 'flatfield') {
        $recipe = "REDUCE_FLATFIELD";
    }
    elsif ($obstype eq 'setup') {
        $recipe = "REDUCE_SETUP";
    }
    elsif ($obstype eq 'array_tests') {
        $recipe = "ARRAY_TESTS";
    }
    elsif ($obstype eq 'noise') {
        $recipe = 'REDUCE_NOISE';
    }
    elsif ($mapmode eq 'scan') {
        $recipe = $has_pol ? "REDUCE_POL_SCAN" : "REDUCE_SCAN";
    }
    elsif ($mapmode eq 'stare' or $mapmode eq 'dream') {
        if ($has_fts) {
            $recipe = "REDUCE_FTS_SCAN";
        }
        elsif ($has_pol) {
            $recipe = "REDUCE_POL_STARE";
        }
        else {
            $recipe = "REDUCE_DREAMSTARE";
        }
    }
    else {
        OMP::Error::TranslateFail->throw(
            "Unexpected obs mode ($obstype/$mapmode)"
            . " when calculating DR recipe");
    }

    $self->translator->output("Using DR recipe $recipe determined from context\n");

    return $recipe;
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
