package BioParser::FASTQ;
use Carp;
use IO::Uncompress::AnyUncompress;
use File::Spec;

use warnings;
use strict;
=pod

=head1 NAME

BioParser::FASTQ

=head1 VERSION

0.2

=head1 SYNOPSIS

A class for fastq parsing

=head1 METHODS

=cut


sub new {
=pod

=head2 new

Creates a new BioParser::FASTQ object

	use BioParser::FASTQ;
	my $fastq = new FASTQ;

=cut
	my ($class , $file) = @_;
	$file = File::Spec->rel2abs($file);
	croak "Need a file to open" unless ($args);
	croak "File doesn't exist" unless (-f $args);
	my $self = {
		file => $file,
		fh =>new IO::Uncompress::AnyUncompress $file || croak "anyuncompress failed\n",
		};
	
	
	
	my $object = bless $self , $class;
	return $object;
}

sub next {
=pod 

=head2 next

Get the next FASTQ file.

while (my $record = $fastq->next()){
	print Dumper $record.
	}

=cut 

	my $self = shift;

	my $record = {};

	my $fh = $self->{fh};

	$record->{header} = <$fh
	> // return 0;
	$record->{seq} = <$fh> // croak "MalFormed Fastq";
	$record->{header2} = <$fh> // croak "MalFormed Fastq";
	$record->{quals} = <$fh> // croak "MalFormed Fastq";

	chomp $_ foreach (values %$record);
	$record->{record} = join ("\n", ($record->{header},$record->{seq},$record->{header2},$record->{quals}));

	return $record;
}



sub get_offset{
=pod 

=head2 get_offset

Sets and returns a best guess of offset

my $offset = $fastq->get_offset;

=cut

	my $self = shift;

	while (my $record = $self->next()){
		map {
		 if ($_ > 75) {
			$self->seek_0();
			$self->{offset} = 64;
		 	return 64;
		 	} 
		 elsif ($_ < 58) {
		 	$self->seek_0();
		 	$self->{offset} = 33;
		 	return 33;
		 	}
		} unpack("W*" , $record->{'quals'});
	}
	$self->{offset} = -1 ; 
	$self->{fh} = new IO::Uncompress::AnyUncompress $self->{file};
	carp "Unable to guess the quality offset, set it yourself";
	return -1;
	}

