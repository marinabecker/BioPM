# BioPM

A series of Perl Modules for interacting with biological databases and biological data formats.


## But BioPerl already has _X_ !
Yes. I am aware.

BioPerl is awesome and expansive I really like it.

It is also huge and not a dependency that I can easily bundle into packages quickly. Most of these modules are designed to run faster/more efficently than what BioPerl has to currently offer and with fewer dependencies. 

I've also done everything I can to make sure that required binaries are INCLUDED in the package so I don't need to worry about pathed variables.


## Included Modules

```
.
├── Drive5
│   ├── bin
│   │   ├── muscle
│   │   └── usearch
│   ├── Muscle.pm
│   └── Usearch.pm
├── GLPSOL
│   ├── bin
│   │   └── glpsol
│   └── GLPSOL.pm
├── KEGG
│   └── KEGG.pm
├── NCBI
│   ├── names.dmp
│   ├── nodes.dmp
│   ├── SRA.pm
│   ├── taxdump.tar.gz
│   ├── tax_lookup.store
│   ├── Taxonomy.pm
│   └── test
├── Parse
│   ├── FASTA.pm
│   ├── FASTQ.pm
│   └── GenBank.pm
├── Plot
│   └── GGplot2.pm
├── README.md
├── SILVA
│   └── SILVA.pm
└── UniProt
    └── UniProt.pm
```

##TO DO

SILVA and UNIPROT both need to be split into database interaction functions and parsers seperately. 

Full Docs would be nice.

Tests would be cool.