#!/bin/bash
set -e

PROJECT_ID="$1"
DATASET_ID="sales01"
DUMP_MODE=0

if [[ "$2" == "--dump" ]]; then
  DUMP_MODE=1
fi

if [ -z "$PROJECT_ID" ]; then
  echo "Usage: $0 PROJECT_ID [--dump]"
  exit 1
fi

echo "Project: $PROJECT_ID"
echo "Dataset: $DATASET_ID"
echo "Mode: $([[ $DUMP_MODE -eq 1 ]] && echo Dump || echo Compare)"

# Table list only
TABLES=$(cat <<EOF
customers
products
sales
joined_sales
EOF
)

mkdir -p test/expected
mkdir -p test/tmp
mkdir -p test/diff

STATUS=0
RESULTS=()

while read -r TABLE; do
  EXPECTED_FILE="test/expected/${TABLE}.csv"
  CURRENT_FILE="test/tmp/${TABLE}.csv"
  DIFF_FILE="test/diff/${TABLE}.diff"

  echo ""
  echo "Processing $TABLE..."

  bq query \
    --project_id="$PROJECT_ID" \
    --dataset_id="$DATASET_ID" \
    --use_legacy_sql=false \
    --format=csv \
    --quiet \
    "SELECT * FROM \`${PROJECT_ID}.${DATASET_ID}.${TABLE}\` AS t ORDER BY MD5(TO_JSON_STRING(t))" > "$CURRENT_FILE"

  if [[ $DUMP_MODE -eq 1 ]]; then
    cp "$CURRENT_FILE" "$EXPECTED_FILE"
    echo "Dumped to $EXPECTED_FILE"
    RESULTS+=("$TABLE: DUMPED")
  else
    if diff -u "$EXPECTED_FILE" "$CURRENT_FILE" > "$DIFF_FILE"; then
      echo "OK"
      RESULTS+=("$TABLE: OK")
      rm -f "$DIFF_FILE"
    else
      echo "ERROR (see $DIFF_FILE)"
      STATUS=1
      RESULTS+=("$TABLE: ERROR")
    fi
  fi
done <<< "$TABLES"

echo ""
echo "===== Regression Test Result ====="
for RESULT in "${RESULTS[@]}"; do
  echo "$RESULT"
done

exit $STATUS
