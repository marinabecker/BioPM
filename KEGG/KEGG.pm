package KEGG;
use Carp;
use Data::Dumper;


use warnings;
use strict;
use File::Fetch;
use File::Copy;
use File::Basename;
use Digest::MD5 qw /md5_hex/;
use YAML::Any qw/DumpFile LoadFile/;
use XML::Simple;
use List::MoreUtils qw/any/;

#use GD::Simple;

my $VERSION = '0.1';




my $available = load_KGML_tree();


=pod

=head1 NAME 
KEGG.pm

=head1 VERSION 
$VERSION

=head1 SYNOPSIS

=head1 METHODS 

=cut

=pod 

=head1 The KGML_tree structure.

This is stored in the PATHWAYS hash of the KEGG object. Access directly the KEGG object via:

	my $KEGG = new KEGG ;
	my $KGML_tree = $KEGG->{PATHWAYS};

Data is structured thus:
	$KGML->{
		groups => [names of paths in group],
		paths => {
			pathway name => [list of kos in path],
			}
		}

It would be really nice to automate the construction of this from the KEGG website or API but I haven't been clever enough to figure it out. 

=cut

sub new{
=pod 

=head2 new

	my $KEGG =   new KEGG;

=cut 	
	my ($class , $DBDIR) = @_;
	mkdir $DBDIR || croak $! unless -d $DBDIR;
	my $self = {
		DBDIR => $DBDIR,
		PATHWAYS => load_KGML_tree(),
		KO2RN => {}, #maps K0 to reanctions
		RN2MAP => {}, #mapts RN to maps 
		RNPATH => {},
		};
	my $object = bless $self , $class;
	$self->net_available_pathways();
	$self->load_KO_2_reaction();
	return $object;
	}


sub ko2rn {
	my $self = shift;
	my $id = shift;
	return [$self->{KO2RN}->{$id}] if (exists $self->{KO2RN}->{$id});
	return [];
	}

sub rn2map{
	my $self = shift;
	my $id = shift;
	return [$self->{RN2MAP}->{$id}] if (exists $self->{RN2MAP}->{$id});
	return [];
	}

sub load_KO_2_reaction{
	#add a YAML dump/load routine if a YAML file is/isn't found.
	my $self = shift;
	my $force = '';
	$force = shift if @_ > 0;
	if ($force eq 'force'){
		unlink("$self->{DBDIR}/KO2RN.YAML") || croak($!) if -e "$self->{DBDIR}/KO2RN.YAML" ;
		unlink("$self->{DBDIR}/RN2MAP.YAML") || croak ($!) if -e "$self->{DBDIR}/RN2MAP.YAML";
		}
	if (-e "$self->{DBDIR}/KO2RN.YAML"){
		$self->{KO2RN} = LoadFile("$self->{DBDIR}/KO2RN.YAML");
		}
	if (-e "$self->{DBDIR}/RN2MAP.YAML"){
		$self->{RN2MAP} = LoadFile("$self->{DBDIR}/RN2MAP.YAML");
		}
	else{
		opendir(my $dh , $self->{DBDIR}) || croak ("Couldn't open handle to $self->{DBDIR}");
		my @KGMLs = readdir($dh);
		foreach my $file (@KGMLs){
			unless ($file eq '.' || $file eq '..' || -z "$self->{DBDIR}/$_" || any {$file eq "$_.kgml"} @{$self->{PATHWAYS}->{paths}->{global_and_overview_maps}}){ 
				croak("$file doesn't exist") unless (-e "$self->{DBDIR}/$_");
				my $xml_ref = XMLin("$self->{DBDIR}/$file") || croak("Couldn't read $self->{DBDIR}/$file");
				foreach my $key (keys %{$xml_ref->{entry}}){
					while ($key=~/ko:(K\d+)/g){
						my $ko = $1;
						if (exists $xml_ref->{entry}->{$key}->{reaction}){
							while ($xml_ref->{entry}->{$key}->{reaction}=~/rn:(R\d+)/g){
								push @{$self->{KO2RN}->{$ko}} , $1;
								push @{$self->{RN2MAP}->{$1}} , $file;
								}
							}
						}
					}
				}
			}

		map{
			@{$self->{RN2MAP}->{$_}} = do {my %seen; grep { !$seen{$_}++ } @{$self->{RN2MAP}->{$_}} };
			} keys %{$self->{RN2MAP}};

		map {
			@{$self->{KO2RN}->{$_}} = do {my %seen; grep { !$seen{$_}++ } @{$self->{KO2RN}->{$_}} };
			} keys %{$self->{KO2RN}};
		
		DumpFile("$self->{DBDIR}/KO2RN.YAML" , $self->{KO2RN});
		DumpFile("$self->{DBDIR}/RN2MAP.YAML" , $self->{RN2MAP});
		}
	return;
	}

sub net_available_pathways{
=pod 

=head2 net_available_pathways

Returns a hash containing the pathway ids and names of all available KEGG pathways, use for finding new stuff and yelling for an update.
	
	$KEGG->net_available_pathways();

=cut

my $self = shift;
my $return ={};
map{
	map{
		$return->{$_}++;
		}@{$self->{PATHWAYS}->{paths}->{$_}}
	}keys %{$self->{PATHWAYS}->{paths}};
$self->{net_available_pathways} = $return;
return;

}

sub local_avail_pathways{
=pod 

=head2 local_available_pathways

Returns a list of the locally available pathways;

	print Dumper $KEGG->local_avail_pathways();
=cut
	my $self = shift;
	my $DBDIR = $self->{DBDIR};
	my $return = [];
	map{ push @{$return}, "\t ".fileparse($_, qr/\.[^.]*/)."\n"} <$DBDIR/*kgml>;
	return $return;
	}

sub fetch_kgml{
=pod 

=head2 fetch_kgml

Fetches a KGML from the KEGG server.

	$KEGG->fetch('ko10223')
=cut
	my $self = shift;
	my $name = shift;
	my $net_path = "http://rest.kegg.jp/get/$name/kgml";
	my $fetch = File::Fetch->new(uri => $net_path);
	my $file_name = $name . '.kgml';
	return if (-e "$self->{DBDIR}/$name.kgml");
	if (exists $self->{net_available_pathways}->{$name}){
		my $file = $fetch->fetch(to => $self->{DBDIR}) || carp ("$name doesn't appear to exist ?");
		my ($name,$path,$suffix) = fileparse($file);
		move($file , $path.$file_name) || carp ("Couldn't move $fetch to $file_name!");
		}
	else{
		carp("$name doesn't appear to be a valid pathway\n");
		}
	}

sub fetch_all_kgml{
=pod 

=head2 fetch_all_kgml

Fetches all available KGMLs from the KEGG server

	$KEGG->fetch_all_kgml();

=cut
	my $self = shift;
	map{
		map{
			$self->fetch_kgml($_);
			}@{$self->{PATHWAYS}->{paths}->{$_}};
		}keys %{$self->{PATHWAYS}->{paths}};
	return;
	}

sub fetch_group_kgml{
=pod 

=head2 fetch_group_kgml

Fetches a group of KGMLs from the KEGG server

	$KEGG->fetch_group_kgml('metabolism');
	$KEGG->fetch_group_kgml('substance_dependece');

If you pass 'all' or 'paths' , it will simply invoke fetch_all_kgml()

=cut
	my $self = shift;
	my $group = shift;
	carp("No such map grouping $group") unless (exists $self->{PATHWAYS}->{$group} || exists $self->{PATHWAYS}->{paths}->{$group});

	if ($group eq 'all' || $group eq 'paths'){
		$self->fetch_all_kgml();
		return;
		}
	if (exists $self->{PATHWAYS}->{$group}){
		map{
			map{
				$self->fetch_kgml($_);
				}@{$self->{PATHWAYS}->{paths}->{$_}};
			}@{$self->{PATHWAYS}->{$group}};
		}
	elsif (exists $self->{PATHWAYS}->{group}){
		map {
			$self->fetch_kgml($_);
			}@{$self->{PATHWAYS}->{paths}->{$group}}
		}
	else{
		confess("Somehow managed to fall through !");
		}
	return;
	}

sub list_paths{
=pod 

=head2 list_paths

Returns a list of the paths in paths variable , may seem a little circular.

	print Dumper $KEGG->list_paths()


=cut
	my $self = shift;
	my $return = [];
	@$return = keys %{$self->{PATHWAYS}->{paths}};
	return $return;
	}

sub list_groups{
=pod 

=head2 list_groups

Returns a list of the groups of paths available.


	print Dumper $KEGG->list_groups();

=cut
	my $self = shift;
	my $return = [];
	@$return =  keys %{$self->{PATHWAYS}};
	return $return;
	}
	

sub load_KGML_tree{
	my $KGML = {
		global_and_overview_maps => ['global_and_overview_maps'] ,
		metabolism => [	
			'carbohydrate_metabolism',
			'energy_metabolism',
			'lipid_metabolism',
			'nucleotide_metabolism',
			'amino_acid_metabolism',
			'metabolism_of_other_amino_acids',
			'glycan_biosynthesis_and_metabolism',
			'metabolism_of_cofactors_and_vitamins',
			'metabolism_of_terpenoids_and_polyketides',
			'biosynthesis_of_other_secondary_metabolites',
			'xenobiotics_biodegradation_and_metabolism'
			#'chemical_structure_transformation_maps' <---no kgml
			] ,
		genetic_information_processing => [
			'translation',
			'folding_sorting_and_degradation',
			'replication_and_repair',
			]  ,
		environmental_information_processing => [
			'membrane_transport',
			'signal_transduction',
			'signaling_molecules_and_interaction'
			]  ,
		cellular_processes => [
			'transport_and_catabolism',
			'cell_motility',
			'cell_growth_and_death',
			'cellular_community'
			]  ,
		organismal_systems => [
			'immune_system',
			'endocrine_system',
			'circulatory_system',
			'digestive_system',
			'excretory_system',
			'nervous_system',
			'sensory_system',
			'development',
			'environmental_adaptation'
		] ,
		human_diseases => [
			'cancers_overview',
			'cancers_specific_types',
			'immune_diseases',
			'neurodegenerative_diseases',
			'substance_dependence',
			'cardiovascular_diseases',
			'endocrine_and_metabolic_diseases',
			'infectious_diseases_bacterial',
			'infectious_diseases_viral',
			'infectious_diseases_parasitic',
			'drug_resistance'
		] ,
		paths => {
			'global_and_overview_maps' => [qw / ko01100 ko01110 ko01120 ko01130 ko01200 ko01210 ko01212 ko01230 ko01220 /],
			'carbohydrate_metabolism' => [qw / ko00010 ko00020 ko00030 ko00040 ko00051 ko00052 ko00053 ko00500 ko00520 ko00620 ko00630 ko00640 ko00650 ko00660 ko00562 /],
			'energy_metabolism' => [qw / ko00190 ko00195 ko00196 ko00710 ko00720 ko00680 ko00910 ko00920 /],
			'lipid_metabolism' => [qw / ko00061 ko00062 ko00071 ko00072 ko00073 ko00100 ko00120 ko00121 ko00140 ko00561 ko00564 ko00565 ko00600 ko00590 ko00591 ko00592 ko01040 /],
			'nucleotide_metabolism' => [qw / ko00230 ko00240 /],
			'amino_acid_metabolism' => [qw / ko00250 ko00260 ko00270 ko00280 ko00290 ko00300 ko00310 ko00330 ko00340 ko00350 ko00360 ko00380 ko00400 /],
			'metabolism_of_other_amino_acids' => [qw / ko00410 ko00430 ko00440 ko00450 ko00460 ko00471 ko00472 ko00473 ko00480 /],
			'glycan_biosynthesis_and_metabolism' => [qw / ko00510 ko00513 ko00512 ko00514 ko00532 ko00534 ko00533 ko00531  ko00563  ko00601 ko00603 ko00604 ko00540 ko00550 ko00511 /],
			'metabolism_of_cofactors_and_vitamins' => [qw / ko00730 ko00740 ko00750 ko00760 ko00770 ko00780 ko00785 ko00790  ko00670  ko00830 ko00860 ko00130 /],
			'metabolism_of_terpenoids_and_polyketides' => [qw / ko00900 ko00902 ko00909 ko00904 ko00906 ko00905 ko00981 ko00908  ko00903 ko00281 ko01052 ko00522 ko01051 ko01056 ko01057 ko00253 ko00523 ko01054 ko01053 ko01055 /],
			'biosynthesis_of_other_secondary_metabolites' => [qw / ko00940 ko00945 ko00941 ko00944 ko00942 ko00943 ko00901  ko00403  ko00950 ko00960 ko01058 ko00232 ko00965 ko00966 ko00402 ko00311 ko00332 ko00261 ko00331 ko00521  ko00524 ko00231  ko00401 ko00254 /],
			'xenobiotics_biodegradation_and_metabolism' => [qw / ko00362 ko00627 ko00364 ko00625 ko00361 ko00623 ko00622  ko00633  ko00642 ko00643 ko00791 ko00930 ko00351 ko00363 ko00621 ko00626 ko00624 ko00365 ko00984 ko00980  ko00982 ko00983 /],
			'chemical_structure_transformation_maps' => [qw / ko01010 ko01060 ko01061 ko01062 ko01063 ko01064 ko01065 ko01066  ko01070 	/],
			'transcription' => [qw / ko03020 ko03022 ko03040 /],
			'translation' => [qw / ko03010 ko00970 ko03013 ko03015 ko03008 /],
			'folding_sorting_and_degradation' => [qw / ko03060 ko04141 ko04130 ko04120 ko04122 ko03050 ko03018 /],
			'replication_and_repair' => [qw / ko03030 ko03410 ko03420 ko03430 ko03440 ko03450 ko03460 /],
			'membrane_transport' => [qw / ko02010 ko02060 ko03070 /],
			'signal_transduction' => [qw / ko02020 ko04014 ko04015 ko04010 ko04013 ko04011 ko04012 ko04310 ko04330 ko04340  ko04350  ko04390 ko04391 ko04370 ko04630 ko04064 ko04668 ko04066 ko04068 ko04020 ko04070 ko04071 ko04024  ko04022 ko04151  ko04152 ko04150 ko04075 /],
			'signaling_molecules_and_interaction' => [qw / ko04080 ko04060 ko04512 ko04514 /],
			'transport_and_catabolism' => [qw / ko04144 ko04145 ko04142 ko04146 ko04140 /],
			'cell_motility' => [qw / ko02030 ko02040 ko04810 /],
			'cell_growth_and_death' => [qw / ko04110 ko04111 ko04112 ko04113 ko04114 ko04210 ko04115 /],
			'cellular_community' => [qw / ko04510 ko04520 ko04530 ko04540 ko04550 /],
			'immune_system' => [qw / ko04640 ko04610 ko04611 ko04620 ko04621 ko04622 ko04623 ko04650 ko04612 ko04660 ko04662  ko04664  ko04666 ko04670 ko04672 ko04062 /],
			'endocrine_system' => [qw / ko04911 ko04910 ko04922 ko04923 ko04920 ko03320 ko04912 ko04913 ko04915 ko04914 ko04917  ko04921 ko04918 ko04919 ko04916 ko04614 /],
			'circulatory_system' => [qw / ko04260 ko04261 ko04270 /],
			'digestive_system' => [qw / ko04970 ko04971 ko04972 ko04976 ko04973 ko04974 ko04975 ko04977 ko04978 /],
			'excretory_system' => [qw / ko04962 ko04960 ko04961 ko04964 ko04966 /],
			'nervous_system' => [qw / ko04724 ko04727 ko04725 ko04728 ko04726 ko04720 ko04730 ko04723 ko04721 ko04722 /],
			'sensory_system' => [qw / ko04744 ko04745 ko04740 ko04742 ko04750 /],
			'development' => [qw / ko04320 ko04360 ko04380 /],
			'environmental_adaptation' => [qw / ko04710 ko04713 ko04711 ko04712 ko04626 /],
			'cancers_overview' => [qw / ko05200 ko05230 ko05231 ko05202 ko05206 ko05205 ko05204 ko05203 /],
			'cancers_specific_types' => [qw / ko05210 ko05212 ko05214 ko05216 ko05221 ko05220 ko05217 ko05218 ko05211 ko05219  ko05215  ko05213 ko05222 ko05223 /],
			'immune_diseases' => [qw / ko05310 ko05322 ko05323 ko05320 ko05321 ko05330 ko05332 ko05340 /],
			'neurodegenerative_diseases' => [qw / ko05010 ko05012 ko05014 ko05016 ko05020 /],
			'substance_dependence' => [qw / ko05030 ko05031 ko05032 ko05033 ko05034 /],
			'cardiovascular_diseases' => [qw / ko05410 ko05412 ko05414 ko05416 /],
			'endocrine_and_metabolic_diseases' => [qw / ko04940 ko04930 ko04932 ko04950 /],
			'infectious_diseases_bacterial' => [qw / ko05110 ko05111 ko05120 ko05130 ko05132 ko05131 ko05133 ko05134 ko05150  ko05152  ko05100 /],
			'infectious_diseases_viral' => [qw / ko05166 ko05162 ko05164 ko05161 ko05160 ko05168 ko05169 /],
			'infectious_diseases_parasitic' => [qw / ko05146 ko05144 ko05145 ko05140 ko05142 ko05143 /],
			'drug_resistance' => [qw / ko01501 ko01502 ko01503 /]
			}
	};
	return $KGML;
	}
1;
