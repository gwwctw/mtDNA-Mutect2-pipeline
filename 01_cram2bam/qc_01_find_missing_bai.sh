#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <BAM_DIR>" >&2
  exit 1
fi

BAM_DIR=$1
SAMTOOLS=/Miniconda3/envs/snakemake/bin/samtools

missing=0

for bam in $(find "$BAM_DIR" -name "*.mtDNA.bam"); do
  if [[ ! -f "${bam}.bai" ]]; then
    echo "[INFO] Indexing missing: $bam"
    $SAMTOOLS index "$bam"
    ((missing++))
  fi
done

echo "[DONE] Indexed $missing BAM files"
