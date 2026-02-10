#!/usr/bin/env bash
#SBATCH --job-name=mosdepth_cov
#SBATCH --partition=fast
#SBATCH --nodelist=bsln005
#SBATCH --cpus-per-task=1
#SBATCH --mem=6G
#SBATCH --time=12:00:00
#SBATCH --array=1-1000%30
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
set -euo pipefail

MANIFEST=/02_mosdepth/mosdepth_manifest.tsv
OUTDIR=/02_mosdepth
REF=/GATK_bundle/Homo_sapiens_assembly38.fasta

MOSDEPTH=/Tools/mosdepth/current/mosdepth

mkdir -p "$OUTDIR"/{autosome,chrM,logs}

OFFSET="${OFFSET:-0}"
LINE_NO=$((SLURM_ARRAY_TASK_ID + OFFSET))

LINE=$(sed -n "${LINE_NO}p" "$MANIFEST" || true)
if [[ -z "${LINE}" ]]; then
  echo "[INFO] No line at LINE_NO=${LINE_NO}. Exit."
  exit 0
fi

IFS=$'\t' read -r BATCH SAMPLE CRAM MTBAM <<< "$LINE"


# 헤더 스킵
# header skip
[[ "$BATCH" == "BATCH" ]] && {
  echo "[INFO] Header line detected (LINE_NO=$LINE_NO). Skip."
  exit 0
}

# 파일 존재 체크
[[ -s "$CRAM" ]]  || { echo "[ERROR] missing CRAM: $CRAM"; exit 1; }
[[ -s "$MTBAM" ]] || { echo "[ERROR] missing mtDNA BAM: $MTBAM"; exit 1; }
[[ -s "${MTBAM}.bai" ]] || { echo "[ERROR] missing mtDNA BAI: ${MTBAM}.bai"; exit 1; }

echo "[INFO] SAMPLE=$SAMPLE LINE_NO=$LINE_NO"

LOGDIR="${OUTDIR}/logs"

OUT_LOG=${LOGDIR}/mosdepth_${SAMPLE}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out
ERR_LOG=${LOGDIR}/mosdepth_${SAMPLE}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err

exec > >(tee -a "$OUT_LOG") 2> >(tee -a "$ERR_LOG" >&2)

# autosome coverage (CRAM): mosdepth summary 생성 (후처리에서 chr1-22 가중평균 계산)
$MOSDEPTH \
  --no-per-base \
  --fast-mode \
  --fasta "$REF" \
  "$OUTDIR/autosome/${SAMPLE}.autosome" \
  "$CRAM"

# chrM coverage (mtDNA BAM)
$MOSDEPTH \
  --no-per-base \
  --fast-mode \
  "$OUTDIR/chrM/${SAMPLE}.chrM" \
  "$MTBAM"
