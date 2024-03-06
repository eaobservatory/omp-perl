#!/local/perl/bin/perl

# Populates user database with initial details

# Input: text file containing user details
#
# CSV file containing:
#   userid [optional]
#   name
#   email address

# The userid is optional - if it is not present the userid
# will be derived from the name by taking the first letter
# of  the first name and the surname.

# All science program User ids should be SURNAMEI (eg JENNESST).

# cat user.details | perl mkuser.pl

# Uses the infrastructure classes so each user is inserted
# independently rather than as a single transaction

# If a user already exists, the current details will be displayed
# for comparison

use warnings;
use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

select \*STDERR; $| = 1;
select \*STDOUT; $| = 1;

use OMP::UserDB;
use OMP::User;
use OMP::UserServer;
use OMP::Error qw/:try/;

my $SEP_IN = q/[,;]+/;
my $SEP_OUT = q/,/;

while (<>) {
    next if /^\s*#/ or /^\s*$/;

    chomp;
    my $line = $_;

    # Remove comments
    $line =~ s/\#.*$//;

    next unless $line;

    # We have to guess the order
    # Force a split into three so we can distinguish between a
    # missing email address
    #  userid,name,
    # and a missing userid
    #  name,email
    # If a single name is supplied this is fine it it ends in a ,
    my @details = split /\s*$SEP_IN\s*/, $line, 3;

    for (@details) {
        s/^\s+//;
        s/\s+$//;
    }

    my ($userid, $name, $email);
    my %user;
    if (scalar(@details) == 3) {
        $user{userid} = $details[0];
        $user{name} = $details[1];
        $user{email} = $details[2];
        die 'Invalid user ID: ' . $user{'userid'}
            unless $user{'userid'} =~ /^[A-Z0-9]+$/;
    }
    else {
        $user{name} = $details[0];
        $user{email} = $details[1];
    }

    unless (defined $user{name} && length $user{name}) {
        warn "Skipped: no user name given in $line.\n";
        next;
    }

    $user{userid} = check_get_userid($user{name}, $user{userid});

    $_ = cleanse_addr($_) for $user{email};

    # Create new object
    my $ompuser = OMP::User->new(%user);

    die "Error creating user object: $user{userid}\n"
        unless $ompuser;

    show_detail($ompuser->userid, $ompuser->name, $ompuser->email);

    # More efficient to do the add and catch the failure rather than
    # do an explicit verify
    try {
        OMP::UserServer->addUser($ompuser);
    }
    otherwise {
        # Get the user
        my $exist = OMP::UserServer->getUser($ompuser->userid);

        if ($exist) {
            print "\n*** ",
                "Failed to add user. Existing entry retrieved for comparison:\n";

            show_detail($exist->userid, $exist->name, $exist->email, '  ');

            print "***\n";
        }
        else {
            my $E = shift;
            print "ERROR ADDING USER $user{userid}\n", $E;
        }
    };

    print "\n";
}

# Prints user detail in the same format as expected to be provided.
sub show_detail {
    my ($id, $name, $addr, $prefix) = @_;

    printf "%s%s\n",
        (defined $prefix ? $prefix : ''),
        join " $SEP_OUT ", $id, $name, (defined $addr ? $addr : '<no mail>');

    return;
}

# Returns a cleansed given email address.
sub cleanse_addr {
    my ($addr) = @_;

    return undef
        unless defined $addr && $addr =~ m{\@};

    for ($addr) {
        s/\s+//g;

        # Sometimes an address is shrouded in '<' & '>'.
        s/^<//;
        s/>$//;
    }

    return $addr;
}

# Returns an user id given a name. It also prints a warning if optional user id
# is given but does not match the system generated one.
sub check_get_userid {
    my ($name, $id) = @_;

    # Derive user id
    my $omp_userid = OMP::User->infer_userid($name);

    return $omp_userid
        unless defined $id && length $id;

    $id = uc $id;

    # It is entirely possible for user ids to not match when an user id has a
    # number at the end to distinguish from the others. In that case warning
    # should suggest that.
    if ($id ne $omp_userid) {
        warn sprintf
            "#  %s: Given and system generated user IDs do not match ...\n"
            . "#     given: %s\n#    system: %s\n",
            $name,
            $id,
            $omp_userid;
    }

    return $id;
}
