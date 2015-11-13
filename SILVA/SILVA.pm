package SILVA;
use Carp;
use File::Fetch;
use Data::Dumper;
use PerlIO::gzip;
use File::Basename;
use YAML::Any qw/DumpFile/;
use Digest::MD5 qw /md5_hex/;
use File::Copy;

use warnings;
use strict;

my $VERSION = 0.5;
=pod

=head1 NAME
SILVA.pm

=head1 VERSION
$VERSION

=head1 SYNOPSIS


=head1 METHODS 

=cut

sub new{
=pod 

=head2 new
Creates a new SILVA object

	my $SILVA= new SILVA;


=cut 	
	my ($class , $args) = @_;

	$args->{dir} = '.' unless $args->{dir};
	chop $args->{dir} if $args->{dir}=~/\/$/;


	my $self = {
		DBDIR => $args->{dir}
		};
	$self->{update} = 1 if $args->{update};

	my $object = bless $self , $class;
	$self->fetch();
	return $object;
	}

sub fetch {
=pod

=head2 fetch
Fetches Database

	$SILVA->fetch();

Currently accepts no arguments and only grabs 123 from the current release.

Will update to take a version number/Type and fetch properly.

Need vocab for : version , SSU/LSU , ref99 , trunc , parc ?

Needs to catch errors for files it can't fetch also.
=cut
	my $self  = shift;
	my $SILVA_fasta = File::Fetch->new(uri=>'http://www.arb-silva.de/fileadmin/silva_databases/current/Exports/SILVA_123_SSUParc_tax_silva_trunc.fasta.gz');
	my $LOCAL_fasta = $self->{DBDIR} . '/SILVA_123_SSUParc_tax_silva_trunc.fasta.gz';
	my $SILVA_tax = File::Fetch->new(uri=>'http://www.arb-silva.de/fileadmin/silva_databases/current/Exports/taxonomy/tax_slv_ssu_123.txt');
	my $LOCAL_tax = $self->{DBDIR} . '/tax_slv_ssu_123.txt' ;
	
	$self->{fasta} = $LOCAL_fasta;
	$self->{taxonomy} = $LOCAL_tax;

	unless (-e $LOCAL_fasta || $self->{update}){
		$SILVA_fasta->fetch(to => $self->{DBDIR});
		}
	unless (-e $LOCAL_tax || $self->{update}){
		$SILVA_tax->fetch(to => $self->{DBDIR});
		}
	return;
	}




sub nr_db{
=pod

=head2 nr_db
Reduces the current database to nr100.
Creates the db for this.
Creates a Hash table xref for records. 

	$SILVA->nr_db();

=cut

	my $self = shift;

	my $nr_db = (fileparse($self->{fasta}, qr/.fasta.gz/))[0].'_nr.fasta.gz';
	my $YAML_dump = (fileparse($self->{fasta}, qr/.fasta.gz/))[0] . '.YAML';

	return if (-e $nr_db && -e $YAML_dump && !defined $self->{update});

	open (INC , '<:gzip' , $self->{fasta}) || croak ("Couldn't open $self->{fasta}");
	open (NR , '>:gzip' , $nr_db) || croak ("Couldn't open NR for writing");

	my $header = undef;
	my $sequence = '';
	my $YAML = {};
	while (my $line = <INC>){
		chomp $line;

		if ($line =~/^>/){

			#process whatever $record is currently

			if (defined $header){
				$line=~s/>//;
				carp "New header but no sequence?" unless $sequence;
				$sequence=~tr/Uu/Tt/; #substitute U/T

				#taxonomy parsing 
				my ($accession, $taxonomy) = split(' ',$header,2); 
				my @tax_levels = split(/;/,$taxonomy);
				
				#sequence_hash;
				my $hash = md5_hex($sequence);

				#NEW SEQUENCE , print to file;
				unless (exists $YAML->{$hash}){
					print NR ">$hash\n";
					$sequence =~ s/(.{60})/$1\n/gs;
					print NR "$sequence\n";
					}

				#push info to the XREF;
				push @{$YAML->{$hash}->{accession}} , $accession;
				push @{$YAML->{$hash}->{species}} , $tax_levels[-1];
				push @{$YAML->{$hash}->{genus}} , $tax_levels[-2];
				push @{$YAML->{$hash}->{full_tax}} , $taxonomy;
				}
			
			#reset sequence , set new header;
			$header=$line;
			$sequence='';
			}
		else{
			$sequence.=$line;
			}
		}
	close INC;
	close NR;
	
	#map map reduce arrays
	map {
		my $hash = $_; 
		map{
			@{$YAML->{$hash}->{$_}} = do{my %seen; grep { !$seen{$_}++ } @{$YAML->{$hash}->{$_}} } if @{$YAML->{$hash}->{$_}} > 1;
			}keys %{$YAML->{$hash}};
		} keys %{$YAML};
			

	$YAML_dump = $self->{DBDIR} . "/$YAML_dump";
	DumpFile($YAML_dump,$YAML);
	$self->{fasta} = $nr_db; 
	$self->{taxonomy} = $YAML_dump;	
	return;
	}

	
1;
