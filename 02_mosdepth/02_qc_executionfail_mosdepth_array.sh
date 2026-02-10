#!/usr/bin/env bash
set -euo pipefail

########################
# config
########################
LOGDIR=/02_mosdepth/logs
OUTDIR=/02_mosdepth
MANIFEST=/01_Batch_info/mosdepth_manifest.tsv
FAIL_TSV=${OUTDIR}/mosdepth_failures.tsv
FAIL_SAMPLES=${OUTDIR}/mosdepth_failed_samples.list


########################
# main
########################
# ====== 1) 로그에서 실패 라인 수집 (.out + .err) ======
grep -HnE \
  "^\[ERROR\]|error parsing arguments|No such file|cannot open|Failed to|Killed|Segmentation fault|hts_open|CRAM|fasta|permission denied" \
  "$LOGDIR"/*.out "$LOGDIR"/*.err 2>/dev/null \
  > "${OUTDIR}/mosdepth_error_lines.raw.txt" || true


# 로그에 에러가 없으면 빈 파일일 수 있음
if [[ ! -s "${OUTDIR}/mosdepth_error_lines.raw.txt" ]]; then
  echo "[INFO] No error lines found in logs."
  : > "$FAIL_TSV"
  : > "$FAIL_SAMPLES"
  exit 0
fi


# ====== 2) JobID/ArrayTaskID/샘플명 추출 ======
cut -d: -f1 "${OUTDIR}/mosdepth_error_lines.raw.txt" | sort -u > "${OUTDIR}/mosdepth_error_files.list"

# 2-2) 각 로그 파일에서 SAMPLE 라인 찾아서 샘플명 추출
# SAMPLE 로그가 없으면, 파일명에서 %A_%a로 task id를 뽑아 MANIFEST로 역추적
echo -e "log_file\tjob_array_id\ttask_id\tBATCH\tSAMPLE\tCRAM\tMTBAM\treason" > "$FAIL_TSV"


while IFS= read -r f; do
  base=$(basename "$f")

  # 파일명 패턴: mosdepth_%A_%a.out
  # 예: mosdepth_123456_78.out
  job_array_id=$(echo "$base" | sed -n 's/^mosdepth_\([0-9]\+\)_.*/\1/p')
  task_id=$(echo "$base" | sed -n 's/^mosdepth_[0-9]\+_\([0-9]\+\)\..*/\1/p')

  # reason: 해당 파일에서 첫 ERROR 라인 1개만 뽑아 요약
  reason=$(grep -m1 -E "^\[ERROR\]|error parsing arguments|No such file|cannot open|Failed to|Killed|Segmentation fault|hts_open|permission denied" "$f" 2>/dev/null || true)
  reason=${reason//$'\t'/ }  # 탭 있으면 보기 좋게 공백 처리

  # SAMPLE 라인 파싱 (있으면 가장 좋음)
  sample=$(grep -m1 -E "^\[INFO\] SAMPLE=" "$f" | sed -n 's/.*SAMPLE=\([^ ]\+\).*/\1/p' || true)

  if [[ -n "$sample" ]]; then
    # manifest에서 샘플 행 찾아 붙이기
    row=$(awk -F'\t' -v s="$sample" 'NR>1 && $2==s{print; exit}' "$MANIFEST" || true)
    if [[ -n "$row" ]]; then
      IFS=$'\t' read -r BATCH SAMPLE CRAM MTBAM <<< "$row"
      echo -e "${f}\t${job_array_id}\t${task_id}\t${BATCH}\t${SAMPLE}\t${CRAM}\t${MTBAM}\t${reason}" >> "$FAIL_TSV"
    else
      echo -e "${f}\t${job_array_id}\t${task_id}\t${BATCH}\t${SAMPLE}\tNA\tNA\tNA\tNA\t${reason}" >> "$FAIL_TSV"
    fi
  else
    # SAMPLE 로그가 없으면: task_id 기반으로 manifest 역추적은 OFFSET을 몰라서 완전 자동은 어려움.
    # 대신 파일만 기록해두고, 원인 조사 대상에 넣는다.
    echo -e "${f}\t${job_array_id}\t${task_id}\tNA\tNA\tNA\tNA\tNA\t${reason}" >> "$FAIL_TSV"
  fi

done < "${OUTDIR}/mosdepth_error_files.list"

# ====== 3) 실패 샘플 리스트 뽑기 ======
cut -f5 "$FAIL_TSV" | tail -n +2 | grep -v '^NA$' | sort -u > "$FAIL_SAMPLES"

echo "[DONE] Failure table : $FAIL_TSV"
echo "[DONE] Failed samples: $FAIL_SAMPLES"
echo "[INFO] n_failed_samples = $(wc -l < "$FAIL_SAMPLES" 2>/dev/null || echo 0)"
~
