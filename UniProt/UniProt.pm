package UniProt;
use warnings;
use strict;
use Carp;
use File::Basename;
use File::Fetch;
use Digest::MD5 qw /md5_hex/;
use YAML::Any qw/DumpFile/;
use PerlIO::gzip;
use File::Which;

use Data::Dumper;

my $VERSION = '0.5';
=pod

=head1 UniProt.pm

=head1 VERSION $VERSION

=head1 DEPENDS

	File::Basename

	WWW::Curl

	WWW::Curl::Easy

	Digest::MD5

	YAML::Any

	PerlIO::gzip

	File::Which

=head1 SYNOPSIS

Fetching and building databases from the UniProt Database. 

=head1 METHODS 

=cut

#should probably find a way to programmatically fetch this info , for now it's hard coded.
my $available_current = {
	"uniprot_sprot_archaea" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_archaea.dat.gz",
	"uniprot_sprot_bacteria" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_bacteria.dat.gz",
	"uniprot_sprot_fungi" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_fungi.dat.gz",
	"uniprot_sprot_human" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_human.dat.gz",
	"uniprot_sprot_invertebrates" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_invertebrates.dat.gz",
	"uniprot_sprot_mammals" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_mammals.dat.gz",
	"uniprot_sprot_plants" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_plants.dat.gz",
	"uniprot_sprot_rodents" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_rodents.dat.gz",
	"uniprot_sprot_vertebrates" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_vertebrates.dat.gz",
	"uniprot_sprot_viruses" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_sprot_viruses.dat.gz",
	"uniprot_trembl_archaea" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_archaea.dat.gz",
	"uniprot_trembl_bacteria" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_bacteria.dat.gz",
	"uniprot_trembl_fungi" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_fungi.dat.gz",
	"uniprot_trembl_human" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_human.dat.gz",
	"uniprot_trembl_invertebrates" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_invertebrates.dat.gz",
	"uniprot_trembl_mammals" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_mammals.dat.gz",
	"uniprot_trembl_plants" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_plants.dat.gz",
	"uniprot_trembl_rodents" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_rodents.dat.gz",
	"uniprot_trembl_unclassified" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_unclassified.dat.gz",
	"uniprot_trembl_vertebrates" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_vertebrates.dat.gz",
	"uniprot_trembl_viruses" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/taxonomic_divisions/uniprot_trembl_viruses.dat.gz",
	"uniprot_sprot" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.dat.gz",
	"uniprot_trembl" => "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_trembl.dat.gz"
	};



sub new {
=pod 

=head2 new

Creates a new object to work on , accepts a directory path for database storage. Defaults to '.'.

	my $UNIPROT =  new UniProt($DBDIR);

=cut
	my ($class , $DBDIR) = @_;
	$DBDIR //= '.';
	mkdir $DBDIR || croak $! unless -d $DBDIR;
	my $self = {
		DBDIR => $DBDIR,
		net_available => $available_current,
		local_available => {},
		current_db_name => ''
		};
	my $object = bless $self, $class;

	$self->local_available();
	return $object;
	}

sub combine_db{
=pod 

=head1 combine_db

Combines multiple named uniprotdbs into one database.

	$UNIPROT->combine_db(combine => ["uniprot_sprot","uniprot_tremble"] , name => "AllTheUniProt");

=cut
	my $self = shift;
	my $args = shift;
	open (COM , '>:gzip' , "$self->{DBDIR}/$args->{name}.dat.gz") || croak ("$self->{DBDIR}/$args->{name}.dat.gz");
	
	foreach my $file (@{$args->{combine}}){
		$self->fetch($file) unless (-e "$self->{DBDIR}/$file.dat.gz");
		open (DAT , '<:gzip' , "$self->{DBDIR}/$file.dat.gz") || die $!;
		while (<DAT>){
			print COM $_;
			}
		close DAT;
		}
	close COM;
	$self->local_available();
	$self->set_current_db_name($args->{name});
	$self->nr100();
	$self->update_files();
	return;
	}

sub set_current_db{
=pod 

=head2 set_db	

Sets the DB that you're using

	$UNIPROT->set_db("uniprot_sprot_archaea")

=cut

	my $self = shift;
	my $name = shift;

	my $base_path = join ('/',($self->{DBDIR}/$self->{$name}));
	my $outputs = {
		'yaml' => $base_path .'.YAML',
		'dat' =>  $base_path . '.dat.gz',
		'fasta' => $base_path .'_nr100.fasta.gz',
		'diamond' => $base_path .'.dmnd'
		};

	if (exists $self->{local_available}->{$name}){
		$self->{current_db_name} = $name;	
		}
	elsif(exists $self->{net_available}->{$name}){
		$self->{current_db_name} = $name;
		}
	else{
		carp("$name , doesn't appear to exist in $self->{DBDIR}");
		}
	$self->update_files();
	return;
}
sub update_files{
=pod 

=head1 update_files
Updates file names from the current_db_name variable

=cut
	my $self = shift;
	my $base_path = join ('/',($self->{DBDIR},$self->{current_db_name}));
	my $outputs = {
		'yaml' => $base_path .'.YAML',
		'dat' =>  $base_path . '.dat.gz',
		'fasta' => $base_path .'_nr100.fasta.gz',
		'diamond' => $base_path .'.dmnd'
		};

	map { $self->{$_} = $outputs->{$_} if (-e $outputs->{$_})} keys %{$outputs};

	return;
	}

sub fetch{
=pod 

=head2 fetch

Downloads a named database from UniProt. 

	$UNIPROT->fetch('uniprot_sprot_bacteria');

=cut
	my $self = shift;
	my $name = shift;
	my $fetch = File::Fetch->new(uri=> $self->{net_available}->{$name});
	$self->set_current_db_name($name);
	if (exists $self->{net_available}->{$name}){
		return if (-e "$self->{DBDIR}/$name.dat.gz");
		my $where = $fetch->fetch(to => $self->{DBDIR}) ;		
		}
	else{
		croak("$name isn't a valid name , try any of the following : ". Dumper $self->{net_available} . "\n");
		}
	$self->update_files();
	return;
	}


sub local_available{
=pod 

=head2 local_available

Updates the internal local_available variable and returns the hash if a user wants it.

	$UNIPROT->local_available();
=cut
	my @return;
	my $self = shift;
	my $DBDIR = $self->{DBDIR};
	my $local_available = {};
	map{ $local_available->{(fileparse($_, qr/.dat.gz/))[0]} = $_} <$DBDIR/*dat.gz>;
	$self->{local_available}=$local_available;
	$self->update_files();
	return $local_available;
	}

sub nr100{
=pod 

=head2 nr100

Creates an nr100 FASTA database from the current_db_name. Also creates an XREF YAML file with extra information.

	$UNIPROT->nr100();

The YAML FILE contains the following info:

```yaml
"md5_hash":
	'AC':
		- Uniprot accesion 		
	'SO_simple':
		- Genus species
	'SO': 		
		- full species (strain info)
	'GO': 
		- GO terms
	'KO': 		
		- Kegg Ontologies
	'GEN':		
		- Genus
```
=cut

	my $self = shift;
	my $COUNTER = 0;
	my %sequences;
	my $YAML = {};

	my $path = join ('/', ($self->{DBDIR} , $self->{current_db_name}));
	#File paths
	my $dat = $path . ".dat.gz";
	my $fasta = $path . "_nr100.fasta.gz";
	my $yaml = $path . ".YAML";

	return if (-e $fasta && -e $yaml && -e $dat);

	$self->fetch($self->{current_db_name}) unless ( -e $dat);

	open(DAT , "<:gzip" , $dat) || croak ("Couldn't open $dat");
	open(FASTA, ">:gzip",$fasta) || croak ("Couldn't open $fasta for writing");
	local $/ = "\n\/\/"; 
	while (my $record = <DAT>){
		chomp $record;
		next unless $record; next if $record =~/^\s+$/; #skip empy and blank records
		next if $record =~ /DE   Flags: Fragment(s)?;/; #skips explicit fragments
		
		#Get our sequence out
		my $sequence = '';
		$sequence = $1 if ($record=~/SQ\s.*;\n([\t[A-Z|\s+]+\s*]*)/g);
		$sequence =~ s/\s//g;
		my $hash = md5_hex($sequence);
		#DUMP new stuff
		unless (exists $YAML->{$hash}){
			print FASTA ">$hash\n";
			$sequence =~ s/(.{60})/$1\n/gs;
			print FASTA $sequence . "\n";
			}

		#Get the AC line
		my $AC;
		$AC = $1 if ($record=~/AC\s+([OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2});\n/);

		#GET ANY KEGG numbers
		my @KO = ();
		push @KO ,$1 while ($record =~/DR\s+KO; ([^\s]+);.*/g);

		#GET GO
		my @GO = ();
		push @GO ,$1 while ($record =~/DR\s+GO; ([^\s]+);.*/g);		
		
		#GET Species
		my @SO;
		my $SO = $1 if ($record =~/[^S]OS\s+(.*)/g);
		$SO =~s/OS\s+//g;
		$SO =~s/\.//g;
		chomp $SO;

		#Make Genus 
		#Make Simple Species
		my $SO_simple = $SO;
		$SO_simple = "$1" if ($SO =~/([A-Za-z0-9]+\s+[A-Za-z0-9]+)\s+/);

		my $GEN = (split(/\s+/ , $SO_simple))[0];
		

		#CHECK AND NEXT 
		carp "Record $AC , doesn't appear to have a sequence!\n" unless $sequence;
		next unless ($sequence);

		push @{$YAML->{$hash}->{'AC'}} 			, $AC if $AC;
		push @{$YAML->{$hash}->{'SO_simple'}}	, $SO_simple if $SO_simple;		
		push @{$YAML->{$hash}->{'SO'}} 			, $SO if $SO;
		push @{$YAML->{$hash}->{'GO'}} 			, @GO if @GO;
		push @{$YAML->{$hash}->{'KO'}} 			, @KO if @KO;
		push @{$YAML->{$hash}->{'GEN'}}			, $GEN if $GEN;

		map {
			@{$YAML->{$hash}->{$_}} = do {my %seen; grep { !$seen{$_}++ } @{$YAML->{$hash}->{$_}} } if( exists $YAML->{$hash}->{$_} && @{$YAML->{$hash}->{$_}} > 1);
			} keys %{$YAML->{$hash}}

		}

	close FASTA;
	DumpFile($yaml,$YAML);
	$self->update_files();
	return;
	}

sub compile_db{
=pod 

=head2 compile_db

Compiles the UNIPROT fasta database using the selected program. Assumes that the program is in $PATH , or provided through bin.

	$UNIPROT->scompile_db(name => 'uniprot_sprot_bacteria', type => 'diamond',bin =>'optional full path to bin')

=cut
	my $self = shift;
	my $args = shift;

	my $fasta = join('/',($self->{DBDIR},$self->{current_db_name})) . "_nr100.fasta.gz";
	my $builds = {
			'diamond' => {
				command => "$args->{bin} makedb --in $fasta -d ".join('/',($self->{DBDIR},$self->{current_db_name}))." -b 10",
				return => join('/',($self->{DBDIR},$self->{current_db_name})).'.dmnd',
				bin => 'diamond'
				},
			'blast2	' => {
				command => "gunzip -c $fasta | $args->{bin} -in - -dbtype prot -title $self->{current_db_name} -out $self->{current_db_name}",
				return => join('/',($self->{DBDIR},$self->{current_db_name})),
				bin => 'makeblastdb'
				},
			'usearch' =>{
				usearch =>
				return =>
				bin =>'usearch'
				}
			};


	$args->{bin} //= $builds->{$args->{type}}->{bin}; # get the default if no bin was passed

	my $bin_path = which($args->{bin}); #returns undef if not in path

	if ($bin_path && -x $args->{bin}){ #two possible , default to passed
		$args->{bin} = $args->{bin};
		}
	elsif($bin_path){ # set it to PATH
		$args->{bin} = $bin_path;
		}
	elsif(-x $args->{bin}){
		$args->{bin} = $args->{bin};
		} 
	else{	
		croak ("Couldn't find the executable in your path OR not able to execute it: $args->{bin}");
		}

	#system call
	system($builds->{$args->{type}}->{command}) == 0 || croak "system call $builds->{$args->{type}}->{command} failed \n \t return $?\n";

	#returns a path to whatever the searching program needs
	$self->update_files();
	return $builds->{return}->{$args->{type}};
	
	}


1;