#!/usr/bin/perl
use warnings;
use strict;

use FindBin;
use TaxonomyCirclePack;

use Data::Dumper;


my $struct = Viz::D3::TaxonomyCirclePack->new();

$struct->incrementID(866770);
$struct->incrementID(866770,500);

print Dumper $struct;

exit;
