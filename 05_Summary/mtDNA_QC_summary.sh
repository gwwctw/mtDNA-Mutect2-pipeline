#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################

WORKDIR="/03_mtDNA_analysis"

MUTECT2_DIR="${WORKDIR}/03_mutect2/results"
MOSDEPTH_CHRM_DIR="${WORKDIR}/02_mosdepth/chrM"
MOSDEPTH_AUTO_DIR="${WORKDIR}/02_mosdepth/autosome"

OUTDIR="${WORKDIR}/05_Summary"

MUTECT2_OUT="${OUTDIR}/qc_mito_variant_counts.tsv"
CHRM_OUT="${OUTDIR}/qc_chrM_coverage.tsv"
AUTO_OUT="${OUTDIR}/qc_autosome_coverage.tsv"
OUT_FINAL="${OUTDIR}/qc_mtDNA_summary.tsv"
FILTER_DIR="${OUTDIR}/qc_filter_breakdown"

mkdir -p  "${FILTER_DIR}"

############################################
# FUNCTIONS
############################################

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

############################################
# 01. mtDNA variant counts (Mutect2)
############################################

log "Step 01. Counting mtDNA variants (Mutect2)"

echo -e "sample_id\tn_raw_total\tn_filt_total\tn_pass\tpass_rate" > "${MUTECT2_OUT}"

for RAWVCF in "${MUTECT2_DIR}"/*.mito.raw.vcf.gz; do
    SAMPLE_ID=$(basename "${RAWVCF}" .mito.raw.vcf.gz)

    # raw variant count
    N_RAW=$(zgrep -vc '^#' "${RAWVCF}")

    # filtered variant count
    FILTERED_VCF="${MUTECT2_DIR}/${SAMPLE_ID}.mito.filtered.vcf.gz"
    if [[ -f "${FILTERED_VCF}" ]]; then
        N_FILT_TOTAL=$(zgrep -vc '^#' "${FILTERED_VCF}")
        N_PASS=$(bcftools view -f PASS -H "${FILTERED_VCF}" | wc -l)
        PASS_RATE=$(awk -v p="${N_PASS}" -v t="${N_FILT_TOTAL}" \
        'BEGIN{ if(t>0) printf "%.6f", p/t; else print "NA" }')

        ####################
        # Filter breakdown
        ####################
        bcftools view -H "${FILTERED_VCF}" \
        | cut -f7 \
        | sort | uniq -c \
        | awk -v s="${SAMPLE_ID}" '{print s "\t" $2 "\t" $1}' \
        > "${FILTER_DIR}/${SAMPLE_ID}.filter_counts.tsv"
    else
        log "[WARN] Missing filtered VCF for ${SAMPLE_ID}, set to 0"
        N_FILT_TOTAL="NA"
        N_PASS="NA"
        PASS_RATE="NA"
    fi

    echo -e "${SAMPLE_ID}\t${N_RAW}\t${N_FILT_TOTAL}\t${N_PASS}\t${PASS_RATE}"
done >> "${MUTECT2_OUT}"

log " → written: ${MUTECT2_OUT}"

############################################
# 02-1. mtDNA chrM coverage (mosdepth)
############################################

log "Step 02-1. Extracting chrM coverage (mosdepth)"

echo -e "sample_id\tmito_mean_coverage" > "${CHRM_OUT}"

for SUM in "${MOSDEPTH_CHRM_DIR}"/*.chrM.mosdepth.summary.txt; do
    SAMPLE_ID=$(basename "${SUM}" .chrM.mosdepth.summary.txt)

    # mosdepth summary: chrom length bases mean min max
    MITO_COV=$(awk '$1=="chrM"{print $4}' "${SUM}")

    echo -e "${SAMPLE_ID}\t${MITO_COV}"
done >> "${CHRM_OUT}"

log " → written: ${CHRM_OUT}"

############################################
# 02-2. autosome weighted mean coverage
############################################

log "Step 02-2. Calculating autosome weighted coverage (chr1–22)"

echo -e "sample_id\tautosome_mean_coverage" > "${AUTO_OUT}"

for SUM in "${MOSDEPTH_AUTO_DIR}"/*.autosome.mosdepth.summary.txt; do
    SAMPLE_ID=$(basename "${SUM}" .autosome.mosdepth.summary.txt)

    AUTO_COV=$(awk '
    $1 ~ /^chr([1-9]|1[0-9]|2[0-2])$/ {
        cov += $2 * $4
        len += $2
    }
    END {
        if (len > 0) printf "%.4f", cov / len;
        else print "NA";
    }' "${SUM}")

    echo -e "${SAMPLE_ID}\t${AUTO_COV}"
done >> "${AUTO_OUT}"

log " → written: ${AUTO_OUT}"

############################################
# 03. Final QC table merge
############################################

log "Step 03. Merging QC tables"

echo -e "sample_id\tn_raw_total\tn_filt_total\tn_pass\tpass_rate\tmito_mean_coverage\tautosome_mean_coverage" \
> "${OUT_FINAL}"

join -t $'\t' -1 1 -2 1 \
    <(tail -n +2 "${MUTECT2_OUT}" | sort -k1,1) \
    <(tail -n +2 "${CHRM_OUT}"    | sort -k1,1) \
| join -t $'\t' -1 1 -2 1 - \
    <(tail -n +2 "${AUTO_OUT}"    | sort -k1,1) \
>> "${OUT_FINAL}"

log " → FINAL QC TABLE: ${OUT_FINAL}"
log "All done."
