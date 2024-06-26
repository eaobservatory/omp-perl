#!/local/perl/bin/perl

=head1 NAME

first-program-submission - Show time of first program submission

=head1 SYNOPSIS

    first-program-submission I<project-id> [ I<project-id> ... ]

    first-program-submission -f I<file-containing-project-ids>

    first-program-submission < I<file-containing-project-ids>

    echo I<project-id> | first-program-submission

=head1 DESCRIPTION

Given a list of project ids, this program generates comma separated values of
date-time of first program submission for each given project id.  The output
format is ...

    project-id,date

Project ids can be specified as arguments to the program, given in a
file, or provided on standard input.

=head2 OPTIONS

=over 2

=item B<-help> | B<-man>

Show the full help message.

=item B<-divider>

Print a blank line after output of each project id.  Default is not to
print the blank line.

=item B<-file> file-containing-project-ids

Specify a file name which has white space separated project ids.
This option can be specified multiple times.

File name of I<-> specifies to read from standard input.

=item B<-header>

If specified once, print the header only in the beginning (default).

If specified more than once, header is printed before output for each
project id.

=item B<-noheader> | B<-H>

Turn off header printing.

=back

=cut

use warnings;
use strict;

use Getopt::Long qw/:config gnu_compat no_ignore_case/;
use Pod::Usage;
use List::Util qw/first/;
use Scalar::Util qw/blessed openhandle/;

BEGIN {
    use FindBin;
    use constant OMPLIB => "$FindBin::RealBin/../lib";
    use lib OMPLIB;

    $ENV{'OMP_DIR'} = File::Spec->catdir(OMPLIB, File::Spec->updir())
        unless exists $ENV{'OMP_DIR'};
}

use OMP::Constants qw/:fb/;
use OMP::General;
use OMP::DB;
use OMP::DB::Backend;
use OMP::DB::Feedback;

my %opt = (
    'header' => undef,
    'divider' => undef,
    'file' => []
);

{
    my ($help, @file);
    GetOptions(
        'h|help|man' => \$help,
        'file=s' => \@file,
        'header+' => \$opt{'header'},
        'H|noheader' => sub {$opt{'header'} = 0},
        'divider!' => \$opt{'divider'},
    ) or pod2usage('-exitval' => 2, '-verbose' => 1);

    pod2usage('-exitval' => 1, '-verbose' => 2) if $help;

    $opt{'file'} = [@file] if scalar @file;

    # Print header at least once in the beginning by default.
    $opt{'header'} ++ unless defined $opt{'header'};
}

my @proj = get_projects(\%opt, @ARGV)
    or pod2usage(
        '-exitval' => 2,
        '-verbose' => 99,
        '-sections' => 'SYNOPSIS',
        '-msg' => 'No project ids were given.');

my $db = OMP::DB->new('DB' => OMP::DB::Backend->new);
my $progs = $db->_db_retrieve_data_ashash(make_query(@proj));

unless (scalar @{$progs}) {
    print "Nothing found in database for given project ids.\n";
    exit;
}

my $last = $progs->[-1];
for my $data (@{$progs}) {
    print_header($opt{'header'});

    print_csv($data);

    print "\n" if $opt{'divider'} && "$data" ne "$last";
}

exit;

BEGIN {
    # Column names of rows returned from dataabase.
    my @header = qw{ projectid date };

    #  Prints CSV given a hash reference (from DBI).
    sub print_csv {
        my ($hash) = @_;

        really_print_csv(map {$hash->{$_}} @header);

        return;
    }

    # Prints the header given a flag (if & how many times to print) and list of
    # header strings.
    sub print_header {
        return really_print_header($_[0], @header);
    }
}

{
    my $once;

    # Prints header as CSV given a flag and a list of header strings.  Flag
    # specifies if to print the header at all, only once, or every time.
    sub really_print_header {
        my $header_once = shift;

        return unless $header_once;
        return if $once && $header_once == 1;

        $once ++;
        my @header = @_;

        # Header in lower case after normalizing any camelCase ones.
        return really_print_csv(map {s/([a-z])([A-Z])/$1_$2/; lc $_} @header);
    }
}

# Simple mindedly prints CSV (see I<Text::CSV> for robustness).
sub really_print_csv {
    printf "%s\n", join ',', @_;
    return;
}

# Returns project id list given the options hash reference, and any additional
# project ids.
sub get_projects {
    my ($opt, @proj) = @_;

    my @file = @{$opt->{'file'}};

    push @file, '-'
        if -p \*STDIN && !first {$_ eq '-'} @file;

    for my $file (@file) {
        my $fh = (openhandle $file ? $file : open_file($file)) or next;
        while (my $line = <$fh>) {
            next if $line =~ m/^\s*$/ or $line =~ m/^\s*#/;

            for ($line) {
                s/^\s+//;
                s/\s+$//;
            }

            push @proj, split /\s+/, $line;
        }
    }
    return map {uc $_} @proj;
}

#  Returns the file handle after opening the given file name.
sub open_file {
    my ($file) = @_;

    my $fh;
    my $err = "Cannot open '$file' (skipped):";

    if ($file eq '-') {
        open $fh, '<-' or do {warn "$err $!\n"; return;};
    }
    else {
        open $fh, '<', $file or do {warn "$err $!\n"; return;};
    }

    return $fh;
}

# Returns the C<OMP::Query::TimeAcct> object given a project id.
sub make_query {
    my (@proj) = @_;

    my $list = join ', ', map {qq/'$_'/} @proj;

    # Only if a constant could be used in string interpolation.
    my $submitted = OMP__FB_MSG_SP_SUBMITTED;

    return <<"__SQL__";
        SELECT f.projectid, date
        FROM $OMP::DB::Feedback::FBTABLE f
        WHERE f.projectid IN ( $list )
          AND f.date =
            ( SELECT MIN(f2.date)
              FROM $OMP::DB::Feedback::FBTABLE f2
              WHERE f2.projectid = f.projectid
                AND ( f2.msgtype = $submitted OR f2.subject LIKE 'Science program submitted%' )
            )
        ORDER BY f.date
__SQL__
}

# Returns a string of given a list of values wrapped in the given tag.
sub wrap {
    my ($tag, @val) = @_;

    return "<$tag>" . join(' ', @val) . "</$tag>";
}

__END__

=head1 BUGS

Not known yet.

=head1 AUTHORS

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=cut
