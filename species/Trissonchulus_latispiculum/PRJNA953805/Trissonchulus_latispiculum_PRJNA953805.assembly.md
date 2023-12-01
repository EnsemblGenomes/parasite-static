The full assembly process is described in [Lee et al., (2023)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10450198/). The [Flye assembler](https://www.nature.com/articles/s41587-019-0072-8) (ver. 2.9.1) was used to assemble the raw ONT reads. These were then polished by four iterations of [Racon](https://genome.cshlp.org/content/27/5/737.full) (ver. 1.4.11), followed by [Medaka]( https://github.com/nanoporetech/medaka) (ver. 1.2.0; option: -m r941_min_sup_g507 or r103_sup_g507). The consensus sequences were further corrected with Illumina reads using [NextPolish](https://academic.oup.com/bioinformatics/article/36/7/2253/5645175?login=true)(ver. 1.4.0), and haplotigs were removed using [HaploMerger2](https://academic.oup.com/bioinformatics/article/33/16/2577/3603547) (ver. 20180603). Assemblies were mapped to the reference genome with [minimap2](https://academic.oup.com/bioinformatics/article/34/18/3094/4994778) (option: -ax asm5). Raw Illumina reads were assembled using the [Spades assembler](https://www.liebertpub.com/doi/abs/10.1089/cmb.2012.0021) (ver. v3.14.1; option: spades_sc).