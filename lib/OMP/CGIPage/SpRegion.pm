package OMP::CGIPage::SpRegion;

=head1 NAME

OMP::CGIPage::SpRegion - Save or plot the regions of a Science Program

=cut

use strict;
use warnings;

use OMP::SpRegion;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use PGPLOT;

use OMP::Error qw/:try/;
use OMP::General;
use OMP::DB::MSB;
use Starlink::AST::PGPLOT;
use Starlink::ATL::MOC qw/write_moc_fits/;

use base qw/OMP::CGIPage/;

=head1 METHODS

=over 4

=item B<view_region>

Creates a page allowing the user to select the output format for the regions,
or outputs the region file.

=cut

sub view_region {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    unless ($q->param('submit_output')) {
        return {
            title => 'Download or Plot Regions for ' . uc($projectid),
            target => $self->url_absolute(),
            selections => [
                [all => 'All observations'],
                [new => 'New observations'],
                [progress => 'Observations in progress'],
                [complete => 'Completed observations'],
            ],
            formats => [
                [stcs => 'STC-S file'],
                [ast => 'AST region file'],
                [fits => 'MOC FITS file'],
                [png => 'Plot as PNG image'],
            ],
        };
    }

    my %mime = (
        png => 'image/png',
        stcs => 'text/plain',
        fits => 'application/fits',
        ast => 'application/octet-stream'
    );

    my %types = map {$_ => 1} qw/all new progress complete/;

    # Check input

    die 'Invalid output format' unless $q->param('format') =~ /^(\w+)$/a;
    my $format = $1;
    die 'Unrecognised output format' unless exists $mime{$format};

    die 'Invalid output type' unless $q->param('type') =~ /^(\w+)$/a;
    my $type = $1;
    die 'Unrecognised output format' unless exists $types{$type};

    # Prepare region object, by fetching the SP and converting it.
    my $sp = undef;
    my $error = undef;
    try {
        my $db = OMP::DB::MSB->new(
            ProjectID => $projectid,
            DB => $self->database
        );
        $sp = $db->fetchSciProg(1);
    }
    catch OMP::Error::UnknownProject with {
        $error = "Science program for $projectid not present in the database.";
    }
    catch OMP::Error::SpTruncated with {
        $error = "Science program for $projectid is in the database but has been truncated.";
    }
    otherwise {
        my $E = shift;
        $error = "Error obtaining science program details for project $projectid: $E";
    };

    return $self->_write_error($error)
        if defined $error;

    return $self->_write_error(
        'The science program could not be fetched for this project.')
        unless defined $sp;

    my $region = OMP::SpRegion->new($sp);

    return $self->_write_error('No regions were found for this project.')
        unless defined $region;

    # Print the output.

    my %header = (-type => $mime{$format});
    $header{'-attachment'} = $projectid . '.' . $format
        unless $mime{$format} =~ /^image/;

    print $q->header(%header);

    if ($format eq 'png') {
        PGPLOT::pgbegin(0, '-/PNG', 1, 1);
        PGPLOT::pgwnad(0, 1, 0, 1);
        $region->plot_pgplot(type => $type);
        PGPLOT::pgend();
    }
    elsif ($format eq 'ast') {
        $region->write_ast(type => $type);
    }
    elsif ($format eq 'stcs') {
        $region->write_stcs(type => $type);
    }
    elsif ($format eq 'fits') {
        my $moc = $region->get_moc(type => $type, order => undef);
        write_moc_fits($moc, '-');
    }
    else {
        die 'Unrecognised format, not trapped by first check.';
    }

    return undef;
}

1;

__END__

=back

=cut
