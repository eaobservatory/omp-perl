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

use OMP::CGIComponent::CaptureImage;
use OMP::CGIComponent::Helper qw/url_absolute/;
use OMP::GetCoords::Plot qw/plot_sources/;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use base qw/OMP::CGIPage/;

=head1 Subroutines

=over 4

=item B<view_source_plot>

Creates a page allowing the user to select the source plotting options.

=cut

sub view_source_plot {
    my $self = shift;

    my $q = $self->cgi;;

    unless ($q->param('submit_plot')) {
        return $self->_show_inputpage({
            proj => (scalar $q->param('project')),
        });
    }

    my ($messages, $plot, $opt) = $self->_show_plot();

    return {
        %{$self->_show_inputpage($opt)},
        messages => $messages,
        plot => $plot,
    }
}

=back

=head2 Internal Subroutines

=over 4

=item _show_inputpage

Prints the HTML input panel.

=cut

sub _show_inputpage {
    my $self = shift;
    my $opt = shift;

    my $q = $self->cgi;;

    return {
        target => url_absolute($q),
        ptypes => [
            [TIMEEL => 'Time-EL'],
            [AZEL   => 'AZ-EL'],
            [TIMEAZ => 'Time-AZ'],
            [TIMEPA => 'Time-PA'],
            [TIMENA => 'Time-NA'],
        ],
        labels => [
            [curve => "Along track"],
            [list => "List on side"],
        ],
        'values' => $opt,
    };
}

=item _show_plot

Prints HTML to show the source plot.

=cut

sub _show_plot {
    my $self = shift;

    my $q = $self->cgi;

    my $projid = "";
    my $utdate = "";
    my $object = "";
    my $mode   = "";
    my $ptype  = "";
    my $agrid  = "";
    my $labpos = "";
    my @msg    = ();

    my $proj = $q->param('project');
    $proj =~ /^([\w\/\$\.\_\@]+)$/a && ($projid = $1) || (do {
           $projid = "";
           push @msg, "Error: must specify a project!";
        } );

    my $utd = $q->param('utdate');
    $utd =~ /^(\d{8})$/a && ($utdate = $1) || (do {
           $utdate = "";
           if ($utd ne "") {
             push @msg, "Error: date format: '$utd' incorrect (YYYYMMDD)!";
           }
        } );

    my $objs = $q->param('object');
    $objs =~ /^([\w\/\$\.\_\@\"\'\s]+)$/a && ($object = $1) || ($object = "");

    my $mod = $q->param('mode');
    $mod =~ /^([\w\+\-\.\_]+)$/a && ($mode = $1) || ($mode = "");
    $mode =~ s/\'//g;
    $mode =~ s/\ /\\\+/g;

    my $ptyp = $q->param('ptype');
    $ptyp =~ /^([\w\+\-\.\_]+)$/a && ($ptype = $1) || ($ptype = "");
    $ptype =~ s/\'//g;
    $ptype =~ s/\ /\\\+/g;

    my $air = $q->param('agrid');
    $air =~ /^([\w\+\-\.\_]+)$/a && ($agrid = $1) || ($agrid ="");
    $agrid =~ s/\'//g;
    $agrid =~ s/\ /\\\+/g;

    my $lpos = $q->param('label');
    $lpos =~ /^([\w\+\-\.\_]+)$/a && ($labpos = $1) || ($labpos = "");
    $labpos =~ s/\'//g;
    $labpos =~ s/\ /\\\+/g;

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

    if (@msg) {
        return (\@msg, undef, \%opt)
    }

    my $capture = new OMP::CGIComponent::CaptureImage(page => $self);

    return (
        [],
        $capture->capture_png_as_data(sub {
            plot_sources(
                output => '-',
                hdevice => '/PNG',
                %opt,
            );
        }),
        \%opt);
}

1;

__END__

=back

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
