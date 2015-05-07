package OMP::CGIPage::SourcePlot;

=head1 NAME

OMP::CGIPage::SourcePlot - Plot source Elevation versus Time for JCMT/UKIRT
for objects associated with projects in the OMP DB.

=head1 DESCRIPTION

Perl wrapper to generate a 'Source Plot' for all objects of a
particular project in the OMP DB.  The actual plotting is
done by OMP::GetCoords::Plot module.

=cut

use strict;

use OMP::GetCoords::Plot qw/plot_sources/;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

=head1 Subroutines

=over 4

=item B<view_source_plot>

Creates a page allowing the user to select the source plotting options.

=cut

sub view_source_plot {
    my $q = shift;
    my %cookie = @_;

    _show_inputpage($q);
}

=item B<view_source_plot_output>

Outputs the source plot.

=cut

sub view_source_plot_output {
    my $q = shift;
    my %cookie = @_;

    #_show_inputpage($q);
    _show_plot($q);
}

=back

=head2 Internal Subroutines

=over 4

=item _show_inputpage

Prints the HTML input panel.

=cut

sub _show_inputpage {
    my $q = shift;

    print
        $q->p('Plot sources from an OMP project'),
        $q->start_form(),
        $q->table(
            $q->Tr([
                $q->td([
                    'UT date (YYYYMMDD)',
                    $q->textfield(-name => 'utdate', size => 16),
                    '[today]',
                ]),
                $q->td([
                    'Project(s)',
                    $q->textfield(-name => 'projid', size => 16),
                    'One or more separated by "@"',
                ]),
                $q->td([
                    'Object(s)',
                    $q->textfield(-name => 'object', size => 16),
                    '(Optional) One or more separated by "@".',
                ]),
                $q->td({-colspan => 3},
                    'Any planets in this list will always be plotted ' .
                    'and not matched against project sources.<br />' .
                    '"5planets" will plot Mars thru Neptune; '.
                    '"planets" will plot all 8; '.
                    '"solar" will add the Sun and Moon',
                ),
                $q->td({-colspan => 3}, 'Plot options'),
                $q->td('Source mode') . $q->td({-colspan => 2},
                    $q->radio_group(
                        -name => 'mode',
                        -values => ['All', 'Active', 'Completed'],
                        -default => 'Active',
                    ),
                ),
                $q->td('Plot type') . $q->td({-colspan => 2},
                    $q->popup_menu(
                        -name => 'ptype',
                        -values => ['TIMEEL', 'AZEL', 'TIMEAZ',
                                    'TIMEPA', 'TIMENA'],
                        -default => 'TIMEEL',
                        -labels => {
                            TIMEEL => 'Time_EL',
                            AZEL   => 'AZ_EL',
                            TIMEAZ => 'Time_AZ',
                            TIMEPA => 'Time_PA',
                            TIMENA => 'Time_NA',
                        },
                    ),
                ),
                $q->td('Grid') . $q->td({-colspan => 2},
                    $q->radio_group(
                        -name => 'agrid',
                        -values => ['0', '1'],
                        -default => '0',
                        -labels => {
                            0 => 'EL grid',
                            1 => 'Airmass grid',
                        },
                    ),
                ),
                $q->td('Label position') . $q->td({-colspan => 2},
                    $q->radio_group(
                        -name => 'label',
                        -values => ['curve', 'list'],
                        -default => 'curve',
                        -labels => {
                            curve => 'Along track',
                            list  => 'List on side',
                        },
                    )
                ),
            ]),
        ),
        $q->p(
            $q->hidden(-name => 'show_output', -value => 'true'),
            $q->submit(-value => 'Plot sources')),
        $q->end_form();
}

=item _show_plot

Prints HTML to show the source plot.

=cut

sub _show_plot {
    my $q = shift;

    my $projid = "";
    my $utdate = "";
    my $object = "";
    my $mode   = "";
    my $ptype  = "";
    my $agrid  = "";
    my $tzone  = "";
    my $labpos = "";
    my @msg    = ();

    my $proj = $q->param('projid');
    $proj =~ /^([\w\/\$\.\_\@]+)$/ && ($projid = $1) || (do {
           $projid = "";
           push @msg, "***ERROR*** must specify a project!";
        } );

    my $utd = $q->param('utdate');
    $utd =~ /^(\d{8})$/ && ($utdate = $1) || (do {
           $utdate = "";
           if ($utd ne "") {
             push @msg, "***ERROR*** date format: '$utd' incorrect (YYYYMMDD)!";
           }
        } );

    my $objs = $q->param('object');
    $objs =~ /^([\w\/\$\.\_\@\"\'\s]+)$/ && ($object = $1) || ($object = "");

    my $mod = $q->param('mode');
    $mod =~ /^([\w\+\-\.\_]+)$/ && ($mode = $1) || ($mode = "");
    $mode =~ s/\'//g;
    $mode =~ s/\ /\\\+/g;

    my $ptyp = $q->param('ptype');
    $ptyp =~ /^([\w\+\-\.\_]+)$/ && ($ptype = $1) || ($ptype = "");
    $ptype =~ s/\'//g;
    $ptype =~ s/\ /\\\+/g;

    my $air = $q->param('agrid');
    $air =~ /^([\w\+\-\.\_]+)$/ && ($agrid = $1) || ($agrid ="");
    $agrid =~ s/\'//g;
    $agrid =~ s/\ /\\\+/g;

    my $tzon = $q->param('tzone');
    $tzon =~ /^([\w\+\-\.\_]+)$/ && ($tzone = $1) || ($tzone = "");
    $tzone =~ s/\'//g;
    $tzone =~ s/\ /\\\+/g;

    my $lpos = $q->param('label');
    $lpos =~ /^([\w\+\-\.\_]+)$/ && ($labpos = $1) || ($labpos = "");
    $labpos =~ s/\'//g;
    $labpos =~ s/\ /\\\+/g;

    if (@msg) {
        print $q->p(@msg);
    }
    else {
        # Open catalog and extract object from project to temporary catalog

        my %opt = (
            proj => $projid,
        );

        # Option to specify source not implemented yet.

        $opt{'ut'} = $utdate    if (defined $utdate && $utdate ne "");
        $opt{'obj'} = $object   if (defined $object && $object ne "");
        $opt{'mode'} = $mode    if (defined $mode && $mode ne "");
        $opt{'ptype'} = $ptype  if (defined $ptype && $ptype ne "");
        $opt{'agrid'} = $agrid  if (defined $agrid && $agrid ne "");
        $opt{'label'} = $labpos if (defined $labpos && $labpos ne "");

        print $q->header(-type => 'image/png');

        plot_sources(
            output => '-',
            hdevice => '/PNG',
            %opt,
        );

        #print $q->h2($projid),
        #      $q->p($q->img({src => '', alt => 'OMP source plot'}));
    }
}

1;

__END__

=back

=cut

=head1 AUTHOR

Remo Tilanus, Joint Astronomy Centre E<lt>r.tilanus@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
Copyright (C) 2015 East Asian Observatory.
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
