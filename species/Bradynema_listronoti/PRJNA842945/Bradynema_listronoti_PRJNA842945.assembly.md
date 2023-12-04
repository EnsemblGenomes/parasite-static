Long and short-read sequencing data was trimmed and filtered based on quality using Guppy (v 6.0.6) and [Fastp](https://academic.oup.com/bioinformatics/article/34/17/i884/5093234) (v 0.20.1).
Long-read sequences were assembled using [Flye](https://www.nature.com/articles/s41587-019-0072-8) (2.9-b1768).
short-reads were assembled using [HASLR](https://www.sciencedirect.com/science/article/pii/S2589004220305770?via%3Dihub) (v 0.8a1) assisted by long-reads. 
These assemblies were merged using Quickmerge (v 0.3), and scaffolded with [LINKS](https://academic.oup.com/gigascience/article/4/1/s13742-015-0076-3/2707579) (v 1.8.7)
The final scaffolded assembly was polished and corrected with [Pilon](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4237348/) (v 1.23).
