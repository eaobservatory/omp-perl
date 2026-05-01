package OMP::Translator::Headers::Heterodyne;

=head1 NAME

OMP::Translator::Headers::Heterodyne - Base heterodyne derived header class

=head1 SYNOPSIS

    use parent qw/OMP::Translator::Headers::Heterodyne/;

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Error;

use parent qw/OMP::Translator::Headers::JCMT/;

=head1 METHODS

=head2 Translation Methods

=over 4

=item B<getDRRecipe>

Default recipe can be supplied by the OT user or determined from context.

Uses the base class for the user supplied value.

=cut

sub getDRRecipe {
    my $self = shift;
    my $cfg = shift;
    my $info = shift;

    # See if the base class knows better
    my $recipe = $self->SUPER::getDRRecipe($cfg, $info);
    return $recipe if defined $recipe;

    # if there was no DR component we have to guess
    if ($info->{'MODE'} =~ /Pointing/) {
        $recipe = 'REDUCE_POINTING';
    }
    elsif ($info->{'MODE'} =~ /Focus/) {
        $recipe = 'REDUCE_FOCUS';
    }
    elsif ($info->{'MODE'} =~ /Skydip/) {
        $recipe = 'REDUCE_SKYDIP';
    }
    else {
        if ($info->{'continuumMode'}) {
            $recipe = 'REDUCE_SCIENCE_CONTINUUM';
        }
        else {
            $recipe = 'REDUCE_SCIENCE';
        }
    }

    $self->translator->output("Using DR recipe $recipe determined from context\n");

    return $recipe;
}

=item B<getNumMixers>

Get the number of receptors (marked "ON" or "NEED").

=cut

sub getNumMixers {
    my $self = shift;
    my $cfg = shift;

    # Get the frontend
    my $fe = $cfg->frontend;
    throw OMP::Error::TranslateFail("Asked to determine number of mixers but no Frontend has been specified\n")
        unless defined $fe;

    my %mask = $fe->mask;
    my $count;
    for my $state (values %mask) {
        $count ++ if ($state eq 'ON' || $state eq 'NEED');
    }

    return $count;
}

=item B<getReferenceDec>

Reference position as sexagesimal string or offset

=cut

sub getReferenceDec {
    my $self = shift;
    my $cfg = shift;

    return $self->_get_reference_coord($cfg, 1, 'dec2000', 'el', 'EL');
}

=item B<getReferenceRA>

Reference position as sexagesimal string or offset

=cut

sub getReferenceRA {
    my $self = shift;
    my $cfg = shift;

    return $self->_get_reference_coord($cfg, 0, 'ra2000', 'az', 'AZ');
}

sub _get_reference_coord {
    my $self = shift;
    my $cfg = shift;
    my ($comp, $radec_acc, $azel_acc, $azel_name) = @_;

    # Get the TCS
    my $tcs = $cfg->tcs;

    my %allpos = $tcs->getAllTargetInfo;

    # check if SCIENCE == REFERENCE
    if (exists $allpos{'REFERENCE'}) {
        # Assume that for now since the OT enforces either an absolute position
        # or one relative to BASE as an offset that if we have an offset people
        # are offsetting and if we have just coords that we are using that explicitly
        my $refpos = $allpos{'REFERENCE'}->coords;
        my $offset = $allpos{'REFERENCE'}->offset;

        if (defined $offset) {
            my @off = $offset->offsets;
            return sprintf '[OFFSET] %s [%s]', $off[$comp]->arcsec, $offset->system;
        }
        else {
            if ($refpos->can($radec_acc)) {
                return "" . $refpos->$radec_acc;
            }
            elsif ($refpos->type eq 'FIXED') {
                return sprintf '%s (%s)', $refpos->$azel_acc, $azel_name;
            }
        }
    }

    # Want this to be an undef header
    return "";
}

=item B<getRefRecep>

Get the reference receptor.

=cut

sub getRefRecep {
    my $self = shift;
    my $cfg = shift;

    my $inst = $cfg->instrument_setup;
    throw OMP::Error::FatalError('Instrument configuration is not available')
        unless defined $inst;

    return scalar $inst->reference_receptor;
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
