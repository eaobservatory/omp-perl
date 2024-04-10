package OMP::Util::FITS;

=head1 NAME

OMP::Util::FITS - FITS header utilities for the OMP

=head1 SYNOPSIS

    use OMP::Util::FITS;

=head1 DESCRIPTION

This class provides routines for processing FITS header information.

=cut

use strict;
use warnings::register;

use JAC::Setup qw/hdrtrans/;

use Astro::FITS::HdrTrans;
use Astro::FITS::Header;
use List::MoreUtils qw/any all/;
use Scalar::Util qw/blessed/;

=head1 METHODS

=head2 Class methods

=over 4

=item B<merge_dupes>

Given an array of hashes containing header object, filename and
frameset, merge into a hash indexed by OBSID where headers have been
merged and filenames have been combined into arrays.

    $merged = OMP::Util::FITS->merge_dupes(@unmerged);

In the returned merged version, header hash item will contain an
Astro::FITS::Header object if the supplied entry in @unmerged was a
simple hash reference.

Input keys:

=over 4

=item header

Reference to hash or an Astro::FITS::Header object.

=item filename

Single filename. (optional)

=item frameset

Optional Starlink::AST frameset.

=back

If the 'filename' is not supplied yet a header translation reports
that FILENAME is available, the value will be stored from the
translation into the filename slot.

Output keys:

=over 4

=item header

Astro::FITS::Header object.

=item filenames

Reference to array of filenames.

=item frameset

Optional Starlink::AST frameset (from first in list).

=item obsidss_files

Hash of files indexed by obsidss.

=back

=cut

sub merge_dupes {
    my $class = shift;

    # Take local copies so that we can add information without affecting caller
    my @unmerged = map {
        {%$_}
    } @_;

    my %unique;
    for my $info (@unmerged) {
        # First need to work out which item corresponds to the unique observation ID
        # We do this via header translation. Since we can in principal have multiple
        # instruments we have to redetermine the class each time round the loop.

        # Convert fits header to hash if required
        my $hdr = $info->{header};
        if (blessed($hdr)) {
            tie my %header, ref($hdr), $hdr;
            $hdr = \%header;
        }
        else {
            # convert the header hash to a Astro::FITS::Header object so that we can easily
            # merge it later
            $info->{header} = Astro::FITS::Header->new(Hash => $hdr);
        }
        my $trans;

        eval {$trans = Astro::FITS::HdrTrans::determine_class($hdr, undef, 1);};
        if ($@) {
            warn sprintf "Skipped '%s' due to: %s\n", $info->{'filename'}, $@;
        }

        next unless $trans;

        my $obsid = $trans->to_OBSERVATION_ID($hdr, $info->{frameset});

        # check for translated filename
        unless (exists $info->{filename}) {
            my $filename = $trans->to_FILENAME($hdr);
            if (defined $filename) {
                $info->{filename} = $filename;
            }
        }

        # Keep the obsidss around (assume only a single one from a row)
        if ($trans->can("to_OBSERVATION_ID_SUBSYSTEM")) {
            my $obsidss = $trans->to_OBSERVATION_ID_SUBSYSTEM($hdr);
            $info->{obsidss} = $obsidss->[0]
                if defined $obsidss && ref($obsidss) && @$obsidss;
        }

        # store it on hash indexed by obsid
        $unique{$obsid} = [] unless exists $unique{$obsid};
        push @{$unique{$obsid}}, $info;
    }

    # Now go through again and merge the headers and filename information for multiple files
    # but identical obsid.
    for my $obsid (keys %unique) {
        # To simplify syntax get array of headers and filenames
        my (@fits, @files, $frameset, %obsidss_files);
        for my $f (@{$unique{$obsid}}) {
            push @fits, $f->{header};
            push @files, $f->{filename};

            if (exists $f->{obsidss}) {
                my $key = $f->{obsidss};
                $obsidss_files{$key} = [] unless exists $obsidss_files{$key};
                push @{$obsidss_files{$key}}, $f->{filename};
            }

            $frameset = $f->{frameset} if defined $f->{frameset};
        }

        # Merge if necessary (shift off the primary)
        my $fitshdr = shift(@fits);
        # use Data::Dumper; print Dumper($fitshdr);

        if (@fits) {
            # need to merge
            # print "FITS:$_\n" for @fits;
            my ($merged, @different) = $fitshdr->merge_primary({merge_unique => 1}, @fits);

            # print Dumper(\@different);

            $merged->subhdrs(@different);
            # print Dumper({merged => $merged, different => \@different});

            $fitshdr = $merged;
        }

        # Some queries result in duplicate rows for filename so uniqify
        # Do not use a hash directly to get the list because that would scramble
        # the original order and we get upset when the OBSIDSS does not match the filename.
        my %files_uniq;
        my @compressed;
        for my $f (@files) {
            unless (exists $files_uniq{$f}) {
                $files_uniq{$f} ++;
                push(@compressed, $f);
            }
        }

        @files = @compressed;

        $unique{$obsid} = {
            header => $fitshdr,
            filenames => \@files,
            obsidss_files => \%obsidss_files,
            frameset => $frameset,
        };
    }

    return unless scalar %unique;
    return {%unique};
}


=item B<merge_dupes_no_fits>

Merges given list of hash references of database rows into a hash
with OBSIDs as keys.  Filenames are put in its own key-value pair
('filenames' is the key & value is an array reference).

    $merged = OMP::Util::FITS->merge_dupes_no_fits(@unmerged);

Input keys:

=over 4

=item header

Header hash reference.

=back

Output keys:

=over 4

=item header

Header hash reference.

=item filenames

Reference to array of filenames.

=back

=cut

sub merge_dupes_no_fits {
    my $class = shift;

    # Take local copies so that we can add information without affecting caller
    my @unmerged = map {
        {%$_}
    } @_;

    my %unique;
    for my $info (@unmerged) {
        next unless $info
            && keys %{$info};

        # Need to get a unique key via header translation
        my $hdr = $info->{header};
        my $trans;
        eval {$trans = Astro::FITS::HdrTrans::determine_class($hdr, undef, 1);};
        if ($@) {
            warn sprintf "Skipped '%s' due to: %s\n", $info->{'filename'}, $@;
        }

        next unless $trans;

        my $obsid = $trans->to_OBSERVATION_ID($hdr, $info->{frameset});

        # Keep the obsidss around (assume only a single one from a row)
        if ($trans->can("to_OBSERVATION_ID_SUBSYSTEM")) {
            my $obsidss = $trans->to_OBSERVATION_ID_SUBSYSTEM($hdr);
            $info->{obsidss} = $obsidss->[0]
                if defined $obsidss && ref($obsidss) && @$obsidss;
        }

        push @{$unique{$obsid}}, $info;
    }

    # Merge the headers and filename information for multiple files but identical
    # sorting key.
    for my $key (keys %unique) {
        my $headers = $unique{$key};

        # Collect ordered, unique file names.
        my (@file, %seen, %obsidss_files);
        for my $h (@{$headers}) {

            my $fkey = exists $h->{'header'}{'FILE_ID'}
                ? 'FILE_ID'
                : exists $h->{'header'}{'FILENAME'}
                    ? 'FILENAME'
                    : undef;

            next unless $fkey;

            # Don't delete() the $fkey entry so that Astro::FITS::HdrTrans does not fail
            # when searching for header translation class (happens for CGS4 instrument
            # at least).
            my $thisfile = $h->{header}->{$fkey};
            my @newfiles = (ref $thisfile ? @$thisfile : $thisfile);
            push @file, @newfiles;
            if (exists $h->{obsidss}) {
                my $key = $h->{obsidss};
                $obsidss_files{$key} = [] unless exists $obsidss_files{$key};
                push @{$obsidss_files{$key}}, @newfiles;
            }
        }

        @file = grep {! $seen{$_} ++} @file;

        # Merege rest of headers.

        $unique{$key} = {
            'header' => _merge_header_hashes($headers),
            'filenames' => [@file],
            'obsidss_files' => \%obsidss_files,
        };
    }

    return unless scalar %unique;
    return {%unique};
}


=item B<_merge_header_hashes>

Given a array reference of hash references (with "header" as the key),
merges them into a hash reference.  If any of the values differ for a
given key (database table column), all of the values appear in
"SUBHEADERS" array reference of hash references.

    $merged = _merge_header_hashes(
        [
            {'header' => {...}},
            {'header' => {...}},
        ]);

=cut

sub _merge_header_hashes {
    my ($list) = @_;

    return
        unless $list && scalar @{$list};

    my @list = @{$list};

    my %common;
    # Special case of a single hash reference.
    my $first = $list[0];
    %common = %{$first} if $first && ref $first;

    return delete $common{'header'}
        if 1 == scalar @list;

    # Rebuild.
    my %collect = _value_to_aref(@list);

    for my $k (keys %collect) {
        next if 'subheaders' eq lc $k;

        my @val = @{$collect{$k}};
        my $first = (grep {defined $_ && length $_} @val)[0];
        my $isnum = Scalar::Util::looks_like_number($first);

        if ((all {! defined $_} @val)
                || ($isnum && all {$first == $_} @val)
                || (defined $first && all {$first eq $_} @val)) {
            $common{'header'}->{$k} = $first;
            next;
        }

        delete $common{'header'}->{$k};
        for my $i (0 .. scalar @val - 1) {
            $common{'header'}->{'SUBHEADERS'}->[$i]->{$k} = $val[$i];
        }
    }

    return delete $common{'header'};
}

sub _value_to_aref {
    my (@list) = @_;

    my %hash;
    for my $href (@list) {
        while (my ($k, $v) = each %{$href->{'header'}}) {
            push @{$hash{$k}}, $v;
        }
    }

    return %hash;
}

1;

__END__

=back

=head1 AUTHORS

=over 4

=item *

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=item *

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=back

=head1 COPYRIGHT

Copyright (C) 2006-2009 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA

=cut
