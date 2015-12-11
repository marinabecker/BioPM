package NCBI::Taxonomy;
use Carp;
use Data::Dumper;


use List::Util;
use File::Spec;
use File::Basename;
use File::Fetch;
use Archive::Tar;
use Storable;

use warnings;
use strict;

=pod
=head1 NCBI::Taxonomy

=head1 VERSION : 0.01

=head1 SYNOPSIS

A module for setting querying and using NCBI's taxonomy.


=head1 METHODS 

Loading this module will immediately cause the following happens:
It will fetch the NCBI taxdump if it doesn't exist;
It will build the lookup hash and will load it into memory.

If all of this is here already - the taxonomy tree is immediately loaded into memory for future use.

=cut

my @levels = qw/superkingdom kingdom phylum class order family genus species/;
my $memoized_get_taxon_rank = {};
my $memoized_get_full_taxonomy = {};

my $location = dirname(File::Spec->rel2abs(__FILE__));
fetch_taxonomy() unless -e ("$location/tax_lookup.store");
build_lookup_hash() unless -e ("$location/tax_lookup.store");
my $taxonomy_tree = retrieve("$location/tax_lookup.store");

build_hierarchy_counter();

1;

sub fetch_taxonomy{
=pod

=head2 NCBI::Taxonomy->fetch_taxonomy()

Attempts to fetch taxdump.tar.gz and setup the lookup hash for other functions

	NCBI::Taxonomy->fetch_taxonomy();
=cut
	my $fetch = File::Fetch->new(uri => 'ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz');
	unless (-e "$location/taxdump.tar.gz"){
		my $file = $fetch->fetch(to => $location);
		my $tar = Archive::Tar->new();
		$tar->read($location."/taxdump.tar.gz");
		$tar->extract_file("names.dmp",$location."/names.dmp");
		$tar->extract_file("nodes.dmp",$location."/nodes.dmp");	
		}
#	unlink($location."/taxdump.tar.gz");
	build_lookup_hash();
	return;
	}

sub update_taxonomy{
=pod

=head2 NCBI::Taxonomy->update_taxonomy();

Will force a refresh on the taxonomy download

=cut
	unlink ("$location/taxdump.tar.gz") if -e "$location/taxdump.tar.gz";
	return fetch_taxonomy();
	}

sub build_lookup_hash{
	return if -e ("$location/tax_lookup.store");
	my $taxonomy_tree;
	open(NAMES, '<' , "$location/names.dmp") || die $!;

	#build structure as $gi -> [ parent , level , name];

	while (my $line = <NAMES>){
		chomp $line;
		next unless $line =~/scientific/;
		my @parts = split(/\|/ , $line);
		$parts[0] =~s/\s//g;
		$parts[1] =~ s/^\s+//;
		$parts[1] =~ s/\s+$//;
		$taxonomy_tree->{$parts[0]}=[undef,undef,$parts[1]];
		}
	#put taxonomy tree into a structure
	open(TAXTREE , '<' , "$location/nodes.dmp") || die $!;
	
	while (my $line = <TAXTREE>){
		chomp $line;
		$line =~s/\s//g;
		my @parts = split(/\|/ , $line);
		$taxonomy_tree->{$parts[0]}->[0] = $parts[1] ;
		$taxonomy_tree->{$parts[0]}->[1] = $parts[2] ;

		#delete nodes whose parent is root. 
		if ($parts[0] == 1){	
			delete $taxonomy_tree->{$parts[0]};
			}

		}
	store $taxonomy_tree , "$location/tax_lookup.store";
	#unlink("$location/names.dmp");
	#unlink("$location/nodes.dmp");
	return;
	}

sub build_hierarchy_counter{
=pod 

=head2 NCBI::Taxonomy->build_hierarchy_counters

Creates an empty tree structure for hierarchical counting within taxons

Current supported levels are SuperKingdom , Kingdom , Phylum , Class , Order, Family , Genus, and Species

=cut

	my $empty_tree_counter = {};
	
	return if (-e "$location/empty_tree_counter.store" ) ;
	open(NAMES, '<' , "$location/nodes.dmp") || die $!;
	
	while (my $line = <NAMES>){
		my $id = (split(/\|/,$line))[0];
		$id =~s/\s+//g;
		print Dumper $id  ;
		print Dumper get_full_taxonomy( $id );
		}





	}

sub get_full_taxonomy{
=pod

=head2 get_full_taxonomy()

Given a taxonomic id returns a hash reference with the taxonomy. 

	NCBI::Taxonomy->get_full_taxonomy(2902);
	
	$VAR1 = {
	          'class' => '-',
	          'genus' => 'Emiliania',
	          'kingdom' => '-',
	          'superkingdom' => 'Eukaryota',
	          'family' => 'Noelaerhabdaceae',
	          'order' => 'Isochrysidales',
	          'phylum' => '-',
	          'species' => '-'
	        };



=cut
	my $id = shift @_;
	my $memoize = shift @_;
	my $tax = {
		superkingdom => '',
		kingdom => '',
		phylum => '',
		class => '', 
		order => '', 
		family => '',
		genus => '', 
		species => '',
		};

	my @return_string = ();
		
	while ($id  > 1){
		$tax->{$taxonomy_tree->{$id}->[1]} = $taxonomy_tree->{$id}->[2] if exists $tax->{$taxonomy_tree->{$id}->[1]};
		$id = $taxonomy_tree->{$id}->[0]; #get parent id;
		}
	map {
		$tax->{$_} = '-' if $tax->{$_} eq '';
		} keys %{$tax};
	return $tax;

	}
sub get_taxon_rank{
=pod 

=head2 NCBI::Taxonomy->get_taxon_rank

Returns the taxonomy at a given level for a specific tax_id.ie given the tax_id 1299282 (Salmonella bongori CFSAN000510) and the text 'genus': 

	$text = NCBI::Taxonomy->get_taxon_rank(1299282,'genus');

	#returns Salmonella

If you simply need the taxon text for the specific tax_id don't pass a level;

	$text = NCBI::Taxonomy->get_taxon_rank(1299282);

	#returns "Salmonella bongori CFSAN000510"

If for anyreason a match isn't made (either the tax_id doesn't exist OR the tax_id doesn't have a level you requested) the return will be -1;

=cut
	shift @_;
	my ($id , $level) = @_;
	my $original_id = $id;
	unless ($level){
		return (exists $taxonomy_tree->{$id})? $taxonomy_tree->{$id}->[2] : -1;
		}

	my %levels =(
				speciesgroup => 1 ,
				family => 1 ,
				subfamily => 1 ,
				subphylum => 1 ,
				superphylum => 1 ,
				subgenus => 1 ,
				norank => 1 ,
				subkingdom => 1 ,
				superorder => 1 ,
				genus => 1 ,
				superkingdom => 1 ,
				superclass => 1 ,
				speciessubgroup => 1 ,
				varietas => 1 ,
				infraorder => 1 ,
				subtribe => 1 ,
				subclass => 1 ,
				forma => 1 ,
				suborder => 1 ,
				tribe => 1 ,
				parvorder => 1 ,
				kingdom => 1 ,
				phylum => 1 ,
				species => 1 ,
				order => 1 ,
				infraclass => 1 ,
				superfamily => 1 ,
				subspecies => 1 ,
				class=> 1);

	unless ( exists $levels{$level}){
		carp " from NCBI::Taxonomy::get_taxon_level (): $level , isn't an NCBI level!";
		return -1;
		}
	
	if (exist $memoized_get_taxon_rank->{$original_id}->{$level}){
		return $memoized_get_taxon_rank->{$original_id}->{$level};
		}

	while ($taxonomy_tree->{$id}->[1] ne $level){
		$id = $taxonomy_tree->{$id}->[0];
		if (! defined($id) || $id == 0 || $id == 1){
			$memoized_get_taxon_rank->{$original_id}->{$level} = -1;
			return -1
			}
		}

	$memoized_get_taxon_rank->{$original_id}->{$level} = $taxonomy_tree->{$id}->[2];
	return $taxonomy_tree->{$id}->[2];	
	}
