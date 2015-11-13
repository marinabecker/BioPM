package Parse::GenBank;
use Carp;

use File::Spec;
use Parse::RecDescent;
use IO::Uncompress::AnyUncompress;

use warnings;
use strict;

my $GBK_SEPARATOR = "//\n";




sub new{
=pod 

=head2 new

    my $GBK = new GBK (file => "path_to_file");

=cut    
    my $class = shift;
    my $file = shift;

    $file = File::Spec->rel2abs($file);
    croak("No file provided ") unless $file;
    croak("$file doesn't exist") unless -e $file;

    my $self = {
    	file => $file,
    	parser => Parse::RecDescent->new( _grammar() ),
        FH => new IO::Uncompress::AnyUncompress $file    	
    	};

    my $object = bless $self, $class;
    return $object;
    }



sub slurp{
=pod 

=head2 slurp()
Processes the entire GBK file into a unified hash structure. This function 
makes serious assumptions about merging data. Only use if you're confident in no 
collisions. (IN GENERAL YOU SHOULDNT USE THIS);

    $GBK->slurp();

=cut
    my $self = shift;
    my $return;

    while (my $chunk = $self->get_record){
        map{
            if (ref $chunk->{$_} eq 'ARRAY'){
                push (@{$return->{$_}} , @{$chunk->{$_}});
                }
            elsif (ref $chunk->{$_} eq 'SCALAR'){
                push (@{$return->{$_}} , $chunk->{$_});
                }
            elsif (ref $chunk->{$_} eq 'HASH'){
                push (@{$return->{$_}} , $chunk->{$_});
                }
            elsif (!defined ref $chunk->{$_}){
                unless ($return->{$_} eq $chunk->{$_}){
                    carp("$chunk->{$_} doesn't match $return->{$_}");
                    }
                }
            }keys %{$chunk};
        }
    $self->{serial} = $return;
    return $return;
    }

sub get_record{
=pod 

=head2 get_record
Gets a chunk of GBK text and returns the parsed version;

=cut
    my $self = shift;
    my $parsed;
    if (my $FH =  $self->{FH}){
        local $/ = $GBK_SEPARATOR;
        my $record;

        #Read on file until we get text or hit the end;
        while (1){ 
            $record = <$FH>;
            last if !defined $record || $record =~ /\S+/;
            }
        if (defined $record && $record =~/\S+/){
            $parsed = $self->{parser}->startrule($record);
            map{

                if (exists $_->{location} && exists $_->{SEQUENCE}){
                    if ($_->{location} =~/^complement\((\d+)\.\.(\d+)\)$/){
                        my $length = $2 - $1;
                        $_->{nt_seq} = substr($parsed->{SEQUENCE},$1,$length);
                        $_->{nt_seq} = reverse($_->{nt_seq});
                        $_->{nt_seq} =~tr/ATGCatgc/TACGtacg/;
                        }
                    elsif ($_->{location} =~ /^(\d+)\.\.(\d+)$/){
                        my $length = $2 - $1;
                        $_->{nt_seq} = substr($parsed->{SEQUENCE},$1,$length);
                        }
                    elsif ($_->{location} =~/^(\d+)$/){
                        $_->{nt_seq} = substr($parsed->{SEQUENCE},$1,1);
                        }
                    else{
                        carp("complex genes not supported for nt_inclusion");
                        }   
                    }
                }@{$parsed->{FEATURES}};
            }
        else{
            return undef;
            }
        }

    return $parsed;
    }

sub _grammar {

=pod

=head2 grammar

Parse::RecDescent Grammar , base courtesy of Ken Youens-Clark significant improvements have been made as we break it

=cut


    return <<'END_OF_GRAMMAR';
{
    my $ref_num  = 1;
    my %record   = ();
    my %ATTRIBUTE_PROMOTE = map { $_, 1 } qw[ 
        mol_type 
        cultivar 
        variety 
        strain 
    ];

    $::RD_ERRORS; # report fatal errors
#    $::RD_TRACE  = 0;
#    $::RD_WARN   = 0; # Enable warnings. This will warn on unused rules &c.
#    $::RD_HINT   = 0; # Give out hints to help fix problems.
}

startrule: section(s) eofile 
    { 
        if ( !$record{'ACCESSION'} ) {
            $record{'ACCESSION'} = $record{'LOCUS'}->{'genbank_accession'};
        }

        if ( ref $record{'SEQUENCE'} eq 'ARRAY' ) {
            $record{'SEQUENCE'} = join('', @{ $record{'SEQUENCE'} });
        }

        $return = { %record };
        %record = ();
    }
    | <error>

section: commented_line
    | header
    | locus
    | dbsource
    | definition
    | accession_line
    | project_line
    | version_line
    | dblink
    | keywords
    | source_line
    | organism
    | reference
    | features
    | base_count
    | contig
    | origin
    | comment
    | record_delimiter
    | <error>

header: /.+(?=\nLOCUS)/xms

locus: /LOCUS/xms locus_name sequence_length molecule_type
    genbank_division(?) modification_date
    {
        $record{'LOCUS'} = {
            locus_name        => $item{'locus_name'},
            sequence_length   => $item{'sequence_length'},
            molecule_type     => $item{'molecule_type'},
            genbank_division  => $item{'genbank_division(?)'}[0],
            modification_date => $item{'modification_date'},
        }
    }

locus_name: /\w+/

space: /\s+/

sequence_length: /\d+/ /(aa|bp)/ { $return = "$item[1] $item[2]" }

molecule_type: /\w+/ (/[a-zA-Z]{4,}/)(?)
    { 
        $return = join(' ', map { $_ || () } $item[1], $item[2][0] ) 
    }

genbank_division: 
    /(PRI|CON|ROD|MAM|VRT|INV|PLN|BCT|VRL|PHG|SYN|UNA|EST|PAT|STS|GSS|HTG|HTC|ENV)/

modification_date: /\d+-[A-Z]{3}-\d{4}/

definition: /DEFINITION/ section_continuing_indented
    {
        ( $record{'DEFINITION'} = $item[2] ) =~ s/\n\s+/ /g;
    }

section_continuing_indented: /.*?(?=\n[A-Z]+\s+)/xms

section_continuing_indented: /.*?(?=\n\/\/)/xms

accession_line: /ACCESSION/ section_continuing_indented
    {
        my @accs = split /\s+/, $item[2];
        $record{'ACCESSION'} = shift @accs;
        push @{ $record{'VERSION'} }, @accs;
    }

version_line: /VERSION/ /(.+)(?=\n)/
    {
        push @{ $record{'VERSION'} }, split /\s+/, $item[2];
    }

project_line: /PROJECT/ section_continuing_indented
    {
        $record{'PROJECT'} = $item[2];
    }

keywords: /KEYWORDS/ keyword_value
    { 
        $record{'KEYWORDS'} = $item[2];
    }

keyword_value: section_continuing_indented
    { 
        ( my $str = $item[1] ) =~ s/\.$//;
        $return = [ split(/,\s*/, $str ) ];
    }
    | PERIOD { $return = [] }

dbsource: /DBSOURCE/ /\w+/ /[^\n]+/xms
    {
        push @{ $record{'DBSOURCE'} }, {
            $item[2], $item[3]
        };
    }

source_line: /SOURCE/ source_value 
    { 
        ( my $src = $item[2] ) =~ s/\.$//;
        $src =~ s/\bsp$/sp./;
        $record{'SOURCE'} = $src;
    }

source_value: /(.+?)(?=\n\s{0,2}[A-Z]+)/xms { $return = $1 }

dblink: dblink_line assembly_line(?) biosample_line(?) sra_line(?)
    {
        $record{'DBLINK'} = $item[1];
        $record{'BIOPROJECT'} = $item[2];
    }

dblink_line: /DBLINK/ dblink_value {$return = $item[2]}
dblink_value: /BioProject: ([^\n]+)(?=\n)/xms {$return = $1}
assembly_line:/Assembly: ([^\n]+)(?=\n)/xms {$return = $1}
biosample_line:/BioSample: ([^\n]+)(?=\n)/xms {$return = $1}
sra_line: /Sequence.*: ([^\n]+)(?=\n)/xms {$return = $1}

organism: organism_line classification_line
    { 
        $record{'ORGANISM'} = $item[1];
        $record{'CLASSIFICATION'} = $item[2];
    }



organism_line: /ORGANISM/ organism_value { $return = $item[2] }

organism_value: /(.*?)(?=\n.*;)/xms { $return = $1 }

classification_line: /(.*?)(?=\n\S)/xms { $return = [ split(/;\s*/, $1) ] }

word: /\w+/

reference: /REFERENCE/ NUMBER(?) parenthetical_phrase(?) authors(?) consrtm(?) title(?) journal(?) remark(?) pubmed(?) remark(?)
    {
        my $num    = $item[2][0] || $ref_num++;
        my $remark = join(' ', map { $_ || () } $item[8][0], $item[10][0]);
        $remark    = undef if $remark !~ /\S+/;

        push @{ $record{'REFERENCES'} }, {
            number  => $num,
            authors => $item{'authors(?)'}[0],
            title   => $item{'title'},
            journal => $item{'journal'},
            pubmed  => $item[9][0],
            note    => $item[3][0],
            remark  => $remark,
            consrtm => $item[5][0],
        };

    }

parenthetical_phrase: /\(([^)]+) \)/xms
    {
        $return = $1;
    }

authors: /AUTHORS/ author_value { $return = $item[2] }

author_value: /(.+?)(?=\n\s{0,2}[A-Z]+)/xms 
    { 
        $return = [ 
            grep  { !/and/ }      
            map   { s/,$//; $_ } 
            split /\s+/, $1
        ];
    }

title: /TITLE/ /.*?(?=\n\s{0,2}[A-Z]+)/xms
    { ( $return = $item[2] ) =~ s/\n\s+/ /; }

journal: /JOURNAL/ journal_value 
    { 
        $return = $item[2] 
    }

journal_value: /(.+)(?=\n\s{3}PUBMED)/xms 
    { 
        $return = $1; 
        $return =~ s/\n\s+/ /g; 
    }
    | /(.+?)(?=\n\s{0,2}[A-Z]+)/xms 
    { 
        $return = $1; 
        $return =~ s/\n\s+/ /g; 
    }

pubmed: /PUBMED/ NUMBER
    { $return = $item[2] }

remark: /REMARK/ section_continuing_indented
    { $return = $item[2] }

consrtm: /CONSRTM/  /.*?(?=\n\s{0,2}[A-Z]+)/xms { $return = $item[2] }

features: /FEATURES/ section_continuing_indented
    { 
        my ( $location, $cur_feature_name, %cur_features, $cur_key );
        for my $fline ( split(/\n/, $item[2]) ) {
            next if $fline =~ m{^\s*Location/Qualifiers};
            next if $fline !~ /\S+/;

            if ( $fline =~ /^\s{21}\/ (\w+?) = (.+)$/xms ) {
                my ( $key, $value )   = ( $1, $2 );
                $value                =~ s/^"|"$//g;
                $cur_key              = $key;
                $cur_features{ $key } = $value;

                if ( $key eq 'db_xref' && $value =~ /^taxon:(\d+)$/ ) {
                    $record{'NCBI_TAXON_ID'} = $1;
                }

                if ( $ATTRIBUTE_PROMOTE{ $key } ) {
                    $record{ uc $key } = $value;
                }
            }
            elsif ( $fline =~ /^\s{5}(\S+) \s+ (.+)$/xms ) {
                my ( $this_feature_name, $this_location ) = ( $1, $2 );
                $cur_key = '';

                if ( $cur_feature_name ) {
                    push @{ $record{'FEATURES'} }, {
                        name     => $cur_feature_name,
                        location => $location,
                        feature  => { %cur_features },
                    };

                    %cur_features = ();
                }

                ( $cur_feature_name, $location ) = 
                    ( $this_feature_name, $this_location );
            }
            elsif ( $fline =~ /^\s{21}([^"]+)["]?$/ ) {
                if ( $cur_key ) {
                    $cur_features{ $cur_key } .= 
                        $cur_key eq 'translation' 
                            ? $1
                            : ' ' . $1;
                }
            }
        }

        push @{ $record{'FEATURES'} }, {
            name     => $cur_feature_name,
            location => $location,
            feature  => { %cur_features },
        };
    }

base_count: /BASE COUNT/ base_summary(s)
    {
        for my $sum ( @{ $item[2] } ) {
            $record{'BASE_COUNT'}{ $sum->[0] } = $sum->[1];
        }
    }

base_summary: /\d+/ /[a-zA-Z]+/
    {
        $return = [ $item[2], $item[1] ];
    }

origin: /ORIGIN/ origin_value 
    { 
        $record{'ORIGIN'} = $item[2] 
    }

origin_value: /(.*?)(?=\n\/\/)/xms
    {
        my $seq = $1;
        $seq =~ s/ORIGIN.*\n//g;
        $seq =~ s/\n//g;
        $seq =~ s/\d//g;
        $seq =~ s/\s+//g;
        $seq =~ s/\/\///g;
        $record{'SEQUENCE'} = $seq;
        $return = $seq;
    }

comment: /COMMENT/ comment_value

comment_value: /(.+?)(?=\n[A-Z]+)/xms
    { 
        $record{'COMMENT'} = $1;
    }

contig: /CONTIG/ section_continuing_indented 
    {
        $record{'CONTIG'} = $item[2];
    }

commented_line: /#[^\n]+/

NUMBER: /\d+/

PERIOD: /\./

record_delimiter: /\/\/\s*/xms

eofile: /^\Z/

END_OF_GRAMMAR
}
1;