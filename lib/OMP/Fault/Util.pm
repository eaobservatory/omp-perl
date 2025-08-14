package OMP::Fault::Util;

=head1 NAME

OMP::Fault::Util - Fault content manipulation

=head1 SYNOPSIS

    use OMP::Fault::Util;

    $text = OMP::Fault::Util->format_fault($fault, $bottompost);

=head1 DESCRIPTION

This class provides general functions for manipulating the components
of C<OMP::Fault> and C<OMP::Fault::Response> objects (and sometimes components
that are not necessarily part of an object yet) for display purposes
or for preparation for storage to the database or to an object.

=cut

use 5.006;
use warnings;
use strict;
use Carp;

use OMP::DateTools;
use OMP::Display;
use OMP::Config;

=head1 METHODS

=head2 General Methods

=over 4

=item B<format_fault>

Format a fault in such a way that it is readable in a mail viewer.  This
method retains the HTML in fault responses and uses HTML for formatting.

    $text = OMP::Fault::Util->format_fault($fault, $bottompost, [%opt]);

The first argument should be an C<OMP::Fault> object.  If the second argument
is true then responses are displayed in ascending order (newer responses appear
at the bottom).

Other options:

=over 4

=item max_entries

Maximum number of responses to show.

=back

=cut

sub format_fault {
    my $self = shift;
    my $fault = shift;
    my $bottompost = shift;
    my %opt = @_;

    my $max_entries = $opt{'max_entries'};

    my $faultid = $fault->id;

    # Get the fault system URL
    my $baseurl = OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir');

    # Set link to response page
    my $url = "$baseurl/viewfault.pl?fault=$faultid";

    my $responselink = "<a href=\"$url\">$url</a>";

    # Get the fault response(s)
    my @responses = $fault->responses;

    # Store fault meta info to strings
    my $system = $fault->systemText;
    my $type = $fault->typeText;
    my $loss = $fault->timelost;
    my $shifttype = $fault->shifttype;
    my $remote = $fault->remote;
    my $projects = $fault->projects;
    my $entryName = lc $fault->getCategoryEntryName;
    my $entryNameQualified = $fault->getCategoryEntryNameQualified;
    my $systemLabel = $fault->getCategorySystemLabel;

    # Don't show the status if there is only the initial filing and it is 'Open'
    my $status = $responses[1] || $fault->statusText !~ /open/i
        ? '<b>Status:</b> ' . $fault->statusText
        : '';

    my $faultdatetext;
    if ($fault->faultdate) {
        # Convert date to local time
        my $faultdate = localtime($fault->faultdate->epoch);

        # Now convert date to string for appending to time lost
        $faultdatetext = "hrs at " . OMP::DateTools->display_date($faultdate);
    }

    # Create the fault meta info portion of our message
    my $meta = sprintf "<pre>%-58s %s",
        "<b>${systemLabel}:</b> $system",
        "<b>Fault type:</b> $type";

    $meta .= sprintf "<br>%-58s %s",
        "<b>Shift type:</b> $shifttype",
        "<b>Remote status:</b> $remote"
        if $shifttype;

    $meta .= sprintf "<br>%-58s %s",
        "<b>Time lost:</b> $loss $faultdatetext", "$status";

    $meta .= '<br><b>Location:</b> ' . $fault->locationText()
        if $fault->location();

    $meta .= '<br><b>Projects:</b> '
        . (join ', ', sort {$a cmp $b} map {uc $_} @$projects)
        if scalar @$projects;

    $meta .= "</pre>";

    # Create the fault text
    my @faulttext;

    if ($responses[1]) {
        # Make it noticeable if this fault is urgent
        push @faulttext,
            "<div align=center><b>* * * * * URGENT * * * * *</b></div><br>"
            if $fault->isUrgent;

        # Include a response link at the top for convenience.
        push @faulttext,
            "To respond to this $entryName go to $responselink<br>--------------------------------<br><br>";

        my @order;
        my $heading = undef;
        unless (defined $max_entries and $max_entries < scalar @responses) {
            # If we aren't bottom posting arrange the responses in descending order
            @order = $bottompost ? @responses : reverse @responses;
        }
        else {
            @order = @responses[$bottompost
                ? (-$max_entries .. -1)
                : (reverse -$max_entries .. -1)];

            # Since our text is truncated by max_entries, prepare heading information.
            my $author = $fault->author->html;
            my $date = OMP::DateTools->display_date(
                scalar localtime($fault->filedate->epoch));
            $heading = "$entryNameQualified filed by $author on $date<br>";
        }

        push @faulttext,
            $heading,
            $meta,
            '(Additional messages hidden.)',
            '<br>================================================================================<br>'
            if defined $heading && $bottompost;

        my $i = 0;
        for (@order) {
            my $user = $_->author;
            my $author = $user->html;  # This is an html mailto
            my $date = localtime($_->date->epoch);  # convert date to localtime
            $date = OMP::DateTools->display_date($date);

            my $text = OMP::Display->format_html($_->text, $_->preformatted);

            $text = OMP::Display->replace_omp_links($text, complete_url => 1);

            # Add separator before each response except the first.
            if ($i ++) {
                push @faulttext,
                    '--------------------------------------------------------------------------------<br>';
            }

            if ($_->isfault) {
                push @faulttext,
                    "$entryNameQualified filed by $author on $date<br><br>";

             # The meta data should appear right after the initial filing unless
                # we are bottom posting in which case it appears right before
                if (! $bottompost) {
                    push @faulttext,
                        $text,
                        '<br>================================================================================<br>',
                        $meta,
                        '<br>';
                }
                else {
                    push @faulttext,
                        $meta,
                        '================================================================================<br>',
                        $text,
                        '<br>';
                }
            }
            else {
                push @faulttext,
                    "Response filed by $author on $date<br><br>$text<br>";
            }
        }

        push @faulttext,
            '================================================================================<br>',
            '(Additional messages hidden.)',
            '<br><br>', $heading, $meta, '<br>'
            if defined $heading && not $bottompost;
    }
    else {
        # This is an initial filing so arrange the message with the meta info first
        # followed by the initial report
        my $author = $responses[0]->author->html;  # This is an html mailto

        # Convert date to local time
        my $date = localtime($responses[0]->date->epoch);

        # now convert date to a string for display
        $date = OMP::DateTools->display_date($date);

        my $text = OMP::Display->format_html(
            $responses[0]->text, $responses[0]->preformatted);

        $text = OMP::Display->replace_omp_links($text, complete_url => 1);

        push @faulttext, "$entryNameQualified filed by $author on $date<br><br>";

        # Make it noticeable if this fault is urgent
        push @faulttext,
            "<div align=center><b>* * * * * URGENT * * * * *</b></div><br>"
            if $fault->isUrgent;

        push @faulttext,
            $meta,
            '<br>================================================================================<br>',
            $text,
            '<br>';
    }

    # Add the response link to the bottom of our message
    push @faulttext,
        "--------------------------------<br>To respond to this $entryName go to $responselink<br>";

    return join '', @faulttext;
}

=item B<compare>

Compare two C<OMP::Fault> or C<OMP::Fault::Response> objects.

    @diff = OMP::Fault::Util->compare($fault_a, $fault_b);

Takes two C<OMP::Fault> or C<OMP::Fault::Response> objects as the only arguments.
Returns a list containing the elements where the two objects differed.  The elements
are conveniently named after the accessor methods of each object type.  Some keys
are not included in the comparison.  For C<OMP::Response> objects only the text, author,
preformatted, timelost, faultdate, shifttype and remote keys are compared.
For C<OMP::Fault> objects the faultid keys are not compared.

=cut

sub compare {
    my $self = shift;
    my $obja = shift;
    my $objb = shift;

    my @diff;
    my @comparekeys;

    if (UNIVERSAL::isa($obja, "OMP::Fault")
            and UNIVERSAL::isa($objb, "OMP::Fault")) {
        # Comparing OMP::Fault objects
        @comparekeys = qw/
            subject system type urgency
            condition projects status
        /;

        push @comparekeys, qw/location/
            if $obja->faultHasLocation;
    }
    elsif (UNIVERSAL::isa($obja, "OMP::Fault::Response")
            and UNIVERSAL::isa($objb, "OMP::Fault::Response")) {
        # Comparing OMP::Fault::Response objects
        @comparekeys = qw/
            text author preformatted
            timelost faultdate shifttype remote
        /;
    }
    else {
        throw OMP::Error::BadArgs(
            "Both Arguments to compare must be of the same object type (that of either OMP::Fault or OMP::Fault::Response)\n");
        return;
    }

    for (@comparekeys) {
        my $keya;
        my $keyb;

        # Be more specific about what we want to compare in some cases
        if ($_ =~ /author/) {
            $keya = $obja->author->userid;
            $keyb = $objb->author->userid;
        }
        elsif ($_ =~ /projects/) {
            $keya = join(",", @{$obja->projects});
            $keyb = join(",", @{$objb->projects});
        }
        elsif ($_ =~ /faultdate/) {
            if ($obja->faultdate) {
                $keya = $obja->faultdate->epoch;
            }
            if ($objb->faultdate) {
                $keyb = $objb->faultdate->epoch;
            }
        }
        else {
            $keya = $obja->$_;
            $keyb = $objb->$_;
        }

        next if (! defined $keya and ! defined $keyb);

        if (! defined $keya and defined $keyb) {
            push @diff, $_;
        }
        elsif (! defined $keyb and defined $keya) {
            push @diff, $_;
        }
        elsif ($keya ne $keyb) {
            push @diff, $_;
        }
    }

    return @diff;
}

1;

__END__

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

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
