package Viz::D3::NestedJSON;
use Carp;
use Data::Dumper;


use List::Util;
use File::Spec;
use File::Basename;
use File::Fetch;
use Archive::Tar;
use List::Util qw /any/;
use Storable;

use JSON;

use warnings;
use strict;

=pod
=head1 Viz::D3::TaxonomyCirclePack

=head1 VERSION : 0.01

=head1 SYNOPSIS

A module for mapping count data to a nested structure and drawing a packed circle graph.

=head1 METHODS 

Loading this module will immediately cause the following happens:
It will fetch the NCBI taxdump if it doesn't exist;


=cut

my @levels = qw/superkingdom kingdom phylum class order family genus species/;
my $location = dirname(File::Spec->rel2abs(__FILE__));
fetch_taxonomy() unless -e ("$location/tax_lookup");
build_lookup_array() unless -e ("$location/tax_lookup");
my $look_up_array = retrieve "$location/tax_lookup";

1;



sub fetch_taxonomy{
=pod

=head2 Viz::D3::TaxonomyCirclePack->fetch_taxonomy()

Attempts to fetch taxdump.tar.gz and setup the lookup hash for other functions

	Viz::D3::TaxonomyCirclePack->fetch_taxonomy()
=cut
	my $fetch = File::Fetch->new(uri => 'ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz');
	unless (-e "$location/taxdump.tar.gz"){
		my $file = $fetch->fetch(to => $location);
		my $tar = Archive::Tar->new();
		$tar->read($location."/taxdump.tar.gz");
		$tar->extract_file("names.dmp",$location."/names.dmp");
		$tar->extract_file("nodes.dmp",$location."/nodes.dmp");	
		}
	unlink($location."/taxdump.tar.gz");
	my @lookup = build_lookup_array();
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


sub build_lookup_array{
=pod

=head2 Viz::D3::TaxonomyCirclePack->build_lookup_array()

Builds a look up array where tax id -> superkingdom;kingdom;phylum;class;order;family;genus;species

=cut

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
	close NAMES;

	open(TAXTREE , '<' , "$location/nodes.dmp") || die $!;	
	while (my $line = <TAXTREE>){
		chomp $line;
		$line =~s/\s//g;
		my @parts = split(/\|/ , $line);
		$taxonomy_tree->{$parts[0]}->[0] = $parts[1] ;
		$taxonomy_tree->{$parts[0]}->[1] = lc($parts[2]) ;

		#delete nodes whose parent is root. 
		if ($parts[0] == 1){	
			delete $taxonomy_tree->{$parts[0]};
			}
		}
	close TAXTREE;


	my @ids = ();


	map {
		my @array = ();
		my $base_id = $_;
		my $id = $base_id;

		if (exists $taxonomy_tree->{$base_id}){

			while ($id > 1){
				unshift (@array , $taxonomy_tree->{$id}->[2]) if (any {$_ eq $taxonomy_tree->{$id}->[1] }  @levels);
				$id =  $taxonomy_tree->{$id}->[0];
				}

			$ids[$base_id]= join(';', @array);

			}

		} keys %{$taxonomy_tree};

	# close (IDOUT);
	store \@ids, "$location/tax_lookup" || die $!;

	unlink "$location/names.dmp";
	unlink "$location/nodes.dmp";


	return;
	}




sub new {

	my $class = shift;
	my %args  = ( @_ && ref $_[0] eq 'HASH' ) ? %{ $_[0] } : @_; 	


	my $self = {
		total_adds => 0,
		tax_counter => {}
		};

	

	my $object = bless $self , $class;
	return $object;
	}


sub incrementID {
	my ($self , $id , $value) = @_;
	return unless $id;
	my $key_list = $look_up_array->[$id];
	return unless defined $key_list;
	($value)? $self->{tax_counter}->{$id} +=$value : $self->{tax_counter}->{$id}++;
	($value)? $self->{total_adds} += $value : $self->{total_adds}++;
	return;
	
#   #this builds a perfect nested hash structure. but it isn't quite what we need
#   my @keys = split(/;/ , $key_list);
# 	my $ref = \$self->{tax_counter};

# 	#loop to the lowest possible and auto vivify as we go
# 	$ref = \$$ref->{$_} foreach @keys;

# 	if ($value){
# 		$$ref->{size}+=$value;
# 		$self->{total_adds}+=$value;
# 		}
# 	else {
# 		$$ref->{size}++;
# 		$self->{total_adds}++;
# 		}
	}


sub flare{

	my $self = shift;
	
	my @sorted_ids;

	@sorted_ids = map { $_->[0] }
					 sort { $a->[1] <=> $b->[1] }
					 map { [ $_ , $look_up_array->[$_]=~ tr/\;/\;/ ] }
					 keys %{$self->{tax_counter}};

		



	my $flare = {
		name => 'flare'
		};

	 map{
	 	my @taxonomy = split (/;/ , $look_up_array->[$_]);
	 	my $ref = \$flare; #top of the tree;
	 	foreach my $taxon(@taxonomy){
	 		if ( defined $$ref->{children}){
	 			my $index = 0;
	 			my $exists = 0;
	 			foreach my $i (@{$$ref->{children}}){
	 				if ($i->{name} && $i->{name} eq $taxon){
	 					$exists = 1;
	 					last;
	 					}
	 				$index++;
	 				}
	 			if ($exists){
	 				$ref = \$$ref->{children}->[$index];
	 				}
	 			else{
					push @{$$ref->{children}} , {name => $taxon};
		 			$ref = \$$ref->{children}->[-1];
	 				}
	 			}

	 		else{
	 			push @{$$ref->{children}} , {name => $taxon};
	 			$ref = \$$ref->{children}->[-1];
	 			}

	 		}
		if (exists $self->{tax_counter}->{$_}){
			$$ref->{size} = $self->{tax_counter}->{$_};
			}

	 	}@sorted_ids;

	 	$self->{flare} = encode_json $flare;
		return $self->{flare};
		}

sub generate_html{
	
	}