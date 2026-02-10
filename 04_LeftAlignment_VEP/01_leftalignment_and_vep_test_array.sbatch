#!/usr/bin/env bash
#SBATCH --job-name=mtDNA_leftalign_vep
#SBATCH --partition=fast
#SBATCH --nodelist=bsln005
#SBATCH --cpus-per-task=2
#SBATCH --mem=10G
#SBATCH --time=12:00:00
#SBATCH --array=1-1000%10
#SBATCH --output=slurm_leftalign_vep_%A_%a.out
#SBATCH --error=slurm_leftalign_vep_%A_%a.err

set -Eeuo pipefail

############################################
# 0. VEP environment
############################################
set +u

source /vep_115/vep/bin/activate
# conda-unpack은 1회성 복구용이라 이미 unpack된 환경에서 다시 실행하면:
# warning 혹은 파일 timestamp 변경 → cache invalidation 가능성
if command -v conda-unpack &>/dev/null; then
  conda-unpack || true
fi

set -u
export PERL5LIB="/gtran/kobic/USER/seo/04.install/vep_115/vep/share/ensembl-vep-115.2-1:${PERL5LIB}"

############################################
# CONFIG
############################################
MANIFEST=/gtran/kobic/USER/slyang/01_RareDisease/03_mtDNA_analysis/02_mosdepth/mosdepth_manifest.tsv
OUTBASE=/gtran/kobic/USER/slyang/01_RareDisease/03_mtDNA_analysis/04_LeftAlignment_VEP/results
LOGDIR=/gtran/kobic/USER/slyang/01_RareDisease/03_mtDNA_analysis/04_LeftAlignment_VEP/logs

REF=/gtran/kgenome/UTILS/Reference/GATK_bundle/Homo_sapiens_assembly38.fasta
GATK=/gtran/kgenome/UTILS/Tools/gatk/gatk-4.1.2.0/gatk_java8

VEP_BIN="/gtran/kobic/USER/seo/04.install/vep_115/vep/bin/vep"
CACHE_DIR="/gtran/kobic/USER/seo/04.install/vep_115/.vep"
ASSEMBLY="GRCh38"
CACHE_VERSION="115"


log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$TASK_LOG"
}
fail() {
  log "[ERROR] Pipeline failed at line $1"
  exit 1
}

############################################
# External annotation DBs
############################################
PLUGIN_BASE="/DB"

CLINVAR_VCF="${PLUGIN_BASE}/clinvar_20251123.vcf.gz"
KOREA4K_VCF="${PLUGIN_BASE}/Korea4K.AF.vcf.gz"
INTERVAR_VCF="${PLUGIN_BASE}/intervar.sorted.vcf.gz"
OMIM_VEP_FILE="${PLUGIN_BASE}/OMIM/omim_vep.chr.sorted.bed.gz"

############################################
# OFFSET logic
############################################
OFFSET="${OFFSET:-0}"
LINE_NO=$((SLURM_ARRAY_TASK_ID + OFFSET))
LINE=$(sed -n "${LINE_NO}p" "$MANIFEST" || true)
[[ -z "$LINE" ]] && exit 0

IFS=$'\t' read -r BATCH SAMPLE CRAM MTBAM <<< "$LINE"
[[ "$SAMPLE" == "SAMPLE" ]] && exit 0

mkdir -p "${OUTBASE}/Batch1" "${OUTBASE}/Batch2"

############################################
# SAMPLE DIR & LOG
############################################

SAMPLE_DIR=${OUTBASE}/${BATCH}/${SAMPLE}
FILT_VCF=/results/${SAMPLE}.mito.filtered.vcf.gz


mkdir -p "$SAMPLE_DIR"


OUT_LOG=${LOGDIR}/LA_VEP_${SAMPLE}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out
ERR_LOG=${LOGDIR}/LA_VEP_${SAMPLE}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err
exec > >(tee -a "$OUT_LOG") 2> >(tee -a "$ERR_LOG" >&2)
TASK_LOG=${LOGDIR}/LA_VEP_${SAMPLE}_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.log
exec > >(tee -a "$TASK_LOG") 2>&1

trap 'fail $LINENO' ERR

log "[INFO] SAMPLE=${SAMPLE}"
log "[INFO] TASK_ID=${SLURM_ARRAY_TASK_ID} OFFSET=${OFFSET} LINE_NO=${LINE_NO}"

############################################
# START
############################################
log "START SAMPLE=${SAMPLE}"
log "SLURM_JOB_ID=${SLURM_JOB_ID}, ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}"

LEFT_VCF=${SAMPLE_DIR}/${SAMPLE}_${SLURM_ARRAY_TASK_ID}.leftalign.vcf.gz
VEP_OUT=${SAMPLE_DIR}/${SAMPLE}_${SLURM_ARRAY_TASK_ID}.vep_annot.vcf

############################################
# Step 4) LeftAlignAndTrimVariants
############################################
log "Running GATK LeftAlignAndTrimVariants"

$GATK LeftAlignAndTrimVariants \
  -R "$REF" \
  -V "$FILT_VCF" \
  --split-multi-allelics \
  --dont-trim-alleles \
  --keep-original-ac \
  -O "$LEFT_VCF"

log "LeftAlignAndTrimVariants finished"
log "Indexing left-aligned VCF"


############################################
# Step 5) VEP annotation (mtDNA 최적화)
############################################
log "Running VEP annotation"

$VEP_BIN \
  --vcf \
  --cache --offline \
  --dir_cache "$CACHE_DIR" \
  --cache_version "$CACHE_VERSION" \
  --assembly GRCh38 \
  --fasta "${CACHE_DIR}/Homo_sapiens.GRCh38.dna.primary_assembly.fa" \
  --input_file "$LEFT_VCF" \
  --output_file "$VEP_OUT" \
  \
  --symbol \
  --hgvs \
  --canonical \
  --pick \
  \
  --no_intergenic \
  --no_stats \
  \
  --fork 2 \
  --buffer_size 100 \
  \
  --custom "$CLINVAR_VCF",ClinVar,vcf,exact,0,CLNSIG,CLNREVSTAT,CLNDN,RS \
  --custom "$KOREA4K_VCF",Korea4K,vcf,exact,0,AF \
  --custom "$INTERVAR_VCF",InterVar,vcf,exact,1,InterVar,PVS1,PS1,PM2,PP3 \
  --custom "$OMIM_VEP_FILE",OMIM,bed,overlap,0,symbol,omim_id \
  \
  --force_overwrite \
  --compress_output bgzip


log "VEP annotation finished"
log "DONE SAMPLE=${SAMPLE}"
