#!/bin/bash
set -e

NEGATIVE=0
PROJECT_ID=""
QUERY_FILE=""

# Parse arguments in any order
for arg in "$@"; do
  case "$arg" in
    --negative)
      NEGATIVE=1
      ;;
    *.sql)
      QUERY_FILE="$arg"
      ;;
    *)
      if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="$arg"
      else
        echo "Unknown argument: $arg"
        exit 1
      fi
      ;;
  esac
done

# Validate arguments
if [[ -z "$PROJECT_ID" || -z "$QUERY_FILE" ]]; then
  echo "Usage: $0 [--negative] PROJECT_ID QUERY_FILE"
  echo "       or in any argument order"
  exit 1
fi

if [[ ! -f "$QUERY_FILE" ]]; then
  echo "File not found: $QUERY_FILE"
  exit 1
fi

OK_COUNT=0
NG_COUNT=0
LINE_NO=0

while IFS= read -r line; do
  LINE_NO=$((LINE_NO + 1))
  SQL=$(echo "$line" | sed 's/;$//')
  if [[ -z "$SQL" ]]; then
    continue
  fi

  echo "[Line $LINE_NO] Running: $SQL"

  CNT=$(bq query --project_id="$PROJECT_ID" --quiet --use_legacy_sql=false --format=csv "$SQL" | tail -n +2)

  if [[ "$NEGATIVE" -eq 1 ]]; then
    if [[ "$CNT" == "0" ]]; then
      echo "[Line $LINE_NO] OK (count = 0)"
      OK_COUNT=$((OK_COUNT + 1))
    else
      echo "[Line $LINE_NO] Error (expected 0, got $CNT)"
      NG_COUNT=$((NG_COUNT + 1))
    fi
  else
    if [[ "$CNT" != "0" ]]; then
      echo "[Line $LINE_NO] OK (count = $CNT)"
      OK_COUNT=$((OK_COUNT + 1))
    else
      echo "[Line $LINE_NO] Error (expected non-zero, got 0)"
      NG_COUNT=$((NG_COUNT + 1))
    fi
  fi

  echo
done < "$QUERY_FILE"

echo "Summary: $OK_COUNT passed, $NG_COUNT failed"

if [[ "$NG_COUNT" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
