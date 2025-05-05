#!/bin/bash

# Usage:
#   ./scripts/golden_test.sh PROJECT_ID test/golden-*.sql
#   ./scripts/golden_test.sh --negative PROJECT_ID test/golden-*.sql

MODE="positive"
FILES=()
PROJECT_ID=""

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --negative)
      MODE="negative"
      ;;
    *)
      if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="$arg"
      else
        FILES+=("$arg")
      fi
      ;;
  esac
done

if [[ -z "$PROJECT_ID" || ${#FILES[@]} -eq 0 ]]; then
  echo "Usage: $0 [--negative] PROJECT_ID file1.sql [file2.sql ...]"
  exit 1
fi

TMPDIR=$(mktemp -d)
ALL_OK=0

for FILE in "${FILES[@]}"; do
  echo "Running golden test: $FILE"

  SQL_PART=$(awk '/^\/\*/ {exit} {print}' "$FILE")
  EXPECTED_CSV=$(awk '
    /^\s*\/\*/ {found=1; next}
    /^\s*\*\// {exit}
    found {print}
  ' "$FILE")

  SQL_FILE="$TMPDIR/query.sql"
  EXPECTED_FILE="$TMPDIR/expected.csv"
  OUTPUT_FILE="$TMPDIR/output.csv"

  echo "$SQL_PART" > "$SQL_FILE"
  echo "$EXPECTED_CSV" > "$EXPECTED_FILE"

  bq query \
    --project_id="$PROJECT_ID" \
    --use_legacy_sql=false \
    --format=csv \
    --quiet < "$SQL_FILE" > "$OUTPUT_FILE"
  BQ_EXIT=$?

  if [[ $BQ_EXIT -ne 0 ]]; then
    echo "ERROR: bq query failed for $FILE"
    echo "--- SQL ---"
    cat "$SQL_FILE"
    echo
    ALL_OK=1
    continue
  fi

  LINE_COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
  if [[ "$MODE" == "positive" ]]; then
    if diff -q "$EXPECTED_FILE" "$OUTPUT_FILE" > /dev/null; then
      echo "PASS: $FILE"
    else
      echo "FAIL: $FILE"
      echo "--- Expected:"
      cat "$EXPECTED_FILE"
      echo "--- Got:"
      cat "$OUTPUT_FILE"
      echo
      ALL_OK=1
    fi
  else
    if [[ "$LINE_COUNT" -eq 0 ]]; then
      echo "PASS: $FILE (no matching rows)"
    else
      echo "FAIL: $FILE (expected zero rows)"
      echo "--- Got:"
      cat "$OUTPUT_FILE"
      echo
      ALL_OK=1
    fi
  fi
done

rm -rf "$TMPDIR"
exit "$ALL_OK"
