package OMP::Info;

=head1 NAME

OMP::Info - Base class for OMP::Info objects

=head1 SYNOPSIS

    use OMP::Info;

=head1 DESCRIPTION

This is a generic base class for C<OMP::Info> objects.

=cut

use 5.006;
use strict;
use warnings;

use Carp;
use OMP::Range;

our $VERSION = '2.000';

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

General hash based constructor. Hash arguments are read in and
each argument sent to a corresponding accessor method to initialize
the object.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    # Create the object
    my $obj = bless {}, $class;

    # Initialise it
    $obj->configure(_initialize => 1, @_);

    return $obj;
}

=back

=head2 General Methods

=over 4

=item B<configure>

Configure the object. Usually called directly from the constructor.
Accepts a hash and for each hash key that matches a method name
passes the value to that method. Keys are case insensitive.

    $i->configure(%args);

If the argument hash contains a special key ("_initialize") set to
true the object will be initialised with values returns from the
C<Defaults> method prior to configuring with the supplied hash. This
allows subclasses to initialise the object without having to subclass
a constructor or the C<configure> method.

=cut

sub configure {
    my $self = shift;
    my %args = @_;

    # Look for the initialize flag
    if (exists $args{_initialize} && $args{_initialize}) {
        %args = ($self->Defaults, %args);
    }

    # Go through the input args invoking relevant methods
    for my $key (keys %args) {
        next if $key =~ /^_/;
        my $method = lc($key);
        if ($self->can($method)) {
            $self->$method($args{$key});
        }
    }
}

=item B<shallow_copy>

Create a shallow copy of an C<OMP::Info> object.  Any (unblessed) ARRAY or
HASH reference at the top level is replaced with a new ARRAY or HASH with
the same contents (including the same references) while anything else is
copied as-is to the new object.

    $copy = $object->shallow_copy;

The ARRAY and HASH accessor methods created by this class will write into
an existing ARRAY or HASH attribute, so these replacements are necessary
to prevent such assignments from altering the content of the original object.
(Of course if any other mutable object or structure inside the object is
changed then the change will still appear in the original object.)

B<See also:> the C<copy> method of C<OMP::Info::Obs> (which uses
C<Storable::dclone> to make a deep copy, thereby more thoroughly isolating
the copy from the original object).

=cut

sub shallow_copy {
    my $self = shift;

    my $copy = bless {}, ref $self;

    foreach my $key (keys %$self) {
        my $value = $self->{$key};
        if ('ARRAY' eq ref $value) {
            # Create new top-level array.
            $copy->{$key} = [@$value];
        }
        elsif ('HASH' eq ref $value) {
            # Create new top-level hash.
            $copy->{$key} = {%$value};
        }
        else {
            # Copy scalars, objects (and other references).
            $copy->{$key} = $value;
        }
    }

    return $copy;
}

=back

=head1 Class methods

=over 4

=item B<uniqueid>

Returns a unique ID for the object.

    $id = $object->uniqueid;

=cut

sub uniqueid {
    my $self = shift;

    return if ! defined($self->runnr)
        || ! defined($self->instrument)
        || ! defined($self->telescope)
        || ! defined($self->startobs);

    return $self->runnr
        . $self->instrument
        . $self->telescope
        . $self->startobs->ymd
        . $self->startobs->hms;
}

=item B<Defaults>

Default initialiser for the object. Should be subclassed if
you wish to modify defaults. Called by C<configure> method.

    %defaults = OMP::Info->Defaults();

The base class returns an empty list.

=cut

sub Defaults {
    return ();
}

=item B<CreateAccessors>

Create specific accessor methods on the basis of the supplied
initializer.

    OMP::Info->CreateAccessors(%members);

An accessor method will be created for each key supplied in the
hash. The value determines the type of accessor method.

=over 4

=item $

Standard scalar accessor (non reference)

=item %

Hash (ref) accessor.

=item @

Array (ref) accessor.

=item 'string'

Class name (supplied object must be of specified class).

=item @string

Array containing specific class.

=item %string

Hash containing specific class.

=item $__UC__

Upper case all arguments (scalar only).

=item $__LC__

Lower case all arguments (scalar only).

=item $__ANY__

Any scalar (including references).

=back

Scalar accessor accept scalars (but not references) to modify the
contents and return the scalar.  With UC/LC modifiers the scalar
arguments are upcased or down cased. With the ANY modifier scalars can
include references of any type (this is also implied by UC and LC).
Hash/Array accessors accept either lists or a reference (and do not
check contents). They return a list in list context and a reference in
scalar context. If an @ or % is followed by a string this indicates
that the array/hash can only accept arguments of that class (all
arguments or array elements are tested).

Class accessors are the same as scalar accessors except their
arguments are tested to make sure they are of the right class.

ASIDE: Do not use C<Class::Struct> since we require bleadperl for it
to work properly with accessors that initialize with object
references. Also we want to be able to check array arguments are
of a correct class.

=cut

sub CreateAccessors {
    my $caller = shift;
    my %struct = @_;

    my $header = "{\n package $caller;\n use strict;\n use warnings;\nuse Carp;\n";

    my $footer = "\n}";

    my $SCALAR = q{
#line 1 OMP::Info::SCALAR
        sub METHOD {
            my $self = shift;
            if (@_) {
                my $argument = shift;
                if (defined $argument) {
                    CLASS_CHECK;
                }
                $self->{METHOD} = $argument;
            }
            return $self->{METHOD};
        }
    };

    my $ARRAY = q{
#line 1 OMP::Info::ARRAY
        sub METHOD {
            my $self = shift;
            $self->{METHOD} = [] unless $self->{METHOD};
            if (@_) {
                my @new;
                if (ref($_[0]) eq 'ARRAY') {
                    @new = @{$_[0]};
                }
                else {
                    @new = @_;
                }
                ARRAY_CLASS_CHECK;
                @{$self->{METHOD}} = @new;
            }
            if (wantarray) {
                return @{$self->{METHOD}};
            }
            else {
                return $self->{METHOD};
            }
        }
    };

    my $HASH = q{
#line 1 OMP::Info::HASH
        sub METHOD {
            my $self = shift;
            $self->{METHOD} = {} unless $self->{METHOD};
            if (@_) {
                if (defined $_[0]) {
                    my %new;
                    if (ref($_[0]) eq 'HASH') {
                        %new = %{$_[0]};
                    }
                    else {
                        %new = @_;
                    }
                    HASH_CLASS_CHECK;
                    if (ref($_[0]) eq 'HASH' && tied(%{$_[0]})) {
                        $self->{METHOD} = $_[0];
                    }
                    else {
                        %{$self->{METHOD}} = %new;
                    }
                }
                else {
                    # clear class
                    $self->{METHOD} = undef;
                    return undef;
                }
            }
            if (wantarray) {
                return (defined $self->{METHOD} ? %{$self->{METHOD}} : ());
            }
            else {
                $self->{METHOD} = {} if ! defined $self->{METHOD};
                return $self->{METHOD};
            }
        }
    };

    my $CLASS_CHECK = q{
#line 1 OMP::Info::class_check
        unless (UNIVERSAL::isa($argument, 'CLASS')) {
            croak "Argument for 'METHOD' must be of class CLASS and not class '".
                (defined $argument ? (ref($argument) ? ref($argument) : $argument) : '<undef>') ."'";
        }
    };

    my $ARRAY_CLASS_CHECK = q{
#line 1 OMP::Info::array_class_check
        for my $argument (@new) {
            CLASS_CHECK;
        }
    };

    my $HASH_CLASS_CHECK = q{
#line 1 OMP::Info::hash_class_check
        for my $key (keys %new) {
            my $argument = $new{$key};
            CLASS_CHECK;
        }
    };

    my $REFCHECK = q{
        croak "Argument for method 'METHOD' can not be a reference"
            if ref($argument);
    };

    my $UPCASE = $REFCHECK . q{ $argument = uc($argument); };

    my $DOWNCASE = $REFCHECK . q{ $argument = lc($argument); };

    # Loop over the supplied keys
    my $class = '';
    for my $key (keys %struct) {
        # Need to create the code
        my $code = $header;

        my $MEMBER = $key;
        my $TYPE = $struct{$key};

        if ($TYPE =~ /^\$/) {
            # Simple scalar
            $code .= $SCALAR;

            # Remove the CHECK block
            if ($TYPE =~ /__UC__/) {
                # upper case
                $code =~ s/CLASS_CHECK/$UPCASE/;
            }
            elsif ($TYPE =~ /__LC__/) {
                # lower case
                $code =~ s/CLASS_CHECK/$DOWNCASE/;
            }
            elsif ($TYPE =~ /__ANY__/) {
                $code =~ s/CLASS_CHECK//;
            }
            else {
                # Check references
                $code =~ s/CLASS_CHECK/$REFCHECK/;
            }
        }
        elsif ($TYPE =~ /^\@/) {
            $code .= $ARRAY;

            # Using a class?
            if ($TYPE =~ /^\@(.+)/) {
                $class = $1;
                $code =~ s/ARRAY_CLASS_CHECK/$ARRAY_CLASS_CHECK/;
                $code =~ s/CLASS_CHECK/$CLASS_CHECK/;
            }
            else {
                $code =~ s/ARRAY_CLASS_CHECK//;
            }
        }
        elsif ($TYPE =~ /^\%/) {
            $code .= $HASH;

            # Using a class?
            if ($TYPE =~ /^\%(.+)/) {
                $class = $1;
                $code =~ s/HASH_CLASS_CHECK/$HASH_CLASS_CHECK/;
                $code =~ s/CLASS_CHECK/$CLASS_CHECK/;
            }
            else {
                $code =~ s/HASH_CLASS_CHECK//;
            }
        }
        elsif ($TYPE =~ /^\w/) {
            # Hopefully a class
            $class = $TYPE;
            $code .= $SCALAR;
            $code =~ s/CLASS_CHECK/$CLASS_CHECK/;
        }

        # Add the closing block
        $code .= $footer;

        # Replace METHOD with method name
        $code =~ s/METHOD/$MEMBER/g;
        $code =~ s/CLASS/$class/g;

        # Run the code
        eval $code;
        if ($@) {
            croak "Error running method creation code: $@\n Code: $code\n";
        }
    }
}

1;

__END__

=back

=head1 TODO

Add code references.

=head1 SEE ALSO

L<Class::Struct>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

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
