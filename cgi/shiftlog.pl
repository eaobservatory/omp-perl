#!/local/perl/bin/perl -XT
#
# shiftlog - keep a log throughout a night
#
# Author: Brad Cavanagh (b.cavanagh@jach.hawaii.edu)
use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
    my $retval = do "./omp-cgi-init.pl";
    unless ($retval) {
        warn "couldn't parse omp-cgi-init.pl: $@" if $@;
        warn "couldn't do omp-cgi-init.pl: $!" unless defined $retval;
        warn "couldn't run omp-cgi-init.pl" unless $retval;
        exit;
    }
}

use OMP::CGIPage::ShiftLog;

OMP::CGIPage::ShiftLog->new(cgi => CGI->new())->write_page(
    'shiftlog_page',
    'staff',
    title => 'Shift Log',
    template => 'shift_log.html',
);
