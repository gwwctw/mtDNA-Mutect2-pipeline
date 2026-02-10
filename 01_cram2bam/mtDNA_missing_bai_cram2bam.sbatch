#!/usr/bin/env bash
#SBATCH --job-name=cram2bam_missingbai
#SBATCH --partition=onebatch
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=/01_cram2bam/logs/cram2bam_%A_%a.out
#SBATCH --error=/01_cram2bam/logs/cram2bam_%A_%a.err

set -euo pipefail

### usage example
# sbatch --array=1-1000%30 mtDNA_cram2bam.sbatch
# sbatch --array=1-1000%30 --export=OFFSET=1000 mtDNA_cram2bam.sbatch
# sbatch --array=1-1000%30 --export=OFFSET=2000 mtDNA_cram2bam.sbatch

######################################
# Config
######################################
SAMTOOLS=/Miniconda3/envs/snakemake/bin/samtools
WORKDIR=/03_mtDNA_analysis/01_cram2bam
LIST=/outcome
REF=/GATK_bundle/Homo_sapiens_assembly38.fasta

######################################
# OFFSET logic
######################################
OFFSET=${OFFSET:-0}
LINE_NO=$((SLURM_ARRAY_TASK_ID + OFFSET))

LINE=$(sed -n "${LINE_NO}p" "${LIST}" || true)
[[ -z "$LINE" ]] && exit 0

IFS=$'\t' read -r BATCH CALLER SAMPLE CRAM CRAI <<< "$LINE"

# skip header
[[ "$BATCH" == "BATCH" ]] && exit 0

######################################
# Logging
######################################
echo "[INFO] SLURM_JOB_ID      = ${SLURM_JOB_ID}"
echo "[INFO] SLURM_ARRAY_ID    = ${SLURM_ARRAY_TASK_ID}"
echo "[INFO] OFFSET            = ${OFFSET}"
#echo "[INFO] LINE_NO           = ${LINE_NO}"
#echo "[INFO] BATCH | CALLER    = ${BATCH} | ${CALLER}"
echo "[INFO] SAMPLE            = ${SAMPLE}"
echo "[INFO] CRAM              = ${CRAM}"

######################################
# Output
######################################
OUTDIR=${WORKDIR}/${BATCH}/${CALLER}
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
