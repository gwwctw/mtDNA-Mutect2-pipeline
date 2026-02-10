!/usr/bin/env bash
set -euo pipefail


MANIFEST=/02_mosdepth/mosdepth_manifest.tsv
OUTDIR=/02_mosdepth
OUTTSV=/02_mosdepth/mosdepth_coverage_summary.tsv
echo -e "BATCH\tSAMPLE\tautosome_mean\tchrM_mean\tchrM_over_autosome" > "$OUTTSV"

tail -n +2 "$MANIFEST" | while IFS=$'\t' read -r BATCH SAMPLE CRAM MTBAM; do
  A_SUM="$OUTDIR/autosome/${SAMPLE}.autosome.mosdepth.summary.txt"
  M_SUM="$OUTDIR/chrM/${SAMPLE}.chrM.mosdepth.summary.txt"

  if [[ ! -s "$A_SUM" || ! -s "$M_SUM" ]]; then
    echo -e "${BATCH}\t${SAMPLE}\tNA\tNA\tNA" >> "$OUTTSV"
    continue
  fi

  # autosome mean (chr1-22 length 가중 평균): sum(bases)/sum(length)
  autosome_mean=$(awk '
    BEGIN{sumBases=0; sumLen=0}
    ($1 ~ /^chr([1-9]$|1[0-9]$|2[0-2]$)$/){
      sumLen += $2;
      sumBases += $3;
    }
    END{
      if(sumLen>0) printf("%.6f", sumBases/sumLen);
      else printf("NA");
    }' "$A_SUM")

  # chrM mean: chrM row의 mean 컬럼(4번째)
  chrM_mean=$(awk '$1=="chrM"{printf("%.6f",$4)}' "$M_SUM")
  [[ -z "$chrM_mean" ]] && chrM_mean="NA"

  ratio="NA"
  if [[ "$autosome_mean" != "NA" && "$chrM_mean" != "NA" ]]; then
    ratio=$(awk -v m="$chrM_mean" -v a="$autosome_mean" 'BEGIN{ if(a>0) printf("%.6f", m/a); else printf("NA"); }')
  fi

  echo -e "${BATCH}\t${SAMPLE}\t${autosome_mean}\t${chrM_mean}\t${ratio}" >> "$OUTTSV"
done

echo "[DONE] $OUTTSV"
