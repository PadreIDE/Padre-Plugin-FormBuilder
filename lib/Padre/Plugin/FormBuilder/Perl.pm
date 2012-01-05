package Padre::Plugin::FormBuilder::Perl;

=pod

=head1 NAME

Padre::Plugin::FormBuilder::Perl - wxFormBuilder to Padre dialog code generator

=head1 SYNOPSIS

  my $generator = Padre::Plugin::FormBuilder::Perl->new(
      dialog => $fbp_object->dialog('MyDialog')
  );

=head1 DESCRIPTION

This is a L<Padre>-specific variant of L<FBP::Perl>.

It overloads various methods to make things work in a more Padre-specific way.

=cut

use 5.008005;
use strict;
use warnings;
use Scalar::Util 1.19 ();
use Params::Util 0.33 ();
use FBP::Perl    0.71 ();

our $VERSION = '0.04';
our @ISA     = 'FBP::Perl';





######################################################################
# Constructor

sub new {
	my $self = shift->SUPER::new(
		# Apply the default prefix style
		prefix => 2,
		@_,
	);

	# The encapsulate accessor
	$self->{encapsulate} = $self->{encapsulate} ? 1 : 0;

	return $self;
}

sub encapsulate {
	$_[0]->{encapsulate};
}





######################################################################
# Dialog Generators

sub form_class {
	my $self  = shift;
	my $form  = shift;
	my $lines = $self->SUPER::form_class($form);
	my $year  = 1900 + (localtime(time))[5];

	# Append the copywrite statement that Debian/etc need
	push @$lines, <<"END_PERL";

# Copyright 2008-$year The Padre development team as listed in Padre.pm.
# LICENSE
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl 5 itself.
END_PERL

	return $lines;
}

sub project_header {
	my $self  = shift;
	my $lines = $self->SUPER::project_header(@_);

	# Add the modification warning
	my $class = Scalar::Util::blessed($self);
	push @$lines, (
		"# This module was generated by $class.",
		"# To change this module edit the original .fbp file and regenerate.",
		"# DO NOT MODIFY THIS FILE BY HAND!",
		"",
	);

	return $lines;
}

sub form_new {
	my $self   = shift;
	my $dialog = shift;
	my $lines  = $self->SUPER::form_new($dialog);

	# Find the full list of public windows
	my @public = grep {
		$_->permission eq 'public'
	} $dialog->find( isa => 'FBP::Window' );

	if ( $self->encapsulate and @public ) {
		# Generate code to save the wxWidgets id values to the hash slots
		my @save = ( '' );
		foreach my $window ( @public ) {
			my $name     = $window->name;
			my $variable = $self->object_variable($window);
			push @save, "\t\$self->{$name} = $variable->GetId;";
		}

		# Splice the bind code into the constructor
		splice( @$lines, $#$lines - 2, 0, @save );
	}

	return $lines;
}

sub project_dist {
	my $self    = shift;
	my $project = shift;
	my $name    = $project->name;

	# If the name is a module name (which it is) then convert to
	# the common dashed version.
	$name =~ s/::/-/g;

	return $name;
}

sub form_super {
	my $self = shift;
	my @super = $self->SUPER::form_super(@_);
	if ( @super ) {
		unshift @super, 'Padre::Wx::Role::Main';
	}
	return @super;
}

sub form_wx {
	my $self  = shift;
	my $topic = shift;
	my $lines = [
		"use Padre::Wx ();",
		"use Padre::Wx::Role::Main ();",
	];
	if ( $self->find_plain( $topic => 'FBP::RichTextCtrl' ) ) {
		push @$lines, "use Wx::STC ();";
	}
	if ( $self->find_plain( $topic => 'FBP::HtmlWindow' ) ) {
		push @$lines, "use Wx::Html ();";
	}
	if ( $self->find_plain( $topic => 'FBP::Grid' ) ) {
		push @$lines, "use Wx::Grid ();";
	}
	if ( $self->find_plain( $topic => 'FBP::Calendar' ) ) {
		push @$lines, "use Wx::Calendar ();";
		push @$lines, "use Wx::DateTime ();";
	} elsif ( $self->find_plain( $topic => 'FBP::DatePickerCtrl' ) ) {
		push @$lines, "use Wx::DateTime ();";
	}
	return $lines;
}

sub form_custom {
	my $self  = shift;
	my $form  = shift;
	my $lines = $self->SUPER::form_custom( $form, @_ );

	# Are any of the files used by the form relative
	# and within the share directory.
	if ( grep { /^share\b/ } $self->form_files($form) ) {
		push @$lines, "use File::ShareDir ();";
	}

	return $lines;
}

sub form_files {
	my $self  = shift;
	my $form  = shift;
	my @files = ();

	# Static bitmaps
	push @files, map {
		$_->bitmap
	} $form->find( isa => 'FBP::StaticBitmap' );

	# Tools
	push @files, map {
		$_->bitmap
	} $form->find( isa => 'FBP::Tool' );

	# Menu entries
	push @files, map {
		$_->bitmap
	} $form->find( isa => 'FBP::MenuItem' );

	# Bitmap buttons
	push @files, map {
		$_->bitmap,
		$_->disabled,
		$_->selected,
		$_->hover,
		$_->focus,
	} $form->find( isa => 'FBP::BitmapButton' );

	# Animation controls
	push @files, map {
		$_->inactive_bitmap
	} $form->find( isa => 'FBP::AnimationCtrl' );

	# Clean and filter
	my %seen = ();
	return grep {
		not $seen{$_}++
	} map {
		s/; Load From File$// ? $_ : ()
	} grep {
		defined $_
	} map {
		Params::Util::_STRING($_)
	} @files;
}

sub object_accessor {
	my $self = shift;
	unless ( $self->encapsulate ) {
		return $self->SUPER::object_accessor(@_);
	}

	my $object = shift;
	my $name   = $object->name;
	return $self->nested(
		"sub $name {",
		"Wx::Window::FindWindowById(\$_[0]->{$name});",
		"}",
	);
}

sub object_event {
	my $self   = shift;
	my $window = shift;
	my $event  = shift;
	my $name   = $window->name;
	my $method = $window->$event();

	return $self->nested(
		"sub $method {",
		"\$_[0]->main->error('Handler method $method for event $name.$event not implemented');",
		"}",
	);
}

# Because we expect everything to be shimmed, apply a stricter interpretation
# of lexicality if the code is being generated for Padre.
sub object_lexical {
	my $self = shift;
	unless ( $self->encapsulate ) {
		return $self->SUPER::object_lexical(@_);
	}
	return 1;
}

# File name
sub file {
	my $self   = shift;
	my $string = shift;
	return undef unless Params::Util::_STRING($string);
	return undef unless $string =~ s/; Load From File$//;
	unless ( $string =~ s/^share[\\\/]// ) {
		return $self->quote($string);
	}

	# Special sharedir form
	my $file = $self->quote($string);
	my $dist = $self->quote($self->project_dist($self->project));
	return "File::ShareDir::dist_file( $dist, $file )";
}

sub wx {
	my $self = shift;
	unless ( $self->prefix > 1 ) {
		return $self->SUPER::wx(@_);
	}

	# Apply the same null checks as the normal method
	my $string = shift;
	return 0  if $string eq '';
	return -1 if $string eq 'wxID_ANY';

	# Handle constants in the new Wx::FOO style
	$string =~ s/\bwx/Wx::/gi;

	# Tidy a collection of multiple constants
	$string =~ s/\s*\|\s*/ | /g;

	return $string;
}

1;

=pod

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Padre-Plugin-FormBuilder>

For other issues, or commercial enhancement or support, contact the author.

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 SEE ALSO

L<Padre>

=head1 COPYRIGHT

Copyright 2010 - 2011 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
