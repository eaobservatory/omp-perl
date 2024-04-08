#!/local/perl/bin/perl

use warnings;
use strict;
use 5.016;  # for //.

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use OMP::DB::Backend;
use OMP::UserDB;

my $SEP_IN = '[;,]+';
my $SEP_OUT = ' ; ';

my $INDENT = join '', (' ') x 2;
my $INDENT_2 = join '', (' ') x 4;
my $INDENT_3 = join '', (' ') x 6;

my @file = @ARGV
    or die qq[Give user data in a CSV file to be verified.\n];

my $udb = OMP::UserDB->new(DB => OMP::DB::Backend->new);

for my $file (@file) {
    print "Processing $file ...\n";
    my @user = parse_file($file) or next;

    for my $user (@user) {
        my ($userid, $name, $addr) = decompose_user($user);

        printf "${INDENT}%s\n", join $SEP_OUT, $userid, $name, $addr;

        my @exist = verify($name, $userid, $addr);
        unless (scalar @exist) {
            print "${INDENT_2}O K to add\n";
            next;
        }

        print "${INDENT_2}already E X I S T S ...\n";
        for my $rec (@exist) {
            printf "${INDENT_3}%s\n",
                join $SEP_OUT, map {$rec->$_() // '<undef>'} qw/userid name email/;
        }
    }
    continue {
        print "\n";
    }
}

exit;

sub decompose_user {
    my ($user, $fill_in) = @_;

    return map {
        my $x = $user->{$_};
        ! $fill_in
            ? $x
            : $x // '<undef>';
    } qw/userid name email/;
}

sub verify {
    my ($name, $id, $email) = @_;

    return $udb->getUserExpensive(
        'name' => $name,
        'email' => $email,
        'userid' => $id,
    );
}

sub parse_file {
    my ($file) = @_;

    my $fh;
    if ($file eq '-') {
        open $fh, '<-' or die "Cannot open '$file' to read: $!\n";
    }
    else {
        open $fh, '<', $file or die "Cannot open '$file' to read: $!\n";
    }

    my @user;

    while (my $line = <$fh>) {
        next if $line =~ /^\s*#/
            or $line =~ /^\s*$/;

        for ($line) {
            s/\#.*$//;
            s/^\s+//;
            s/\s+$//;
        }

        next unless $line;

        push @user, parse_line($line);
    }

    close $fh or die "Cannot close '$file': $!\n";

    return @user;
}

sub parse_line {
    my ($line) = @_;

    my ($id, $name, $email);
    my @in = split /\s*${SEP_IN}\s*/, $line;

    if (scalar @in == 3) {
        ($id, $name, $email) = @in;
    }
    elsif (scalar @in == 2) {
        ($name, $email) = @in;
    }
    else {
        $name = $in[0];
    }

    for ($id, $name) {
        next unless defined;
        s/^\s+//;
        s/\s+$//;
    }

    unless (defined $id && length $id) {
        $id = OMP::User->infer_userid($name);
        printf "User ID generated for %s: %s\n", $name, $id;
    }

    if (defined $email) {
        $email =~ s/\s+//g;
        $email = undef unless $email =~ /\@/;
    }

    return {
        'name' => $name,
        'userid' => $id,
        'email' => $email,
    };
}
