# This is not a perl program
# It's a small chunk of perl code that can be used by all OMP CGI
# scripts to determine standard environment variables and perl module
# paths.

# It is an important simplification since it means that all the CGI
# scripts can have the location of their OMP module path changed in
# one place rather than every CGI script.

# This file must be in the same directory as your CGI program.
# It can be loaded using

#   do "./cgi-init.pl";

BEGIN {
  # For taint checking, restrict our path
  $ENV{PATH} = "/bin:/usr/bin";

  # Sybase environment variable (unless already set)
  $ENV{SYBASE} = "/local/progs/sybase"
    unless exists $ENV{SYBASE};

  # Global OMP location
  use constant OMPLIB => "/jac_sw/omp/msbserver";
  use File::Spec;

  # Set the configuration directory, unless we have an override
  # from the environment
  $ENV{'OMP_CFG_DIR'} = File::Spec->catdir( OMPLIB, "cfg" )
    unless exists $ENV{'OMP_CFG_DIR'};
}

# Make sure that all modules configure CGI::Carp the same way
use CGI;
use CGI::Carp qw/fatalsToBrowser/;

# Set the module search path to be the same location as the
# config file
use lib OMPLIB;

# Unbuffered output
$| = 1;

# Return value from script
1;

