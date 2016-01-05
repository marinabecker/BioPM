package Viz::D3::TaxonomyCirclePack;
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
	store \@ids, "$location/tax_lookup" || die $!;
	unlink "$location/names.dmp";
	unlink "$location/nodes.dmp";
	return;
	}




sub new {
=pod

=head2 new

Creates a new basic object for holding taxonomic data.

	my $object = Viz::D3::TaxonomyCirclePack->new();


=cut
	my $class = shift;

	my $self = {
		total_adds => 0,
		tax_counter => {}
		};

	my $object = bless $self , $class;
	return $object;
	}


sub incrementID {
=pod 

=head2 incrementID()

Increments a taxonomic id, if a value is passed to the method increments it by that amount

	$object->incrementID(23); # increments taxonomic id 23 by 1
	$object->incremembtID(23,500); #increments taxonomic id 23 by 50

=cut

	my ($self , $id , $value) = @_;
	return unless $id;
	my $key_list = $look_up_array->[$id];
	return unless defined $key_list;
	($value)? $self->{tax_counter}->{$id} +=$value : $self->{tax_counter}->{$id}++;
	($value)? $self->{total_adds} += $value : $self->{total_adds}++;
	return;
	}

sub normalize{
=pod 

=head2 normalize()

Normalizes all values by the number total number of elements in the object

	$object->normalize()

=cut
	my $self = shift;
	return unless $self->{total_adds};
	map{
		$_ = $_ / $self->{total_adds};
		}keys %{$self->{tax_counter}};
	return;
	}


sub flareSimple{
=pod

=head2 flareSimple()

Converts a basic object into a simple flare figure

=cut
	my $self = shift;
	
	#Schwartsian transform to sort by number of taxonomic items;
	my @sorted_ids = map { $_->[0] }
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


sub drawSimple{
=pod 

=head2 drawSimple()

Takes a simple flare object and draws it as a circle pack. 


=cut
	my $self = shift;
	$self->flareSimple() unless exists $self->{flare};

	(my $document = qq @

	<!DOCTYPE html>
	<html>
	<head>
	<meta charset="utf-8">
	<style>

	.node {
	  cursor: pointer;
	}

	.node:hover {
	  stroke: #000;
	  stroke-width: 1.5px;
	}

	.node--leaf {
	  fill: white;
	}

	.label {
	  font: 10px "Helvetica Neue", Helvetica, Arial, sans-serif;
	  text-anchor: middle;
	  text-shadow: 0 1px 0 #fff, 1px 0 0 #fff, -1px 0 0 #fff, 0 -1px 0 #fff;
	}

	.label,
	.node--root,
	.node--leaf {
	  pointer-events: none;
	}

	.d3-tip {
	  line-height: 1;
	  font-weight: bold;
	  padding: 12px;
	  background: rgba(0, 0, 0, 0.8);
	  color: #fff;
	  border-radius: 2px;
	  -webkit-transition: opacity 0.3s; /* For Safari 3.1 to 6.0 */
	  transition: opacity 0.3s;
	}

	/* Creates a small triangle extender for the tooltip */
	.d3-tip:after {
	  box-sizing: border-box;
	  display: inline;
	  font-size: 10px;
	  width: 100%;
	  line-height: 1;
	  color: rgba(0, 0, 0, 0.8);
	  content: "\25BC";
	  position: absolute;
	  text-align: center;
	}

	/* Style northward tooltips differently */
	.d3-tip.n:after {
	  margin: -1px 0 0 0;
	  top: 100%;
	  left: 0;
	}
	</style>
	</head>
	<body>
	<script src="http://d3js.org/d3.v3.min.js" charset="utf-8"></script>
	<script>

	var root = $self->{flare};

	var margin = 10,
	    diameter = 960;

	var color = d3.scale.linear()
	    .domain([-1, 7])
	    .range(["hsl(152,20%,80%)", "hsl(228,90%,15%)"])
	    .interpolate(d3.interpolateHcl);

	var pack = d3.layout.pack()
	    .padding(100)
	    .size([diameter - margin, diameter - margin])
	    .value(function(d) { return d.size; }) 

	var svg = d3.select("body").append("svg")
	    .attr("width", diameter)
	    .attr("height", diameter)
	    .append("g")
	    .attr("transform", "translate(" + diameter / 2 + "," + diameter / 2 + ")");

	var focus = root,
	      nodes = pack.nodes(root),
	      view;

	var circle = svg.selectAll("circle")
	      .data(nodes)
	      .enter().append("circle")
	      .attr("class", function(d) { return d.parent ? d.children ? "node" : "node node--leaf" : "node node--root"; })
	      .style("fill", function(d) { return d.children ? color(d.depth) : null; })
	      .on("click", function(d) { if (focus !== d) zoom(d), d3.event.stopPropagation(); })
	      .on('mouseout', function (d) {tipCirclePack.hide(d)});

	  var text = svg.selectAll("text")
	      .data(nodes)
	      .enter().append("text")
	      .attr("class", "label")
	      .style("fill-opacity", function(d) { return d.parent === root ? 1 : 0; })
	      .style("display", function(d) { return d.parent === root ? null : "none"; })
	      .text(function(d) { return d.name });// ! d.children ? d.name : d.size > 10 ? d.name : null }); // play with this to display text on specific size 

	  var node = svg.selectAll("circle,text");

	  d3.select("body")
	      .style("background", color(-1))
	      .on("click", function() { zoom(root); });

	  zoomTo([root.x, root.y, root.r * 2 + margin]);

	  function zoom(d) {
	    var focus0 = focus; focus = d;

	    var transition = d3.transition()
	        .duration(d3.event.altKey ? 750 : 750)
	        .tween("zoom", function(d) {
	          var i = d3.interpolateZoom(view, [focus.x, focus.y, focus.r * 2 + margin]);
	          return function(t) { zoomTo(i(t)); };
	        });

	    transition.selectAll("text")
	      .filter(function(d) { return d.parent === focus || this.style.display === "inline"; })
	        .style("fill-opacity", function(d) { return d.parent === focus ? 1 : 0; })
	        .each("start", function(d) { if (d.parent === focus) this.style.display = "inline"; })
	        .each("end", function(d) { if (d.parent !== focus) this.style.display = "none"; });
	  }

	  function zoomTo(v) {
	    var k = diameter / v[2]; view = v;
	    node.attr("transform", function(d) { return "translate(" + (d.x - v[0]) * k + "," + (d.y - v[1]) * k + ")"; });
	    circle.attr("r", function(d) { return d.r * k; });
	  }


	d3.select(self.frameElement).style("height", diameter + "px");

	</script>
	</body>
	</html>
	@) =~ s/^\t//mg;

return $document;
	}
