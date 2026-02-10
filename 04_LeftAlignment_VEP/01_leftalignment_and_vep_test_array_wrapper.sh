#!/usr/bin/env bash

sbatch --array=1-1000%10 --export=ALL,OFFSET=0 01_leftalignment_and_vep_test_array.sbatch
sbatch --array=1-1%10    --export=ALL,OFFSET=1000 01_leftalignment_and_vep_test_array.sbatch
