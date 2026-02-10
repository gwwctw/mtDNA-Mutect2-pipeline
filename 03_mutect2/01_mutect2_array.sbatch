#!/usr/bin/env bash
#SBATCH --job-name=mutect2_mito
#SBATCH --partition=fast
#SBATCH --nodelist=bsln005
#SBATCH --cpus-per-task=1
#SBATCH --mem=12G
#SBATCH --time=24:00:00
#SBATCH --array=1-1000%20
#SBATCH --output=/slurm_mutect2_%A_%a.out
#SBATCH --error=/slurm_mutect2_%A_%a.err

set -euo pipefail

############################################
# CONFIG
############################################
MANIFEST=mosdepth_manifest.tsv

OUTDIR=/03_mutect2/results
LOGDIR=/03_mutect2/logs
mkdir -p "$OUTDIR" "$LOGDIR"

REF=/GATK_bundle/Homo_sapiens_assembly38.fasta

# GATK 4.1.2.0 + Java8 wrapper (autosomal-coverage 지원)
GATK=/gatk/gatk-4.1.2.0/gatk_java8

# mosdepth autosome coverage summary
AUTOSOME_MEDIAN_TSV=/02_mosdepth/mosdepth_coverage_summary.tsv

############################################
# OFFSET logic
############################################
OFFSET="${OFFSET:-0}"
LINE_NO=$((SLURM_ARRAY_TASK_ID + OFFSET))

LINE=$(sed -n "${LINE_NO}p" "$MANIFEST" || true)
[[ -z "$LINE" ]] && {
  echo "[INFO] No line at LINE_NO=$LINE_NO. Exit."
  exit 0
}

IFS=$'\t' read -r BATCH SAMPLE CRAM MTBAM <<< "$LINE"

# header skip
[[ "$BATCH" == "BATCH" ]] && {
  echo "[INFO] Header line detected (LINE_NO=$LINE_NO). Skip."
  exit 0
}

############################################
# Sanity checks
############################################
[[ -s "$MTBAM" ]] || { echo "[ERROR] Missing mtDNA BAM: $MTBAM" >&2; exit 1; }
[[ -s "${MTBAM}.bai" ]] || { echo "[ERROR] Missing mtDNA BAI: ${MTBAM}.bai" >&2; exit 1; }
[[ -s "$REF" ]] || { echo "[ERROR] Missing REF: $REF" >&2; exit 1; }

############################################
# Logging (sample-level)
############################################
OUT_LOG=${LOGDIR}/mutect2_${SAMPLE}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out
ERR_LOG=${LOGDIR}/mutect2_${SAMPLE}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err
exec > >(tee -a "$OUT_LOG") 2> >(tee -a "$ERR_LOG" >&2)

echo "[INFO] TASK_ID=${SLURM_ARRAY_TASK_ID}"
echo "[INFO] OFFSET=${OFFSET}"
echo "[INFO] LINE_NO=${LINE_NO}"
echo "[INFO] SAMPLE=${SAMPLE}"
echo "[INFO] GATK VERSION:"
$GATK --version

############################################
# Output paths
############################################
RAW_VCF=${OUTDIR}/${SAMPLE}.mito.raw.vcf.gz
RAW_STATS=${OUTDIR}/${SAMPLE}.mito.raw.vcf.gz.stats
FILT_VCF=${OUTDIR}/${SAMPLE}.mito.filtered.vcf.gz

############################################
# 1) Mutect2 (gnomAD mtDNA settings)
############################################
$GATK Mutect2 \
  -R "$REF" \
  -I "$MTBAM" \
  -L chrM:1-16569 \
  --mitochondria-mode \
  --annotation StrandBiasBySample \
  --max-reads-per-alignment-start 75 \
  --max-mnp-distance 0 \
  -O "$RAW_VCF"

############################################
# autosomal coverage lookup (mosdepth)
############################################
AUTOSOME_COV=$(awk -v s="$SAMPLE" '
  NR>1 && $2==s {print $3; exit}
' "$AUTOSOME_MEDIAN_TSV")

if [[ -z "$AUTOSOME_COV" ]]; then
  echo "[ERROR] autosomal coverage not found for SAMPLE=$SAMPLE" >&2
  exit 1
fi

echo "[INFO] AUTOSOME_COVERAGE=${AUTOSOME_COV}"

############################################
# 2) FilterMutectCalls (mtDNA mode)
############################################
$GATK FilterMutectCalls \
  -R "$REF" \
  -V "$RAW_VCF" \
  --stats "$RAW_STATS" \
  --mitochondria-mode \
  --min-allele-fraction 0.01 \
  --max-alt-allele-count 4 \
  --autosomal-coverage "$AUTOSOME_COV" \
  -O "$FILT_VCF"

echo "[DONE] ${SAMPLE}"
