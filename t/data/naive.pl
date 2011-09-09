package Padre::Plugin::FormBuilder::Regression::Test1;

## no critic

# This module was generated by Padre::Plugin::FormBuilder::Perl.
# To change this module edit the original .fbp file and regenerate.
# DO NOT MODIFY THIS FILE BY HAND!

use 5.008;
use strict;
use warnings;
use Padre::Wx ();
use Padre::Wx::Role::Main ();

our $VERSION = '0.04';
our @ISA     = qw{
	Padre::Wx::Role::Main
	Wx::Dialog
};

sub new {
	my $class  = shift;
	my $parent = shift;

	my $self = $class->SUPER::new(
		$parent,
		-1,
		Wx::gettext("Test Dialog"),
		Wx::DefaultPosition,
		Wx::DefaultSize,
		Wx::DEFAULT_DIALOG_STYLE,
	);

	$self->{m_checkBox5} = Wx::CheckBox->new(
		$self,
		-1,
		Wx::gettext("Check Me!"),
		Wx::DefaultPosition,
		Wx::DefaultSize,
	);

	my $bSizer7 = Wx::BoxSizer->new(Wx::VERTICAL);
	$bSizer7->Add( $self->{m_checkBox5}, 0, Wx::ALL, 5 );

	$self->SetSizerAndFit($bSizer7);
	$self->Layout;

	return $self;
}

sub m_checkBox5 {
	$_[0]->{m_checkBox5};
}

1;

# Copyright 2008-2011 The Padre development team as listed in Padre.pm.
# LICENSE
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl 5 itself.

