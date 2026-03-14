package OMP::Info::Comment;

=head1 NAME

OMP::Info::Comment - a comment

=head1 SYNOPSIS

    use OMP::Info::Comment;

    $resp = OMP::Info::Comment->new(
        author => $user,
        text => $text,
        date => $date);

    $resp = OMP::Info::Comment->new(
        author => $user,
        text => $text,
        status => OMP__DONE_DONE);

    $body = $resp->text;
    $user = $resp->author;

    $tid = $resp->tid;

=head1 DESCRIPTION

This is used to attach comments to C<OMP::Info::MSB> and C<OMP::Info::Obs>
objects. Multiple comments can be stored in each of these objects.

=cut

use 5.006;
use warnings;
use strict;
use Carp;

use OMP::Constants qw/:fb/;
use OMP::Display;
use OMP::Error;
use Time::Piece qw/:override/;

our $VERSION = '2.000';

use base qw/OMP::Info/;

# Overloading
use overload '""' => "stringify";

# Feedback message status, in descending priority order.
# (Excluding OMP__FB_DELETE.)
my @DATA_FB_STATUS = (
    [OMP__FB_IMPORTANT(), {
        name => 'Important',
    }],
    [OMP__FB_INFO(), {
        name => 'Info',
    }],
    [OMP__FB_SUPPORT(), {
        name => 'Support',
    }],
    [OMP__FB_HIDDEN(), {
        name => 'Hidden',
    }],
);

# Feedback message types.
my @DATA_FB_TYPE = (
    [OMP__FB_MSG_COMMENT(), {
        name => 'Comment',
    }],
#   [OMP__FB_MSG_DATA_OBTAINED(), {
#       # Never used?
#       name => 'Data obtained',
#   }],
    [OMP__FB_MSG_DATA_REQUESTED(), {
        name => 'Data requested',
    }],
    [OMP__FB_MSG_FIRST_ACCEPTED_MSB_ON_NIGHT(), {
        name => 'First MSB of night accepted',
    }],
    [OMP__FB_MSG_MSB_OBSERVED(), {
        name => 'MSB observed',
    }],
    [OMP__FB_MSG_MSB_UNOBSERVED(), {
        name => 'MSB undone',
    }],
    [OMP__FB_MSG_MSB_ALL_OBSERVED(), {
        name => 'MSB removed',
    }],
    [OMP__FB_MSG_MSB_UNREMOVED(), {
        name => 'MSB unremoved',
    }],
#   [OMP__FB_MSG_MSB_SUMMARY(), {
#       # Never used?
#       name => 'MSB summary',
#   }],
    [OMP__FB_MSG_MSB_SUSPENDED(), {
        # (Not used for JCMT)
        name => 'MSB suspended',
    }],
    [OMP__FB_MSG_PASSWD_ISSUED(), {
        name => 'Password issued',
    }],
    [OMP__FB_MSG_PROJECT_ENABLED(), {
        name => 'Project enabled',
    }],
    [OMP__FB_MSG_PROJECT_DISABLED(), {
        name => 'Project disabled',
    }],
    [OMP__FB_MSG_PROJECT_ALTERED(), {
        name => 'Project altered',
    }],
    [OMP__FB_MSG_SP_DELETED(), {
        name => 'Program deleted',
    }],
    [OMP__FB_MSG_SP_RETRIEVED(), {
        name => 'Program retrieved',
    }],
    [OMP__FB_MSG_SP_SUBMITTED(), {
        name => 'Program submitted',
    }],
    [OMP__FB_MSG_TIME_ADJUST_CONFIRM(), {
        name => 'Time adjusted',
    }],
#   [OMP__FB_MSG_TIME_NONE_SPENT(), {
#       # Never used?
#       name => 'No time spent',
#   }],
);

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new comment object.
The comment must ideally be supplied in the constructor but this is
not enforced. "author", "status", "tid" and "date" are optional.


    $resp = OMP::Info::Comment->new(
        author => $author,
        text => $text,
        status => 1,
    );

If it is not specified the current date will be used. The date must be
supplied as a C<Time::Piece> object and is assumed to be UT. The tid can
be undefined.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $comm = $class->SUPER::new(@_);

    # $comm->_populate();

    # Return the object
    return $comm;
}

=back

=head2 Create Accessor Methods

Create the accessor methods from a signature of their contents.

=cut

__PACKAGE__->CreateAccessors(
    _text => '$',
    author => 'OMP::User',
    _date => 'Time::Piece',
    preformatted => '$',
    private => '$',
    status => '$',
    runnr => '$',
    tid => '$',
    instrument => '$',
    telescope => '$',
    startobs => 'Time::Piece',
    obsid => '$',
    relevance => '$',
    id => '$',
    is_time_gap => '$',
    entrynum => '$',
    program => '$',
    projectid => '$',
    sourceinfo => '$',
    subject => '$',
    type => '$',
);

=head2 Accessor methods

=over 4

=item B<text>

Text content forming the comment. Should be in plain text.

    $text = $comm->text;
    $comm->text($text);

Returns empty string if text has not been set. Strips whitespace
from beginning and end of text when used as a constructor.

=cut

sub text {
    my $self = shift;
    if (@_) {
        my $text = shift;
        if (defined $text) {
            $text =~ s/^\s+//s;
            $text =~ s/\s+$//s;
        }
        $self->_text($text);
    }

    return (defined $self->_text ? $self->_text : '');
}

=item B<date>

Date the comment was filed. Must be a Time::Piece object.

    $date = $comm->date;
    $comm->date($date);

If the date is not defined when the C<Info::Comment> object
is created, it will default to the current time.

=cut

sub date {
    my $self = shift;
    if (@_) {
        my $date = shift;
        $self->_date($date);
    }

    unless (defined($self->_date)) {
        my $new = gmtime();
        $self->_date($new);
    }

    return $self->_date;
}

=item B<typeText>

Get description of the type of this message, or of the given type number.

=cut

sub typeText {
    my $self = shift;
    my $type = (ref $self) ? $self->type : (@_ ? shift : undef);

    foreach (@DATA_FB_TYPE) {
        return $_->[1]->{'name'} if $_->[0] == $type;
    }

    return undef;
}

=item B<statusText>

Get description of the status of this message, or of the given status number.

=cut

sub statusText {
    my $self = shift;
    my $status = (ref $self) ? $self->status : (@_ ? shift : undef);

    foreach (@DATA_FB_STATUS) {
        return $_->[1]->{'name'} if $_->[0] == $status;
    }

    return undef;
}

=back

=head2 General Methods

=over 4

=item B<stringify>

Convert comment to plain text for quick display.
This is the default stringification overload.

Just returns the comment text.

=cut

sub stringify {
    my $self = shift;
    return $self->text;
}

=item B<summary>

Summary of the object in different formats (XML, text, hash).

    $xml = $comm->summary('xml');

=cut

sub summary {
    my $self = shift;
    my $format = lc(shift);

    $format = 'xml' unless $format;

    my @order = qw/status date author tid text/;
    # Create hash
    my %summary;
    for (@order) {
        $summary{$_} = $self->$_();
    }

    if ($format eq 'hash') {
        return (wantarray ? %summary : \%summary);
    }

    if ($format eq 'text') {
        my $out = '';

        for (@order) {
            $out .= sprintf "%7s: %s\n", $_, $summary{$_};
        }

        return $out;
    }

    if ($format eq 'xml') {
        my $xml = "<SpComment>\n";

        for my $key (keys %summary) {
            next if $key =~ /^_/;
            next unless defined $summary{$key};

            $xml .= sprintf "<$key>%s</$key>\n", OMP::Display::escape_entity($summary{$key});
        }

        $xml .= "</SpComment>\n";

        return $xml;
    }
    else {
        throw OMP::Error::FatalError("Unknown format: $format");
    }
}

=back

=head2 Class Methods

=over 4

=item B<get_fb_status_options>

Get an array of pairs of feedback status value and label, in priority order.

=cut

sub get_fb_status_options {
    my $class = shift;
    my %opt = @_;

    return [map {
        [$_->[0], $_->[1]->{'name'}]
    } @DATA_FB_STATUS];
}

=item B<get_fb_type_options>

Get an array of pairs of feedback message type value and label, in order.

=cut

sub get_fb_type_options {
    my $class = shift;
    my %opt = @_;

    return [map {
        [$_->[0], $_->[1]->{'name'}]
    } @DATA_FB_TYPE];
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::Info::Obs>, C<OMP::Fault>, C<OMP::User>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2004 Particle Physics and Astronomy Research
Council. Copyright (C) 2007 Science and Technology Facilities Council.
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
