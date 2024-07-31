package OMP::CGIComponent::ShiftLog;

=head1 NAME

OMP::CGIComponent::ShiftLog - CGI functions for the shiftlog tool

=head1 SYNOPSIS

    use OMP::CGIComponent::ShiftLog;

    my $verified = $comp->parse_query();

    my $commments = $comp->get_shift_comments($verified);

=head1 DESCRIPTION

This module provides routines used for CGI-related functions for
shiftlog - variable verification, form creation, comment
submission, etc.

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use OMP::DateTools;
use Scalar::Util qw/blessed/;
use Time::Piece;
use Time::Seconds;

use OMP::Query::Shift;
use OMP::DB::Shift;
use OMP::Error qw/:try/;

use base qw/OMP::CGIComponent/;

our $VERSION = '2.000';

=head1 Routines

=over 4

=item B<parse_query>

Converts the values submitted in a query into a hash
for easier parsing later.

    $parsed_query = $comp->parse_query();

This function will return a hash reference.

=cut

sub parse_query {
    my $self = shift;

    my $q = $self->cgi;
    my $vars = $q->Vars;
    my %return = ();

    # Telescope. This is a string made up of word characters.
    my $telescope = $self->page->decoded_url_param('telescope');
    if ($telescope) {
        ($return{'telescope'} = $telescope) =~ s/\W//ag;
    }

    # Time Zone for entry. This is either UT or HST. Defaults to HST.
    if (exists($vars->{'entryzone'})) {
        if ($vars->{'entryzone'} =~ /ut/i) {
            $return{'entryzone'} = 'UT';
        }
        else {
            $return{'entryzone'} = 'HST';
        }
    }
    else {
        $return{'entryzone'} = 'HST';
    }

    # Date. This is in yyyy-mm-dd format. If it is not set, it
    # will default to the current UT date.
    my $date = $self->page->decoded_url_param('utdate');
    if ($date) {
        $return{'date'} = OMP::DateTools->parse_date($date);
    }
    else {
        $return{'date'} = gmtime;
    }

    # Time. This is in hh:mm:ss or hhmmss format. If it is not set, it
    # will default to the current local time.
    if (exists($vars->{'time'}) && $vars->{'time'} =~ /(\d\d):?(\d\d):?(\d\d)?/a) {
        $return{'time'} = join ':', $1, $2, ($3 // '00');
    }
    else {
        $return{'time'} = '';
    }

    # Text. Anything goes, but leading/trailing whitespace is stripped.
    if (exists($vars->{'text'})) {
        ($return{'text'} = $vars->{'text'}) =~ s/^\s+//s;
        $return{'text'} =~ s/\s+$//s;
    }

    return \%return;
}

=item B<get_shift_comments>

Gets shift comments for a given date.

    my $comments = $comp->get_shift_comments($verified);

The first argument is a hash reference to a verified
query (see B<parse_query>),

=cut

sub get_shift_comments {
    my $self = shift;
    my $v = shift;

    return unless defined $v->{'telescope'};
    return unless defined $v->{'date'};

    my $ut = $v->{'date'};
    $ut = $ut->ymd if blessed $ut;
    my $telescope = $v->{'telescope'};

    # Form the query.
    my $query = OMP::Query::Shift->new(HASH => {
        date => {delta => 1, value => $ut},
        telescope => $telescope,
    });

    # Grab the results.
    my $sdb = OMP::DB::Shift->new(DB => $self->database);
    my @result = $sdb->getShiftLogs($query);

    # At this point we have an array of relevant Info::Comment objects,
    # so return them.
    return \@result;
}

=item B<submit_comment>

Submit a comment to the database.

    $comp->submit_comment($verified);

The only argument is a hash reference to a verified
query (see B<parse_query>).

=cut

sub submit_comment {
    my $self = shift;
    my $v = shift;

    return unless defined $v->{'text'};

    my $telescope = $v->{'telescope'};
    my $entryzone = $v->{'entryzone'};
    my $date = $v->{'date'}->ymd;
    my $time = $v->{'time'};
    my $text = $v->{'text'};

    my $userobj = $self->auth->user;

    # Form the date.
    if ($time and $time =~ /(\d\d):(\d\d):(\d\d)/a) {
        my ($hour, $minute, $second) = ($1, $2, $3);

        # Convert the time zone to UT, if necessary.
        if ($entryzone =~ /hst/i) {
            $hour += 10;
            $hour %= 24;
        }
        $time = join ':', $hour, $minute, $second;
    }
    else {
        my $timeobj = gmtime;
        $time = $timeobj->hms;
    }
    my $datetime = Time::Piece->strptime("$date $time", '%Y-%m-%d %T');

    # Create an OMP::Info::Comment object.
    my $comment = OMP::Info::Comment->new(
        author => $userobj,
        text => $v->{'text'},
        date => $datetime,
    );

    # Store the comment in the database.
    my $sdb = OMP::DB::Shift->new(DB => $self->database);
    $sdb->enterShiftLog($comment, $telescope);
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGIPage::ShiftLog>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
