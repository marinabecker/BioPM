package Parse::FASTA;
use Carp;
use File::Spec;
use IO::Uncompress::AnyUncompress;

use warnings;
use strict;

=pod
=head1 NAME

=head1 VERSION

=head1 SYNOPSIS

=head1 METHODS 
=cut



sub new{
=pod 

=head2 new


=cut 	
	my ($class , $file) = @_;


	$file = File::Spec->rel2abs($file);	
	croak ("No file provided !") unless $file;
	croak ("$file doesn't exist") unless (-e $file);

		
	my $self ={
		file => $file,
		FH=> new IO::Uncompress::AnyUncompress $file || croak("Couldn't open $file\n")
		};

	my $object = bless $self , $class;
	return $object;
	}


sub get_record {
	my $self = shift;

	local $/ = ">";
	
	my $fh = $self->{FH};
	my $rec = <$fh>;

	if (defined $rec){
		chomp $rec;
		unless($rec){
			$rec = <$fh>;
			chomp $rec;
			}
		}
	else{
		return undef;
		}

	my ($header , $sequence) = split(/\n/,$rec,2);
	$sequence=~s/\n//g if $sequence;
	return [$header , $sequence];
	}
1;
