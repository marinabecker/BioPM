package Muscle;
require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(align_file);
use warnings;
use strict;
use File::Which;
use File::Spec;
use File::Basename;
use File::Copy qw/move/;
use Carp;



sub align_file{
=pod
=head2 align_file()

Aligns a file using MUSCLE if a file with the same name already exists will complete a profile profile alignment.

	align_file(
		file => '/path/to/file.faa',
		clean => '0|1',
		fresh => '0|1',
		bin => '/path/to/bin'
		)
=cut
	my %args  = ( @_ && ref $_[0] eq 'HASH' ) ? %{ $_[0] } : @_; 
	
	$args{bin} //= '/usr/bin/muscle';
	unless (-x $args{bin}){
		carp "$args{bin} doesn't appear to be an executable file!";
		return;
		}

	$args{clean} //= 1;
	
	$args{fresh} //= 1;

	$args{file} = File::Spec->rel2abs($args{file});

	
	my ($out,$path,$ext) = fileparse($args{file} ,  qr/\.[^.]*/); 
	$out = "$path$out.aln";
	unlink ($out) if ($args{fresh} && -e $out);



	if (-e $out){ #use profile profile alignment to keep things clean (only works if you didn't get fresh)
		if (system("muscle -in $args{file} -out $args{file}.tmp -maxiters 2 2> /dev/null")==0){
			unlink ($args{file}) if $args{clean} eq '1';
			if (system("muscle -profile -in1 $out -in2 $args{file}.tmp -out $args{file}.comb -maxiters 2  2> /dev/null") == 0){
				unlink("$args{file}.tmp");
				move("$args{file}.comb" , "$out") || croak("Failed to move profile-profile alignment to its new home!");
			
				}
			else{

				}
			}
		else{
			carp("Muscle Failed to align $args{file} : $?");

			}
		}
	else { #do a fresh alignment;
		if (system("muscle -in $args{file} -out $out -maxiters 2 2> /dev/null") == 0){

			}
		else{
			carp("Muscle Failed to align $args{file} :  $?");

			}
		}
return;
		}



1;