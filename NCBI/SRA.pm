package SRA;
use Carp;
use Data::Dumper;
use LWP::Simple;
use XML::Simple;
use File::Fetch;
use File::Which;
use YAML::XS qw/DumpFile LoadFile Dump/; 
use File::Basename;
use File::Spec;

use threads;
use Thread::Semaphore;

#simple locking mechanism to keep connections to a minimum
my $downloads = Thread::Semaphore->new(5);


use DBI;

use warnings;
use strict;

my $Bin = dirname(__FILE__);
my $VERSION = "0.9" ;
=pod
=head1 NAME 
SRA.pm

=head1 VERSION
0.9

=head1 SYNOPSIS
Ways to interface with the SRA and manipulate runs in ways I find meaningful.

=head1 METHODS 
=cut

sub new{
=pod 

=head2 new
Creates a new SRA object

my $SRA = new SRA;
	$SRA->{
		search_string => 'string that should scrape all bacteria'
		DIR => 'working directory',
		search_dump => 'search return YAML',
		sra_dump => 'sra YAML',
		search_term => 'what you searched',
		sample_path => 'where BioSamples are stored'
	}

=cut 	
	my ($class , $args) = @_;
	$args->{DIR} //= $Bin;
	carp ("I need a Directory to work in!") unless ($args->{DIR});
	chop $args->{DIR} if $args->{DIR} =~ /\/$/;
	
	mkdir $args->{DIR} unless -e $args->{DIR};

	my $self = {
		search_string => "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?term=Bacteria&db=sra&usehistory=y&biomol+dna[prop]",
		DIR => $args->{DIR},
		};

	my $object = bless $self , $class;

	$self->{db_file} = "$self->{DIR}/sra.sq3";
	$self->_construct_object();


	return $object;
	}

sub update{
=pod

=head2 update

Updates object variables. Important if database has changed at all.
	
	$SRA->update();

=cut

	my $self = shift;
	unlink $self->{db_file};
	$self->_connect_object;
	$self->get_srr_accessions;
	return;
}



	


sub get_srr_accessions{
=pod

=head2 get_srr_accessions

Processess the search returns, dumps all of the runs to a YAML file of all Experiments.

	$SRA->get_sras(return_max => 1000);

=cut

	my ($self , $args) = @_;

	#max items to return at a time
	$args->{return_max} //= 1000;
	

	#GET ALL EXPERIMENT DATA;	

		#threads for downloading everything
		my @efetch_outs = ();
		my @threads = ();

		my $search_return =  XMLin(get($self->{search_string}));
		DumpFile("$Bin/search_return" , $search_return);
		my $count = $search_return->{Count};
		my $web_enviroment = $search_return->{WebEnv};
		my $query_key = $search_return->{QueryKey};
	 	
	 	print STDERR "Launching Threads!\n";
	 	for (my $retstart = 0; $retstart < $count; $retstart += $args->{return_max}) {
	         my $efetch_url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=sra&WebEnv=$web_enviroment";
	         $efetch_url .= "&query_key=$query_key\&retstart=$retstart";
	         $efetch_url .= "&retmax=$args->{return_max}&rettype=xml&retmode=text";
	         push @threads , threads->create( \&_efetch ,$efetch_url, $retstart , $args->{return_max});
	         select(undef,undef,undef,0.35);
	     	}

	     print STDERR "Threads Launched\n";
	     map{push @efetch_outs , $_->join()} @threads;
	     print STDERR "Threads Closed\n";
	     foreach my $efetch_out(@efetch_outs){
	     		next unless defined $efetch_out;
	     		$efetch_out = XMLin($efetch_out);
	         if (ref ($efetch_out->{EXPERIMENT_PACKAGE}) eq 'ARRAY'){
		         my @experiments = @{$efetch_out->{EXPERIMENT_PACKAGE}};
		         $self->_import_to_sqlite(\@experiments);
		     	}
		     else{
		     	warn "EXPERIMENT PACKAGE ISN'T AN ARRAY!\n";
		     	print Dumper $efetch_out;
		     	}
	        }

	$self->set_genera();
	$self->set_platforms();
	$self->set_species();
	$self->set_taxon_ids();

    return;
	}

#threading downloads in an attempt to get data down from the server faster , but needed to use locks to 
# minimize the  number of requests open at a given time. It isn't documented but it looks like there is a limit on that as well.
 
sub _efetch{
	my $url = shift;
	my $ret_start = shift;
	my $ret_end = shift;
	$downloads->down(1);
	my $return;
	while (! $return){
		$return = get($url);
		}
	my $tid = threads->tid();
	open (OUT , '>' , "/tmp/$tid.txt");
	$return =~s/[^[:ascii:]]+//g;
	print OUT $return;
	my $tries = 0;
	while ( (-z "/tmp/$tid.txt") || $return =~ /<ERROR>Unable to obtain query #1<\/ERROR>/){
		$return = get($url);
		$return =~s/[^[:ascii:]]+//g;	
		print OUT $return;
		$tries++;
		select(undef,undef,undef,0.35);
		if ($tries > 1000){
			warn "Failed fetch\n";
			warn $url."\n";
			$downloads->up(1);
			return;
			}
		}
	$downloads->up(1);
	return $return;
	}

sub _import_to_sqlite{
=pod 

=head2 import_to_sqlite()

Takes the processed runs, strips relevant information and stores it into an sqlite table.

	$SRA->_import_to_sqlite();

=cut

	my ($self , $incoming_set) = @_;

	$incoming_set = [$incoming_set] if (ref($incoming_set) eq 'SCALAR');
	my @rows;

	foreach my $incoming (@{$incoming_set}){
		my $platform = (keys(%{$incoming->{EXPERIMENT}->{PLATFORM}}))[0];
		$platform //= 'NULL';




	 	my $insert ={
	 		run_id => '',
			library_construction_protocol  => '',
			library_strategy  => $incoming->{EXPERIMENT}->{DESIGN}->{LIBRARY_DESCRIPTOR}->{LIBRARY_STRATEGY},
			library_source  => $incoming->{EXPERIMENT}->{DESIGN}->{LIBRARY_DESCRIPTOR}->{LIBRARY_SOURCE},
			project_id  => $incoming->{STUDY}->{accession},
			instrument_model => $incoming->{EXPERIMENT}->{PLATFORM}->{$platform}->{INSTRUMENT_MODEL},
			project => $incoming->{STUDY}->{accession},
			platform => $platform,
			attributes_yaml => '',
			published 	=> '' ,
			spots 		=> '' ,
			n_reads 	=> '' ,
			total_bases => '' ,
			accessed_date => '',
			genus => '',
	      		};
	      	
	      	if (ref($incoming->{EXPERIMENT}->{DESIGN}->{LIBRARY_DESCRIPTOR}->{LIBRARY_CONSTRUCTION_PROTOCOL}) eq 'HASH' || ref($incoming->{EXPERIMENT}->{DESIGN}->{LIBRARY_DESCRIPTOR}->{LIBRARY_CONSTRUCTION_PROTOCOL}) eq 'ARRAY'){
	      		$insert->{library_construction_protocol}=Dump($incoming->{EXPERIMENT}->{DESIGN}->{LIBRARY_DESCRIPTOR}->{LIBRARY_CONSTRUCTION_PROTOCOL});
	      		}
	      	else{
	     	    $insert->{library_construction_protocol}=$incoming->{EXPERIMENT}->{DESIGN}->{LIBRARY_DESCRIPTOR}->{LIBRARY_CONSTRUCTION_PROTOCOL};
	      		}
		#workaround for some of the bizzare multi sample  bio samples
		$insert->{attributes_yaml} = Dump($incoming->{SAMPLE}->{SAMPLE_ATTRIBUTES}->{SAMPLE_ATTRIBUTE}) if (ref $incoming->{SAMPLE} eq "HASH" && exists $incoming->{SAMPLE}->{SAMPLE_ATTRIBUTES}->{SAMPLE_ATTRIBUTE});

#sometimes an experiment has many runs .... 

		$incoming->{RUN_SET}->{RUN} = [$incoming->{RUN_SET}->{RUN}] unless (ref($incoming->{RUN_SET}->{RUN}) eq 'ARRAY');
		      		
	  		map{

	  			# for multiple samples in a single sequencing RUN
	  		   if (ref($_->{Pool}->{Member}) eq 'ARRAY'){
	  		   		#This loop was intended to deal with people who WERE submitting pooled sequencing lanes. (there were biosamples of this type in 2015)
	  		   		#It also was a massive pain in the ass and broke alot so Fuckit.
	  		   		# my $counter = 0;
	  		   		# $insert->{n_reads} = $_->{Statistics}->{nreads} if exists $_->{Statistics}->{nreads};
	  		   		
	  		   		# map{
	  		   		# 	$insert->{run_id} = (exists $incoming->{RUN_SET}->{RUN}->{accession}) ? $incoming->{RUN_SET}->{RUN}->{accession}."\_".$counter : ''; # add a counter to the accession
	  		   		# 	$insert->{experiment_id} = (exists $incoming->{EXPERIMENT}->{IDENTIFIERS}->{accession}) ? $incoming->{EXPERIMENT}->{IDENTIFIERS}->{accession}:'';
	      		 #   		$insert->{scientific_name} = (exists $_->{organism} )? $_->{organism} : ''  ;
	      		 #   		$insert->{genus} = ($insert->{scientific_name})? (split(/\s+/ , $insert->{scientific_name}))[0] : '';
	      		 #   		$insert->{sample_id} =(exists  $_->{accession})? $_->{accession} : '' ;
	      		 #   		$insert->{taxon_id} = (exists $_->{tax_id}) ? $_->{tax_id} : '' ;  
		  	     #   		$insert->{published} = $_->{published} if exists $_->{published};
		  	     #   		$insert->{spots} = $_->{spots} if exists $_->{spots};
		  	     #   		$insert->{total_bases} = $_->{bases} if exists $_->{bases};
		  	     #   		$insert->{barcode} = 'NEEDS DEMULTIPLEX!';
	  		   		# 	$self->{insert}->execute(@{$insert}{@{$self->{fields}}});
	  		   		# 	$counter++;		  	       		
	  		   		# 	}@{$_->{Pool}->{Member}};
	  		   		}
	  		   else {
	      		   $insert->{experiment_id} = $_->{EXPERIMENT_REF}->{accession} if exists  $_->{EXPERIMENT_REF}->{accession} ;
	      		   $insert->{scientific_name} = $_->{Pool}->{Member}->{organism} if exists $_->{Pool}->{Member}->{organism};
	      		   $insert->{genus} = ($insert->{scientific_name})? (split(/\s+/ , $insert->{scientific_name}))[0] : '';
	      		   $insert->{sample_id} = $_->{Pool}->{Member}->{accession} if exists $_->{Pool}->{Member}->{accession};
	      		   $insert->{taxon_id} = $_->{Pool}->{Member}->{tax_id} if exists $_->{Pool}->{Member}->{tax_id};	      		   
	      		   $insert->{run_id} = $_->{accession} if exists $_->{accession};
		  	       $insert->{published} = $_->{published} if exists $_->{published};
		  	       $insert->{spots } = $_->{total_spots} if exists $_->{total_spots};
		  	       $insert->{n_reads} = $_->{Statistics}->{nreads} if exists $_->{Statistics}->{nreads};
		  	       $insert->{total_bases} = $_->{total_bases} if exists $_->{total_bases};
		  	       $insert->{barcode} = '';
		  	       $self->{insert}->execute(@{$insert}{@{$self->{fields}}});
		  	   	   }

	       	} @{$incoming->{RUN_SET}->{RUN}};

		}
	}	


sub get_dbi_handle{
=pod

=head2 _get_dbi_handle
Returns the dbh so you can query directly;

	my $DBI = $SRA->_get_dbi_handle;

=cut
	my $self = shift;
	return $self->{dbh};
	}

sub _construct_object{
# OUR CONSTRUCTOR
	my $self = shift;
	#Create our SQLITE CONNECTION
	$self->{dbh} = DBI->connect(
			"dbi:SQLite:dbname=$self->{DIR}/sra.sq3",
			"",
			"",
			{
				RaiseError => 1,
				sqlite_use_immediate_transaction => 1,
				#AutoCommit => 0
			},
		) || croak ($DBI::errstr);

	$self->{dbh}->do("CREATE TABLE IF NOT EXISTS sra (
		run_id TEXT PRIMARY KEY NOT NULL,
		scientific_name TEXT, 
		taxon_id INT, 
		sample_id TEXT, 
		experiment_id TEXT, 
		published TEXT, 
		spots INT, 
		n_reads INT, 
		total_bases INT, 
		library_construction_protocol TEXT, 
		library_strategy TEXT, 
		library_source TEXT, 
		project_id TEXT, 
		instrument_model TEXT, 
		platform TEXT, 
		accessed_date TEXT,
		attributes_yaml TEXT,
		genus TEXT, 
		barcode TEXT
		)"
	);
	$self->{dbh}->do("PRAGMA cache_size = 20000");
	$self->{dbh}->do("PRAGMA page_size = 4095");
	$self->{dbh}->do("PRAGMA temp_store = memory");
	$self->{dbh}->do("PRAGMA synchronous = off");

	my @fields = qw /run_id scientific_name taxon_id sample_id experiment_id published spots n_reads total_bases library_construction_protocol library_strategy library_source project_id instrument_model platform accessed_date attributes_yaml genus barcode/ ;
	my $field_list = join ", " , @fields;
	my $field_placeholders = join "," , map {'?'} @fields;
	my $insert_query = qq{INSERT OR IGNORE INTO sra ($field_list) VALUES ($field_placeholders)};
	$self->{insert} = $self->{dbh}->prepare($insert_query);
	$self->{fetch_record} = $self->{dbh}->prepare("SELECT * FROM sra WHERE run_id = ?");
	$self->{fields} = \@fields;
	}



sub DESTROY{
	my $self = shift;
	}

sub set_genera{
	my $self = shift;
	my $sth = $self->{dbh}->prepare("SELECT genus FROM sra");
	$sth->execute();
	while (my ($genus) = $sth->fetchrow_array) {
		$self->{genera_in_sra}->{genus}++ if $genus;
		} 
	}
sub get_genera{
	my $self = shift;
	return $self->{genera_in_sra};
	}

sub set_platforms{
	my $self = shift;
	my $sth = $self->{dbh}->prepare("SELECT DISTINCT platform FROM sra");
	$sth->execute();
	while (my ($platform) = $sth->fetchrow_array) {
		$self->{platforms_in_sra}->{$platform}++ if $platform;
		}
	}

sub get_platforms{
	my $self = shift;
	return $self->{platforms_in_sra};
	}

sub set_species{
	my $self = shift;
	my $sth = $self->{dbh}->prepare("SELECT DISTINCT scientific_name FROM sra");
	$sth->execute();
	while (my ($s_name) = $sth->fetchrow_array) {
		$self->{scientific_names_in_sra}->{$s_name}++ if $s_name;
		}
	}

sub get_species{
	my $self = shift;
	return $self->{scientific_names_in_sra};
	}

sub set_taxon_ids{
	my $self = shift;
	my $sth = $self->{dbh}->prepare("SELECT DISTINCT taxon_id FROM sra");
	$sth->execute();
	while (my ($tax_id) = $sth->fetchrow_array) {
		$self->{taxons_in_sra}->{$tax_id}++ if $tax_id;
		} 
	}

sub get_taxon_ids{
	my $self = shift;
	return $self->{taxons_in_sra};
	}


1;





