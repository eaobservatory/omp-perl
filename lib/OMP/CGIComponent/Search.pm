package OMP::CGIComponent::Search;

=head1 NAME

OMP::CGIComponent::Search - CGI functions relating to search operations

=head1 SYNOPSIS

    use OMP::CGIComponent::Search;

    $search = OMP::CGIComponent::Search->new(page => $page);

=cut

use strict;
use warnings;

use Carp;
use List::Util qw/min max/;
use Time::Piece;
use Time::Seconds qw/ONE_DAY/;

use OMP::DateTools;
use OMP::Display;
use OMP::DB::User;

use parent qw/OMP::CGIComponent/;

=head1 METHODS

=over 4

=item read_search_common

Read common search values from CGI parameters.

    %values = $search->read_search_common();

=cut

sub read_search_common {
    my $self = shift;

    my $q = $self->cgi;

    my %values = ();

    $values{'text_boolean'} = ($q->param('text_boolean') ? 1 : 0);

    foreach (qw/text period userid mindate maxdate days/) {
        my $val = $q->param($_);
        $values{$_} = $val if defined $val;
    }

    return %values;
}

=item read_search_sort

Read C<sort_by> and C<sort_order> CGI parameters.

    %values = $search->read_search_sort();

=cut

sub read_search_sort {
    my $self = shift;

    my $q = $self->cgi;

    return (
        sort_by => (scalar $q->param('sort_by')),
        sort_order => (scalar $q->param('sort_order')),
    );
}

=item common_search_hash

Prepare database query fragment for common search parameters.

    ($message, \%hash) = $search->common_search_hash(\%values, $authorfield);

=cut

sub common_search_hash {
    my $self = shift;
    my $values = shift;
    my $authorfield = shift;

    my %hash;
    my $message = undef;

    if ($values->{'text'}) {
        $hash{'text'} = $values->{'text_boolean'}
            ? {value => $values->{'text'}, mode => 'boolean'}
            : $values->{'text'}
    }
    else {
        $message = 'No query text specified.';
    }

    if ($values->{'userid'}) {
        if ($values->{'userid'} =~ /^([A-Z]+[0-9]*)$/) {
            $hash{$authorfield} = $1;
        }
        else {
            $message = 'Invalid user ID.';
        }
    }

    if ($values->{'period'} eq 'arbitrary') {
        my ($mindate, $maxdate) = map {
            my $datestr = $values->{$_};
            unless ($datestr) {
                undef;
            }
            elsif ($datestr !~ /^\d{8}$/a and $datestr !~ /^\d\d\d\d-\d\d-\d\d$/a) {
                $message = 'Date "' . $datestr . '" not understood.';
                undef;
            }
            else {
                OMP::DateTools->parse_date($datestr);
            }
        } qw/mindate maxdate/;

        if ($mindate or $maxdate) {
            my %datehash;
            if ($mindate) {
                $datehash{'min'} = $mindate->ymd;
            }
            if ($maxdate) {
                $maxdate += ONE_DAY;
                $datehash{'max'} = $maxdate->ymd;
            }
            $hash{'date'} = \%datehash;
        }
    }
    elsif ($values->{'period'} eq 'days') {
        my $days = $values->{'days'};
        if ($days) {
            unless ($days =~ /^\d+$/) {
                $message = 'Day range "' . $days . '" not understood.';
            }
            else {
                my $t = gmtime;
                $t += ONE_DAY;
                $hash{'date'} = {delta => - $days, value => $t->ymd};
            }
        }
    }

    return ($message, \%hash);
}

=item sort_search_results

Sort the given list of search results.

    $results = $search->sort_search_results(\%values, $datefield, \@results);

=cut

sub sort_search_results {
    my $self = shift;
    my $values = shift;
    my $datefield = shift;
    my $results = shift;

    if ($values->{'sort_by'} eq 'date') {
        if ($values->{'sort_order'} eq 'ascending') {
            return [sort {$a->$datefield->epoch <=> $b->$datefield->epoch} @$results];
        }
        return [sort {$b->$datefield->epoch <=> $a->$datefield->epoch} @$results];
    }

    # Assume sort_by relevance.
    if ($values->{'sort_order'} eq 'ascending') {
        return [sort {$a->relevance() <=> $b->relevance()} @$results];
    }
    return [sort {$b->relevance() <=> $a->relevance()} @$results];
}

=item B<text_snippet>

Prepare a snippet of text representing a search result.

Can either operate on a comment (any object with C<text> and C<preformatted>
methods, such as C<OMP::Info::Comment>) or text and a preformatted flag.

    $snippet = $search->text_snippet($query, $comment);
    $snippet = $search->text_snippet($query, $text, $preformatted);

=cut

sub text_snippet {
    my $self = shift;
    my $query = shift;
    my $comment = shift;
    my ($text, $preformatted) = eval {$comment->can('text')}
        ? ($comment->text, $comment->preformatted)
        : ($comment, shift);
    my %opt = @_;

    my $html = $opt{'html'};
    my $context_chars = $opt{'context_chars'} || 140;
    my $max_length = $opt{'max_length'} || ($context_chars * 2);

    $text = OMP::Display->html2plain($text, {rightmargin => 2048})
        if $preformatted;

    return '' unless defined $text;
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+|\s+$//g;

    my $terms = _snippet_query_terms($query);
    return _snippet_trim($text, $max_length, $html) unless @$terms;

    my $matches = _snippet_matches($text, $terms);
    return _snippet_trim($text, $max_length, $html) unless @$matches;

    # Find the section of the text, expanded by the given amount of context,
    # which overlaps the most matches.
    my $best = undef;
    my $best_score = undef;
    foreach my $candidate (@$matches) {
        my $start = $candidate->[0] - $context_chars;
        my $end   = $candidate->[1] + $context_chars;

        my $score = 0;
        foreach my $match (@$matches) {
            $score ++ if $match->[0] < $end && $match->[1] > $start;
        }

        if ((not defined $best) or ($score > $best_score)) {
            $best = $candidate;
            $best_score = $score;
        }
    }

    my $snippet_start = max($best->[0] - $context_chars, 0);
    my $snippet_end   = min($best->[1] + $context_chars, length $text);

    if ($snippet_start > 0) {
        my $space = index($text, ' ', $snippet_start);
        $snippet_start = $space + 1 if $space >= 0 and $space < $best->[0];
    }

    if ($snippet_end < length $text) {
        my $space = rindex($text, ' ', $snippet_end);
        $snippet_end = $space if $space > $best->[1];
    }

    my $snippet = substr($text, $snippet_start, $snippet_end - $snippet_start);
    $snippet = '...' . $snippet if $snippet_start > 0;
    $snippet .= '...' if $snippet_end < length $text;

    # Return the snippet unless HTML format was requested.
    return $snippet unless $html;

    my $start_tag = exists $opt{'start_tag'} ? $opt{'start_tag'} : '<b>';
    my $end_tag   = exists $opt{'end_tag'} ? $opt{'end_tag'} : '</b>';

    # Search again for matches, but just in the extracted snippet.
    $matches = _snippet_matches($snippet, $terms);
    return OMP::Display::escape_entity($snippet) unless @$matches;

    my @result = ();
    my $pos = 0;

    foreach my $match (@$matches) {
        next if $match->[0] < $pos;

        push @result,
            OMP::Display::escape_entity(
                substr($snippet, $pos, $match->[0] - $pos)),
            $start_tag,
            OMP::Display::escape_entity(
                substr($snippet, $match->[0], $match->[1] - $match->[0])),
            $end_tag;

        $pos = $match->[1];
    }

    push @result, OMP::Display::escape_entity(substr($snippet, $pos));

    return join '', @result;
}

# Get an array of regular expressions matching the terms in the given query.

sub _snippet_query_terms {
    my $query = shift;
    return [] unless defined $query;

    my @terms;

    # Add quoted phases.
    while ($query =~ /"([^"]+)"/g) {
        my $phrase = $1;
        $phrase =~ s/\s+/ /g;
        $phrase =~ s/^\s+|\s+$//g;

        push @terms, $phrase if $phrase;
    }

    # Remove the quoted phrases from the query.
    $query =~ s/"[^"]+"//g;

    # Add remaining words.
    foreach my $token (split ' ', $query) {
        $token =~ s/[^-_'a-zA-Z0-9]+//g;

        push @terms, $token if $token;
    }

    # Check uniqueness, sort by decreasing length and convert to regular expressions.
    my %seen;
    return [
        map {my $quoted = quotemeta $_; qr/$quoted/i}
        sort {length($b) <=> length($a)}
        grep {not $seen{lc $_} ++}
        @terms];
}

# Get an array of [start, end] pairs of match locations within the given text.

sub _snippet_matches {
    my $text = shift;
    my $terms = shift;
    my @matches;

    foreach my $term (@$terms) {
        while ($text =~ /$term/g) {
            push @matches, [$-[0], $+[0]];
        }
    }

    @matches = sort {
        $a->[0] <=> $b->[0]
        || ($b->[1] - $b->[0]) <=> ($a->[1] - $a->[0])
    } @matches;

    my @non_overlapping;
    foreach my $match (@matches) {
        next if @non_overlapping && $match->[0] < $non_overlapping[-1]->[1];
        push @non_overlapping, $match;
    }

    return \@non_overlapping;
}

# Trim text to given maximum length and optionally escape HTML entities.

sub _snippet_trim {
    my ($text, $max_length, $html) = @_;

    if ($max_length < length $text) {
        my $cut = rindex($text, ' ', $max_length - 3);
        $cut = $max_length - 3 if $cut < 1;

        $text = substr($text, 0, $cut) . '...';
    }

    return OMP::Display::escape_entity($text) if $html;

    return $text;
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2023 East Asian Observatory
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
