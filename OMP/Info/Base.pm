package OMP::Info::Base;

=head1 NAME

OMP::Info::Base - Base class for OMP::Info objects

=head1 SYNOPSIS

  use OMP::Info::Base;

=head1 DESCRIPTION

This is a generic base class for C<OMP::Info> objects.

=cut

use 5.006;
use strict;
use warnings;

use Carp;
use OMP::Range;

our $VERSION = (qw$Revision$)[1];


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
  $obj->configure( _initialize => 1, @_ );

  return $obj;
}

=back

=head2 General Methods

=over 4

=item B<configure>

Configure the object. Usually called directly from the constructor.
Accepts a hash and for each hash key that matches a method name
passes the value to that method. Keys are case insensitive.

  $i->configure( %args );

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
    %args = ( $self->Defaults, %args);
  }

  # Go through the input args invoking relevant methods
  for my $key (keys %args) {
    next if $key =~ /^_/;
    my $method = lc($key);
    if ($self->can($method)) {
      $self->$method( $args{$key});
    }
  }

}

=back

=head1 Class methods

=over 4

=item B<Defaults>

Default initialiser for the object. Should be subclassed if
you wish to modify defaults. Called by C<configure> method.

  %defaults = OMP::Info::Base->Defaults();

The base class returns an empty list.

=cut

sub Defaults {
  return ();
}

=item B<CreateAccessors>

Create specific accessor methods on the basis of the supplied
initializer.

  OMP::Info::Base->CreateAccessors(%members);

An accessor method will be created for each key supplied in the
hash. The value determines the type of accessor method.

  $ - standard scalar accessor
  % - hash (ref) accessor
  @ - array (ref) accessor
  'string' - class name (supplied object must be of specified class)
  @string   - array containing specific class
  %string  - hash containing specific class
  $__UC__ - upper case all arguments (scalar only)
  $__LC__ - lower case all arguments (scalar only)

Scalar accessor accept scalars to modify the contents and return the
scalar.  Hash/Array accessors accept either lists or a reference. They
return a list in list context and a reference in scalar context. If an
@ or % is followed by a string this indicates that the array/hash can
only accept arguments of that class (all arguments or array elements
are tested).

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
#line 1 OMP::Info::Base::SCALAR
		 sub METHOD {
		   my $self = shift;
		   if (@_) { 
		     my $argument = shift;
		     CLASS_CHECK;
		     $self->{METHOD} = $argument;
		   }
		   return $self->{METHOD};
		 }
	       };

  my $ARRAY = q{
#line 1 OMP::Info::Base::ARRAY
		sub METHOD {
		  my $self = shift;
		  $self->{METHOD} = [] unless $self->{METHOD};
		  if (@_) {
		    my @new;
		    if (ref($_[0]) eq 'ARRAY') {
		      @new = @{$_[0]};
		    } else {
		      @new = @_;
		    }
		    ARRAY_CLASS_CHECK;
		    @{ $self->{METHOD} } = @new;
		  }
		  if (wantarray) {
		    return @{ $self->{METHOD} };
		  } else {
		    return $self->{METHOD};
		  }
		}
	      };

  my $HASH = q{
#line 1 OMP::Info::Base::HASH
	       sub METHOD {
		 my $self = shift;
		 $self->{METHOD} = {} unless $self->{METHOD};
		 if (@_) {
		   my %new;
		   if (ref($_[0]) eq 'HASH') {
		     %new = @{$_[0]};
		   } else {
		     %new = @_;
		   }
		   HASH_CLASS_CHECK;
		   %{ $self->{METHOD} } = %new;
		 }
		 if (wantarray) {
		   return @{ $self->{METHOD} };
		 } else {
		   return $self->{METHOD};
		 }
	       }
	     };

  my $CLASS_CHECK = q{
#line 1 OMP::Info::Base::class_check
		      unless (UNIVERSAL::isa($argument, 'CLASS')) {
			croak "Argument for 'METHOD' must be of class CLASS and not class '". (ref($argument) ? ref($argument) : $argument) ."'";
		      }
		     };

  my $ARRAY_CLASS_CHECK = q{
#line 1 OMP::Info::Base::array_class_check
			    for my $argument (@new) {
			      CLASS_CHECK;
			    }
			   };

  my $HASH_CLASS_CHECK = q{
#line 1 OMP::Info::Base::hash_class_check
			   for my $key (keys %new) {
			     my $argument = $new{$key};
			     CLASS_CHECK;
			   }
			  };

  my $UPCASE = q{ $argument = uc($argument); };
  my $DOWNCASE = q{ $argument = lc($argument); };

  # Loop over the supplied keys
  my $class = '';
  for my $key (keys %struct) {
    # Need to create the code
    my $code = $header;

    my $MEMBER = $key;
    my $TYPE = $struct{$key};

    if ($TYPE =~ /^\$/ ) {
      # Simple scalar
      $code .= $SCALAR;

      # Remove the CHECK block
      if ($TYPE =~ /__UC__/) {
	# upper case
	$code =~ s/CLASS_CHECK/$UPCASE/;
      } elsif ($TYPE =~ /__LC__/) {
	# lower case
	$code =~ s/CLASS_CHECK/$DOWNCASE/;
      } else {
	$code =~ s/CLASS_CHECK//;	
      }

    } elsif ($TYPE =~ /^\@/) {

      $code .= $ARRAY;

      # Using a class?
      if ($TYPE =~ /^\@(.+)/) {
	$class = $1;
	$code =~ s/ARRAY_CLASS_CHECK/$ARRAY_CLASS_CHECK/;
	$code =~ s/CLASS_CHECK/$CLASS_CHECK/;
      } else {
	$code =~ s/ARRAY_CLASS_CHECK//;
      }
    } elsif ($TYPE =~ /^\@/) {

      $code .= $ARRAY;

      # Using a class?
      if ($TYPE =~ /^\@(.+)/) {
	$class = $1;
	$code =~ s/HASH_CLASS_CHECK/$HASH_CLASS_CHECK/;
	$code =~ s/CLASS_CHECK/$CLASS_CHECK/;
      } else {
	$code =~ s/HASH_CLASS_CHECK//;
      }

    } elsif ($TYPE =~ /^\w/) {
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

=back

=head1 SEE ALSO

L<Class::Struct>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
