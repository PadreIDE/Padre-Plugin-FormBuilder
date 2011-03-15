package Padre::Plugin::FormBuilder;

=pod

=head1 NAME

Padre::Plugin::FormBuilder - Generate Perl for dialogs created in wxFormBuilder

=head1 DESCRIPTION

The FormBuilder user interface design tool helps to produce user interface code
relatively quickly. However, it does not support the generation of Perl.

B<Padre::Plugin::FormBuilder> provides an interface to the
L<Wx::Perl::FormBuilder> module to allow the generation of Padre dialog code
based on wxFormBuilder designs.

=head1 METHODS

=cut

use 5.008005;
use strict;
use warnings;

# Normally we would run-time load most of these,
# but we happen to know Padre uses all of them itself.
use Class::Inspector 1.22 ();
use Params::Util     1.00 ();
use Padre::Plugin    0.66 ();
use Padre::Util      0.81 ();
use Padre::Wx        0.66 ();

our $VERSION = '0.02';
our @ISA     = 'Padre::Plugin';

# Temporary namespace counter
my $COUNT = 0;





#####################################################################
# Padre::Plugin Methods

sub padre_interfaces {
	'Padre::Plugin'         => 0.66,
	'Padre::Util'           => 0.81,
	'Padre::Wx'             => 0.66,
	'Padre::Wx::Role::Main' => 0.66,
}

sub plugin_name {
	'wxFormBuilder';
}

# Clean up our classes
sub plugin_disable {
	my $self = shift;
	$self->unload('Padre::Plugin::FormBuilder::Dialog');
	$self->unload('Padre::Plugin::FormBuilder::FBP');
	$self->unload('Padre::Plugin::FormBuilder::Perl');
}

sub menu_plugins_simple {
	my $self = shift;
	return $self->plugin_name => [
		'Generate Padre Dialog' => sub {
			$self->menu_dialog;
		},
	];
}





######################################################################
# Menu Commands

sub menu_dialog {
	my $self = shift;
	my $main = $self->main;

	# Load the wxGlade-generated Perl file
	my $xml  = $self->dialog_fbp or return;
	my $list = $self->package_list($xml);

	# Show the main dialog
	require Padre::Plugin::FormBuilder::Dialog;
	my $dialog = Padre::Plugin::FormBuilder::Dialog->new(
		$main, $xml, $list,
	);
	while ( $dialog->ShowModal != Wx::wxID_CANCEL ) {
		# Extract information and clean up dialog
		my $name    = $dialog->selected;
		my $command = $dialog->command;
		unless ( $name and $command ) {
			last;
		}

		# Do they want a Padre dialog or a regular one
		my $padre = !! $dialog->{padre}->IsChecked;

		# Should we generate into a temporary namespace
		my $package = $dialog->{temp}->IsChecked
			? "Padre::Plugin::FormBuilder::Temp::Dialog" . ++$COUNT
			: $name;

		# Generate the dialog code
		my $code = $self->generate_dialog(
			file    => $xml,
			dialog  => $name,
			package => $package,
			padre   => $padre,
		);

		# Handle the user instructions
		if ( $command eq 'generate' ) {
			# Open the generated code as a new file
			$self->main->new_document_from_string(
				$code,
				'application/x-perl',
			);
			last;
		}

		# Must be previes.
		# Load the dialog
		local $@;
		eval "$code";
		if ( $@ ) {
			$self->main->error("Error loading dialog: $@");
			$self->unload($name);
			last;
		}

		# Create the dialog
		my $preview = eval {
			$name->new( $main );
		};
		if ( $@ ) {
			$self->main->error("Error constructing dialog: $@");
			$self->unload($name);
			last;
		}

		# Show the dialog
		my $rv = eval {
			$preview->ShowModal;
		};
		$preview->Destroy;
		if ( $@ ) {
			$self->main->error("Dialog crashed while in use: $@");
			$self->unload($name);
			last;
		}

		# Clean up
		$self->unload($name);
		last;
	}

	$dialog->Destroy;
	return;
}





######################################################################
# Dialog Functions

sub dialog_fbp {
	my $self    = shift;
	my $main    = $self->main;
	my $project = $main->current->project;

	# Where is the wxGlade-generated Perl file
	my $dialog = Wx::FileDialog->new(
		$main,
		Wx::gettext("Select wxFormBuilder File"),
		$project ? $project->root : $main->cwd,
		"",
		"*.fbp",
		Wx::wxFD_OPEN | Wx::wxFD_FILE_MUST_EXIST,
	);
	$dialog->CenterOnParent;

	# File select loop
	while ( $dialog->ShowModal != Wx::wxID_CANCEL ) {
		# Check the file
		my $path = $dialog->GetPath;
		unless ( -f $path ) {
			$main->error("File '$path' does not exist");
			next;
		}

		return $path;
	}

	return undef;
}

sub dialog_class {
	my $self = shift;
	my $name = shift || '';
	my $main = $self->main;

	# What class name?
	my $dialog = Wx::TextEntryDialog->new(
		$main,
		Wx::gettext("Enter Class Name"),
		$self->plugin_name,
		$name,
	);
	while ( $dialog->ShowModal != Wx::wxID_CANCEL ) {
		my $package = $dialog->GetValue;
		unless ( defined $package and length $package ) {
			$main->error("Did not provide a class name");
			next;
		}
		unless ( Params::Util::_CLASS($package) ) {
			$main->error("Not a valid class name");
			next;
		}

		return $package;
	}

	return;
}





######################################################################
# Main Functionality

# Do a simple scan for package statements
sub package_list {
	my $self = shift;
	my $file = shift;

	# Load the file
	require FBP;
	my $xml = FBP->new;
	my $ok  = $xml->parse_file($file);
	unless ( $ok ) {
		$self->main->error("Failed to load $file");
		return;
	}

	return [
		grep { defined $_ and length $_ }
		map  { $_->name }
		$xml->find( isa => 'FBP::Dialog' )
	];
}

# Generate the class code
sub generate_dialog {
	my $self  = shift;
	my %param = @_;

	# Load the file
	require FBP;
	my $xml = FBP->new;
	my $ok  = $xml->parse_file($param{file});
	unless ( $ok ) {
		$self->main->error("Failed to load $param{file}");
		return;
	}

	# Find the dialog
	my $fbp = $xml->find_first(
		isa  => 'FBP::Project',
	);
	my $dialog = $fbp->find_first(
		isa  => 'FBP::Dialog',
		name => $param{dialog},
	);
	unless ( $dialog ) {
		$self->main->error("Failed to find dialog $param{dialog}");
		return;
	}

	# Does the project have an existing version?
	my $project = $self->current->project;
	my $version = $project ? $project->version : undef;

	# Configure the code generator
	my $perl = undef;
	if ( $param{padre} ) {
		require Padre::Plugin::FormBuilder::Perl;
		$perl = Padre::Plugin::FormBuilder::Perl->new(
			project => $fbp,
			defined($version) ? ( version => $version ) : (),
		);
	} else {
		require FBP::Perl;
		$perl = FBP::Perl->new(
			project => $fbp,
		);
	}

	# Generate the class code
	my $string = $perl->flatten(
		$perl->dialog_class( $dialog, $param{package} )
	);

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

Copyright 2010 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
