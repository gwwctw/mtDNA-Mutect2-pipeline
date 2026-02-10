#!/usr/bin/env bash

# NOTE:
# MANIFEST has 1001 samples
# Do NOT change array ranges unless MANIFEST changes

# 1–1000
sbatch --array=1-1000%20 --export=ALL 01_mutect2_array.sbatch

# 1001 (1 sample)
sbatch --array=1-1 --export=ALL,OFFSET=1000 01_mutect2_array.sbatch
