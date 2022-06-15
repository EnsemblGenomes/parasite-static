The draft genome assembly was produced by the [Parasites & Microbes Programme at the Wellcome Trust Sanger Institute](https://www.sanger.ac.uk/programme/parasites-and-microbes/). The assembly uses Illumina paired-end sequencing followed by a genome assembly pipeline comprising various steps, including De novo genome assembly with [SPAdes](https://pubmed.ncbi.nlm.nih.gov/32559359), decontamination with [Redundans](https://pubmed.ncbi.nlm.nih.gov/27131372) and [BlobTools](https://f1000research.com/articles/6-1287/v1), scaffolding with [OPERA-LG](https://pubmed.ncbi.nlm.nih.gov/27169502) and more.

The mitochondrial genome was assembled independently by mapping all trimmed reads to mitochondrial genomes of closely related species. Aligned reads were assembled using [Velvet](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2336801) followed by manual curation to produce a signle contig which was then validated by multiple sequence alignment to filarial mtDNA genomes using [Mesquite](http://www.mesquiteproject.org/).