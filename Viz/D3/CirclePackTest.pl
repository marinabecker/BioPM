#!/usr/bin/perl
use warnings;
use strict;

use FindBin;
use TaxonomyCirclePack;

use Data::Dumper;


my $struct = Viz::D3::TaxonomyCirclePack->new();

open (IN , '<' , 'Kraken.report') || die $!;

while (my $line = <IN>){
	chomp $line;
	my @tmp = split(/\t+/ , $line);
	($tmp[3] eq 'S')?$struct->incrementID($tmp[4] , $tmp[1]) :$struct->incrementID($tmp[4] , $tmp[2]);
	
	}

$struct->flare();

exit;
