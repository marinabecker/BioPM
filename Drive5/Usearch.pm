package Usearch;

use Inline (CPP => 'DATA',
		    ccflags => '-std=c++11');


use Carp;
use Data::Dumper;
use File::Which;
use File::Basename;
use File::Copy qw/move/;
use File::Spec;



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

	my $usearch = Usearch->new();

=cut 	
	my $class = shift;
	my %args  = ( @_ && ref $_[0] eq 'HASH' ) ? %{ $_[0] } : @_; 

	$args{bin} //= 'usearch';

	croak("Can't find usearch at the path $args{bin} !") unless (-e $args{bin} && -x _);
	
	my $self = {
		bin => $args{bin},
		};

	my $object = bless $self , $class;

	return $object;
	}


sub sort {
	my $self = shift;
	my $file = shift;

	$file=File::Spec->rel2abs($file);
	
	return undef unless -e $file;

	my $system = $self->{bin}." --sortbylength $file -fastaout $file.sorted > $file.sorted.log 2>&1";
	if (system($system) == 0){
		move("$file.sorted" , $file);
		unlink("$file.sorted.log");
		return 0;
		}
	else{
		return "usearch sort failed.\n return: $?";
		}
	}

sub uclust{
=pod

=head2 uclust();

Performs clustering of fasta files through uclust. Uses small_mem so requires a sort first. Produces output as uc and or fasta;

	$usearch->uclust(
		id => '% id for clustering',
		file => 'full path to file',
		output => 'uc|fasta',
		);
=cut 
	my $self = shift;
	my %args  = ( @_ && ref $_[0] eq 'HASH' ) ? %{ $_[0] } : @_; 
	
	$self->{id} //= .60;

	$args{file} = File::Spec->rel2abs($args{file});
	return undef unless -e $args{file};

	$self->sort($args{file});

	my $system = $self->{bin}. " -cluster_smallmem $args{file} -id $args{id} -uc $args{file}.uc > $args{file}.cluster.log 2>&1";

	if (system($system) == 0){
		unlink("$args{file}.cluster.log");
		}
	else{
		return "Usearch cluster_smallmem failed on $args{file} with the following";
		}

	if ($args{output}=~/fasta/ig){
		my ($filename,$path,$suffix) = fileparse($args{file}, qr/\.[^.]*/);
		my $base_path = $path.$filename;
			#unlink previous sub groups;
		map { unlink($_) } $base_path."*.faagrp";
		open (IN , '<' , "$args{file}.uc") || croak("Couldn't open $args{file}.uc for reading!");
		my %cluster_hash;

		while (my $line = <IN>){
			chomp $line;
			$line=[split(/\s+/,$line)];
			$cluster_hash{$line->[8]} = $line->[1];
			}
		close IN;
		unlink("$args{file}.uc") unless $args{output}=~/uc/;

		my @values = values(%cluster_hash);
		@values = do { my %seen; grep { !$seen{$_}++ } @values};
		

		if (scalar(@values) > 1){
			open(FASTA,'<',$args{file}) || croak("Couldn't open $args{file} for reading");
			local $/ = ">";
			while (my $record = <FASTA>){
				chomp $record;
				next unless $record;
				my ($header , $sequence) = split(/\n/,$record,2);
				if (exists $cluster_hash{$header}){
					open(OUT , '>>' , "$base_path\_$cluster_hash{$header}.faagrp") || croak ("Unable to open $base_path\_$cluster_hash{$header}.faa !");
					print OUT ">$record";
					close OUT;
					}
				else{
					carp "$header is in the clusters but not in the hash!";
					}
				}
			}
		}

	return 0;
	}

sub generate_pairs{
=pod

=head2 generate_pairs();
Generate a file of pairwise distances for a fasta file.

Given the path to a file generates a tab seperated file of <query> <targe> <id>.

Returns the output file path on success , undef on failure.

	$USEARCH->generate_pairs($PATH_TO_FILE);

=cut

	my $self = shift;
	my $file = shift;

	$file = File::Spec->rel2abs($file);
	my ($filename,$path,$suffix) = fileparse($file, qr/\.[^.]*/);

	unless (-e $file){
		carp "$file doens't exist";
		return undef;
		}

	my $basepath = $path.$filename;

	my $system = "$self->{bin} -allpairs_local $file  -acceptall -userout $basepath.pairs -userfields query+target+id  > $basepath.pairs.stderr 2>&1";
	
	if (system($system) == 0){
		unlink("$basepath.pairs.stderr");
		}
	else{
		carp "Usearch failed for some reason! $?\n";
		return undef;
		}
	return "$basepath.pairs";
	}


sub matrix_from_usearch_pairs{
=pod

=head2 build_from_pairs();

Given a pairs file builds a matrix and dumps it to disk.

	build_from_pairs(path_to_pairs)

=cut
	my $self = shift;
	my $pairs_file = shift;
	$pairs_file = File::Spec->abs2rel($pairs_file);


	my ($filename,$path,$suffix) = fileparse($pairs_file, qr/\.[^.]*/);

	my $base_path = $path.$filename;

	my $matrix = Usearch::UsearchDistanceMatrix->new();
	my $line_number = $matrix->build_from_pairs($pairs_file);

	if ($line_number > 0){
		$matrix->print_matrix("$base_path.mtx");
		return "$base_path.mtx";
		}
	return undef;

	}


sub heatmap_pairs_matrix{
	my $self = shift;
	my $mtx = shift;
	open(IN , '<' , $mtx) || croak($!);
	my $header = <IN>; close IN; $header=(split(/\s+/,$header))[0];
	my $gene_name = (split(/~~~/,$header))[1];
	my $hm = basepath($mtx).".png";
	my $R = basepath($mtx).".R";
	
	open (OUT,'>',$R) || die $!;

	print OUT "data<-read.table(\"$mtx\" , header=TRUE )\n";
	print OUT "rownames(data)=colnames(data)\n";
	print OUT "data=as.matrix(data)\n";
	print OUT "library(gplots)\n";

	print OUT "png(file=\"$hm\",width=12*720,height=12*720,res=720,point=14)\n";
	print OUT "mtx <- heatmap.2 (data,denscol=\"green\",trace=\"none\",dendrogram=\"row\",symm=TRUE,keysize=0.7,main=\"$gene_name \" ,cexRow=0.2,offsetRow=0,labCol = \" \")\n";
	print OUT "dev.off()\n";
	print OUT "write.table(data, file=\"$mtx\" , sep=\"\\t\", row.names=TRUE, quote=FALSE)\n";

	my $system = ("Rscript $R > /dev/null 2>&1");
	if (system($system) == 0){
		return 1;
		}
	else{
		return  0;
		}


	}


sub basepath{
=pod

=head2 basepath()

Given a file - gets its full path , removes the last suffix , returns the full path and basename for usage

	basepath(/this/is/my/file.txt)

returns "/this/is/my/file";

=cut 
	my $file = File::Spec->rel2abs(shift);
	my ($filename,$path,$suffix) = fileparse($file, qr/\.[^.]*/);
	return  $path.$filename;
	}

1;

__DATA__
__CPP__


#include <unordered_map>
#include <unordered_set>
#include <string>
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <cstdio>


class UsearchDistanceMatrix{
public:
	UsearchDistanceMatrix();
	~UsearchDistanceMatrix();
	int build_from_pairs(SV*);
	int print_matrix (SV*);
	int report_copy_number();

private:
	int copy_number; 
	int line_number;
	std::unordered_map <std::string , std::vector <int>> copies_per_sample;
	std::unordered_set <std::string> key_set;
	std::unordered_map <std::string , int> index_to_keys;
	std::vector <std::vector<char> > matrix;
	};

UsearchDistanceMatrix::UsearchDistanceMatrix(){
	line_number = 0;
	}
UsearchDistanceMatrix::~UsearchDistanceMatrix(){

	}

int UsearchDistanceMatrix::build_from_pairs(SV* file_path){
	std::string S_file_path = SvPVX(file_path);
	std::ifstream file(S_file_path);
	
	if (file.is_open()){
		//get all possible identifiers from the pairs file , read them into a set then convert to an index->{integer} map
		// where the integer is essentially an index
		std::string line;
		
		while (getline(file,line)){
			line_number++;
			std::istringstream iss(line);
			if (iss.fail () || iss.bad()){
				return -2;
				}
			std::string target;
			std::string query;
			std::string value;
			iss >> target >> query >> value;
			key_set.insert(target);
			key_set.insert(query);
			}

		int index = 0;
		for (auto x : key_set){
			index_to_keys[x]=index;
			++index;
			}
		file.clear(); 
		file.seekg(0,file.beg);
		//reserve matrix

		std::vector<char> blank(index , 0);
		for (int x = 0 ; x < index ; ++x){
			matrix.push_back(blank);
			}

		// Actually Build the matrix
		while(getline(file,line)){
			std::istringstream iss(line);
			if (iss.fail () || iss.bad()){
				return -2;
				}
			std::string target;
			std::string query;
			std::string value;
			iss >> target >> query >> value;

			int i_value = std::stoi(value);
			
			
			matrix[index_to_keys[target]][index_to_keys[query]]= i_value;
			matrix[index_to_keys[query]][index_to_keys[target]]= i_value;
			matrix[index_to_keys[target]][index_to_keys[target]]= 100;
			matrix[index_to_keys[query]][index_to_keys[query]]= 100;
			}
		file.close();
		}
	else{
		return -1;
		}
	

	return line_number;
	}

int UsearchDistanceMatrix::print_matrix(SV* outfile){
	std::string file_name =SvPVX(outfile);
	std::ofstream file(file_name);
	if (!file.is_open()){
		return -1;
		}
	auto end_of_keys = index_to_keys.end();
	auto begining_of_keys = index_to_keys.begin();

	int size = index_to_keys.size();
//print our header
	auto header_it = begining_of_keys;
	while (true){
		file << header_it->first;
		++header_it;
		if (header_it != end_of_keys){
			file << "\t";
			}
		else{
			break;
			}
		}
	file << std::endl;
//print the matrix
	for (auto x = begining_of_keys ; x != end_of_keys ; ++x){
		auto y = begining_of_keys;
		while (true){
			file << (int)matrix[x->second][y->second];
			++y;
			if (y != end_of_keys){
				file << "\t";
				}
			else{
				break;
				}
			}
		file << std::endl;
		}
	file.close();
	return 0;
	
	}
