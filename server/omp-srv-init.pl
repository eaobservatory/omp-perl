# This is not a Perl program
# It's a small chunk of Perl code that can be used by all OMP CGI server
# scripts to determine standard environment variables and Perl module
# paths.

# This file must be in the same directory as your CGI program.
# It can be loaded using

#   do './omp-srv-init.pl';

BEGIN {
    # For taint checking, restrict our path
    $ENV{'PATH'} = '/bin:/usr/bin';

    # Global OMP location
    use constant OMPLIB => '/jac_sw/omp/msbserver/lib';
    use File::Spec;

    # Set the configuration directory, unless we have an override
    # from the environment
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

# Set the module search path to be the same location as the
# config file
use lib OMPLIB;

# Use "JAC" path for "local" modules.
use JAC::Setup qw/ocsq ocscfg hdrtrans/;

# Return value from script
1;
