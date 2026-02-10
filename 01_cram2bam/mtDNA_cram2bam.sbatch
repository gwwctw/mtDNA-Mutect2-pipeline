#!/usr/bin/env bash
#SBATCH --job-name=mtDNA_cram2bam
#SBATCH --partition=onebatch
#SBATCH --partition=fast
#SBATCH --nodelist=bsln005
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

set -euo pipefail

### usage example
# sbatch --array=1-1000%30 mtDNA_cram2bam.sbatch
# sbatch --array=1-1000%30 --export=OFFSET=1000 mtDNA_cram2bam.sbatch
# sbatch --array=1-1000%30 --export=OFFSET=2000 mtDNA_cram2bam.sbatch

######################################
# Config
######################################
SAMTOOLS=/gtran/kgenome/UTILS/Tools/Miniconda3/envs/snakemake/bin/samtools
WORKDIR=/gtran/kobic/USER/slyang/01_RareDisease/03_mtDNA_analysis/01_cram2bam
LIST=/gtran/kobic/USER/slyang/01_RareDisease/01_Batch_info/mtDNA_cram_list.tsv
REF=/gtran/kgenome/UTILS/Reference/GATK_bundle/Homo_sapiens_assembly38.fasta

######################################
# OFFSET logic
######################################
OFFSET=${OFFSET:-0}
LINE_NO=$((SLURM_ARRAY_TASK_ID + OFFSET))

LINE=$(sed -n "${LINE_NO}p" "${LIST}" || true)
[[ -z "$LINE" ]] && exit 0

IFS=$'\t' read -r BATCH SAMPLE CRAM CRAI <<< "$LINE"

# skip header
[[ "$BATCH" == "BATCH" ]] && exit 0

[[ -z "$CRAM" || -z "$CRAI" ]] && {
  echo "[WARN] Missing CRAM/CRAI for ${SAMPLE}"
  exit 0
}

CRAM_BASE=$(basename "$CRAM")
INDIV_ID=${CRAM_BASE%%_*}

LOGDIR=${WORKDIR}/logs
mkdir -p "${LOGDIR}"

OUT_LOG=${LOGDIR}/cram2bam_${INDIV_ID}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out
ERR_LOG=${LOGDIR}/cram2bam_${INDIV_ID}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err

exec > >(tee -a "$OUT_LOG") 2> >(tee -a "$ERR_LOG" >&2)

######################################
# Logging
######################################
echo "[INFO] SLURM_JOB_ID      = ${SLURM_JOB_ID}"
echo "[INFO] SLURM_ARRAY_ID    = ${SLURM_ARRAY_TASK_ID}"
echo "[INFO] OFFSET            = ${OFFSET}"
echo "[INFO] LINE_NO           = ${LINE_NO}"
echo "[INFO] SAMPLE            = ${SAMPLE}"
echo "[INFO] CRAM              = ${CRAM}"

######################################
# Output
######################################
OUTDIR=${WORKDIR}/${BATCH}
mkdir -p "${OUTDIR}" "${WORKDIR}/logs"
OUTBAM=${OUTDIR}/${SAMPLE}.mtDNA.bam

######################################
# mtDNA extract
######################################
$SAMTOOLS view \
  -T "${REF}" \
  -b "${CRAM}" \
  chrM \
  > "${OUTBAM}"

$SAMTOOLS index "${OUTBAM}"

echo "[DONE] ${SAMPLE}"
