package GLPSOL;
use Carp;
use File::Which;

use warnings;
use strict;

my $VERSION = '0.1';

=pod

=head1 NAME
GLPSOL.pm

=head1 VERSION
$VERSION

=head1 SYNOPSIS
A library for writing MPS files , executing glpsol, and parsing outputs

=head1 METHODS 
=cut

sub new{
=pod 

=head2 new

Creates a new GLPSOL object. Can take an argument to where the glpsol binary is, otherwise
attempts to find it in $PATH.

	 my $GLPSOL = new GLPSOL('/path/to/glpsol')
=cut 	
	my ($class , $bin) = @_;

	#Give program name if none provided
	$bin //= 'glpsol';

	my $bin_path = which('glpsol');

	if ($bin_path && -x $bin){
		$bin = $bin;
		}
	elsif($bin_path){
		$bin = $bin_path;
		}
	elsif(-x $bin){
		$bin = $bin;
		}
	else{
		croak("Couldn't find executable in your path , or where you said it was!");
		}

	croak ("Can't find glpsol on the provided path! ") unless (-x $bin);
	my $self = {
		BIN => $bin
		};
	my $object = bless $self , $class;
	return $object;
	}

sub get_bin{
	my $self = shift;
	return $self->{BIN}
	}
	
sub min_set_cover{
=pod 

=head2 min_set_cover

Writes an MPS file to solve a minimum set cover problem from a hash of hashes (sparse matrix). Assumes that the first set of keys is the row , and the second set of keys is any column that row belongs to. We solve the matrix to minimimize the number of columns needed to describe all of the rows in the matrix. 

	
	my $mps_file = GLPSOL->min_set_cover($HASH);
	
=cut 
	my $self = shift;
	my $args = shift;
	my $matrix = $args->{matrix};
	my $file = $args->{file} // 'MIN_SET_COVER';
	open (MPS , '>', "$file") || croak ($!);
	croak ("Need a HASH reference for min_set_cover") unless ref($matrix) eq 'HASH';
	
	#get list of columns;
	my @columns;
	my @rows = keys %{$matrix};
	foreach my $row (@rows){
		foreach my $column (keys %{$matrix->{$row}}){
			push (@columns, $column);
			}
		} 
	#map reduce <--- thats funny, I dont care who you are	
	@columns = do {my %seen; grep { !$seen{$_}++ } @columns}; 
	
	
	print MPS "NAME          $file\n";
	print MPS "ROWS\n";
	print MPS " N  NUM\n";
	
	foreach my $row (@rows) {
		print MPS " G  $row\n";
		}

	print MPS "COLUMNS\n";
	foreach my $column (@columns) {
		printf MPS "    %-10s %-10s %10d\n" , $column, "NUM",1;
		foreach my $row (@rows){
			if (exists $matrix->{$row}->{$column}){
				printf MPS "    %-10s %-10s %10d\n" , $column, $row,1;
				}
			}
		}

	print MPS "RHS\n";

	foreach my $row (@rows) {
		printf MPS "    %-10s%-10s%10.1f\n" ,"RHS1",$row, 1.0 ;
		}
	
	print MPS "BOUNDS\n";
	
	foreach my $column (@columns){
		printf MPS " BV %-10s%-10s\n" ,"BND1", $column;
		}

	print MPS "ENDATA\n\n";
	close MPS;
	return $file;
	}

sub execute{
=pod t 

=head2 execute

Takes a path to an MPS file, and runs it through glpsol, returns the path of the solution.
	
	my $solution = $GLPSOL->execute(path/to/file.mps);
	
=cut
	my $self = shift;
	my $file = shift;
	croak ("$file doesn't appear to exist") unless (-e $file);
	my $command = join ' ' ,($self->{BIN}, '--freemps' , $file , '-o', "$file.sol" , ">"," /dev/null" , "2>&1");
	system($command) == 0 || croak "system call $command failed, returned:\n\t $?\n";
	return "$file.sol";
	}

sub parse_solution{
=pod 

=head2 parse_solution

Parses a solution file generated from GLPSOL , returns two lists : the naive solution (i.e. all members) and a minimum set that still provides cover. 
	
	my $mps_file = GLPSOL->min_set_cover($HASH);
	
=cut 
	my $self = shift;
	my $file = shift;
	my $total_list = [];
	my $minimum_list = [];
	croak ("$file doesn't appear to exist") unless (-e $file);
	open (SOL , '<' , $file) || croak ($!);

	my $start_reading = 0;
	while (my $line = <SOL>){
		chomp $line;
		$start_reading = 0 if ($line =~/^$/); #reset for blank line at end of solution
		if ($start_reading == 1){
			next if $line eq '------ ------------    ------------- ------------- -------------';
			next if $line eq '';
			next if $line eq 'End of output';
			$line =~s/\*//g;
			my ($blank ,$number, $column, $minum) = split (/\s+/,$line);
			push @$total_list , $column;
			push @$minimum_list , $column if $minum == 1;
			}
		$start_reading = 1 if ($line eq '   No. Column name       Activity     Lower bound   Upper bound');
		}
	close SOL;
	return {
		'total_list' => $total_list,
		'minimum_list' => $minimum_list
		};
	}


1;

