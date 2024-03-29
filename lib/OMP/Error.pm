package OMP::Error;

=head1 NAME

OMP::Error - Exception handling in an object orientated manner

=head1 SYNOPSIS

    use OMP::Error qw /:try/;
    use OMP::Constants qw /:status/;

    # throw an error to be caught
    throw OMP::Error::AuthenticationFail( $message, OMP__AUTHFAIL );
    throw OMP::Error::FatalError( $message, OMP__FATAL );

    # record and then retrieve an error
    do_stuff();
    my $Error = OMP::Error->prior;
    OMP::Error->flush if defined $Error;

    sub do_stuff {
        record OMP::Error::FatalError( $message, OMP__FATAL);
    }

    # try and catch blocks
    try {
        stuff();
    }
    catch OMP::Error::FatalError with
    {
        # its a fatal error
        my $Error = shift;
        orac_exit_normally($Error);
    }
    otherwise
    {
       # this block catches croaks and other dies
       my $Error = shift;
       orac_exit_normally($Error);

    }; # Dont forget the trailing semi-colon to close the catch block

=head1 DESCRIPTION

C<OMP::Error> is inherits from the L<Error|Error> class and more
documentation about the (many) features present in the module but
currently unused by the OMP can be found in the documentation for that
module.

As with the C<Error> package, C<OMP::Error> provides two interfaces.
Firstly it provides a procedural interface to exception handling, and
secondly C<OMP::Error> is a base class for exceptions that can either
be thrown, for subsequent catch, or can simply be recorded.

If you wish to throw an exception then you should also C<use
OMP::Constants qw / :status /> so that the OMP constants are
available.

=head1 PROCEDURAL INTERFACE

C<OMP::Error> exports subroutines to perform exception
handling. These will be exported if the C<:try> tag is used in the
C<use> line.

=over 4

=item try BLOCK CLAUSES

C<try> is the main subroutine called by the user. All other
subroutines exported are clauses to the try subroutine.

The BLOCK will be evaluated and, if no error is throw, try will return
the result of the block.

C<CLAUSES> are the subroutines below, which describe what to do in the
event of an error being thrown within BLOCK.

=item catch CLASS with BLOCK

This clauses will cause all errors that satisfy
C<$err-E<gt>isa(CLASS)> to be caught and handled by evaluating
C<BLOCK>.

C<BLOCK> will be passed two arguments. The first will be the error
being thrown. The second is a reference to a scalar variable. If this
variable is set by the catch block then, on return from the catch
block, try will continue processing as if the catch block was never
found.

To propagate the error the catch block may call C<$err-E<gt>throw>

If the scalar reference by the second argument is not set, and the
error is not thrown. Then the current try block will return with the
result from the catch block.

=item otherwise BLOCK

Catch I<any> error by executing the code in C<BLOCK>

When evaluated C<BLOCK> will be passed one argument, which will be the
error being processed.

Only one otherwise block may be specified per try block

=back

=head1 CLASS INTERFACE

=head2 CONSTRUCTORS

The C<OMP::Error> object is implemented as a HASH. This HASH is
initialized with the arguments that are passed to it's
constructor. The elements that are used by, or are retrievable by the
C<OMP::Error> class are listed below, other classes may add to these.

    -file
    -line
    -text
    -value

If C<-file> or C<-line> are not specified in the constructor arguments
then these will be initialized with the file name and line number
where the constructor was called from.

The C<OMP::Error> package remembers the last error created, and also
the last error associated with a package.

=over 4

=item throw([ARGS])

Create a new C<OMP::Error> object and throw an error, which will be
caught by a surrounding C<try> block, if there is one. Otherwise it
will cause the program to exit.

C<throw> may also be called on an existing error to re-throw it.

=item with([ARGS])

Create a new C<OMP::Error> object and returns it. This is defined for
syntactic sugar, eg

    die with OMP::Error::FatalError($message, OMP__FATAL);

=item record([ARGS])

Create a new C<OMP::Error> object and returns it. This is defined for
syntactic sugar, eg

    record OMP::Error::AuthenticationFail($message, OMP__ABORT)
        and return;

=back

=head2 METHODS

=over 4

=item prior([PACKAGE])

Return the last error created, or the last error associated with
C<PACKAGE>

    my $Error = OMP::Error->prior;

=back

=head2 OVERLOAD METHODS

=over 4

=item stringify

A method that converts the object into a string. By default it returns
the C<-text> argument that was passed to the constructor, appending
the line and file where the exception was generated.

=item value

A method that will return a value that can be associated with the
error. By default this method returns the C<-value> argument that was
passed to the constructor.

=back

=head1 PRE-DEFINED ERROR CLASSES

=over 4

=item B<OMP::Error::Authentication>

The password provided could not be authenticated. Also encoded
in the constant C<OMP__AUTHFAIL>

=item B<OMP::Error::BadArgs>

Method was called with incorrect arguments.

=item B<OMP::Error::BadCfgKey>

Attempt was made to extract a configuration option from the config
system using a key that does not exist in the config file.

=item B<OMP::Error::CacheFailure>

Problem occurred with Archive caching.

=item B<OMP::Error::DataRead>

Unable to read data file off disk.

=item B<OMP::Error::DBConnection>

Unable to make a connection to the database backend.

=item B<OMP::Error::DBError>

Generic error with the backend database.

=item B<OMP::Error::DBLocked>

The database is currently locked out. Please try again later.

=item B<OMP::Error::DBMalformedQuery>

The DB query XML could not be understood.

=item B<OMP::Error::DirectoryNotFound>

The requested directory could not be found.

=item B<OMP::Error::FatalError>

Used when we have no choice but to abort but using a non-standard
reason. It's constructor takes two arguments. The first is a text
value, the second is a numeric value, C<OMP__FATAL>. These values are
what will be returned by the overload methods.

=item B<OMP::Error::FileNotFound>

The requested file could not be found.

=item B<OMP::Error::FileUseless>

The given file exists but could not be used for some reason.

=item B<OMP::Error::InvalidUser>

The user supplied to the routine is not a valid OMP user.

=item B<OMP::Error:MSBBadConstraint>

A site quality or scheduling constraints supplied in the science
programme is either inconsistent with the project constraint or
is inverted such that an MSB could never be scheduled.

=item B<OMP::Error::MSBMalformedQuery>

The MSB query XML could not be understood.

=item B<OMP::Error::MSBMissing>

The requested MSB could not be found in the current MSB database.
This is likely if the science program has been resubmitted since
the query was made. In general this is non-fatal.

=item B<OMP::Error::MSBMissingObserve>

An MSB was submitted that never resulted in an observation.
SpIterObserve was missing.

=item B<OMP::Error::MSBMissingTID>

Transaction ID is not associated with the MSB.

=item B<OMP::Error::ObsRead>

An error occurred during the reading of a file to create an
C<OMP::Info::Obs> object. This is typically due to a misformed
NDF or an NDF without a header (which could happen because of
negative countdowns at UKIRT).

=item B<OMP::Error::ProjectExists>

An attempt was made to add a project that already exists in the
database.

=item B<OMP::Error::SpBadStructure>

The Science Program XML was not valid.

=item B<OMP::Error::SpChangedOnDisk>

The version of the science program in the database was not derived
from the version of the science program being submitted (the timestamps
differ).

=item B<OMP::Error::SpEmpty>

No MSBs were present in the Science Program.

=item B<OMP::Error::SpRetrieveFail>

Unable to retrieve the Science Program from the database.

=item B<OMP::Error::SpStoreFail>

Unable to store the Science Program in the database.

=item B<OMP::Error::SpTruncated>

The Science Program has been truncated somehow.

=item B<OMP::Error::TranslateFail>

Error occurred during translation.

=item B<OMP::Error::UnknownProject>

The specified project is not known to the OMP.

=back

=head1 KNOWN PROBLEMS

C<OMP::Error> which are thrown and not caught inside a C<try> block
will in turn be caught by C<Tk::Error> if used inside a Tk
environment, as will C<croak> and C<die>. However if is a C<croak> or
C<die> is generated inside a try block and no C<otherwise> block
exists to catch the exception it will be silently ignored until the
application exits, when it will be reported.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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

use Error;
use warnings;
use strict;

our $VERSION = '2.000';

# flush method added to the base class
use base qw/Error::Simple/;

package OMP::Error::Authentication;
use base qw/OMP::Error/;

package OMP::Error::BadArgs;
use base qw/OMP::Error/;

package OMP::Error::BadCfgKey;
use base qw/OMP::Error/;

package OMP::Error::CacheFailure;
use base qw/OMP::Error/;

package OMP::Error::DataRead;
use base qw/OMP::Error/;

package OMP::Error::DBConnection;
use base qw/OMP::Error/;

package OMP::Error::DBError;
use base qw/OMP::Error/;

package OMP::Error::DBLocked;
use base qw/OMP::Error/;

package OMP::Error::DBMalformedQuery;
use base qw/OMP::Error/;

package OMP::Error::DirectoryNotFound;
use base qw/OMP::Error/;

package OMP::Error::FatalError;
use base qw/OMP::Error/;

package OMP::Error::FileNotFound;
use base qw/OMP::Error/;

package OMP::Error::FileUseless;
use base qw/OMP::Error/;

package OMP::Error::InvalidUser;
use base qw/OMP::Error/;

package OMP::Error::MSBBadConstraint;
use base qw/OMP::Error/;

package OMP::Error::MSBMalformedQuery;
use base qw/OMP::Error/;

package OMP::Error::MSBMissing;
use base qw/OMP::Error/;

package OMP::Error::MSBMissingObserve;
use base qw/OMP::Error/;

package OMP::Error::MSBMissingTID;
use base qw/OMP::Error/;

package OMP::Error::ObsRead;
use base qw/OMP::Error/;

package OMP::Error::ProjectExists;
use base qw/OMP::Error/;

package OMP::Error::SpBadStructure;
use base qw/OMP::Error/;

package OMP::Error::SpChangedOnDisk;
use base qw/OMP::Error/;

package OMP::Error::SpEmpty;
use base qw/OMP::Error/;

package OMP::Error::SpRetrieveFail;
use base qw/OMP::Error/;

package OMP::Error::SpStoreFail;
use base qw/OMP::Error/;

package OMP::Error::SpTruncated;
use base qw/OMP::Error/;

package OMP::Error::TranslateFail;
use base qw/OMP::Error/;

package OMP::Error::UnknownProject;
use base qw/OMP::Error/;

package OMP::Error::MailError;
use base qw/OMP::Error/;

1;
