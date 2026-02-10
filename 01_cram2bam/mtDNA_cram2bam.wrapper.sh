#!/usr/bin/env bash


sbatch --array=1-1000%30 mtDNA_cram2bam.sbatch

sbatch --array=1-1000%30 --export=OFFSET=1000 mtDNA_cram2bam.sbatch

sbatch --array=1-1000%30 --export=OFFSET=2000 mtDNA_cram2bam.sbatch
