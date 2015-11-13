#!/usr/bin/perl
use warnings;
use Data::Dumper;
use GenBank;


my $file = new Parse::GenBank("/home/dstorey/Desktop/BioPM/Parse/tests/bacteria.290.genomic.gbff.gz");
while (my $record = $file->get_record){

	}

exit();