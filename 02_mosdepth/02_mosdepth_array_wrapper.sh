#!/usr/bin/env bash

# 1–1000
sbatch --array=1-1000%30 --export=ALL,OFFSET=1    02_mosdepth_array.sbatch

# 1001–2000
sbatch --array=1-1000%30 --export=ALL,OFFSET=1001 02_mosdepth_array.sbatch

# 2001–2002 (2개만)
sbatch --array=1-2       --export=ALL,OFFSET=2001 02_mosdepth_array.sbatch
