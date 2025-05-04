#!/bin/bash
set -e

LOCATION="asia-northeast1"
SCHEDULE="every day 05:00"
DUMMY_SCHEDULE=""

RUN_SOON=""
DELETE_ONLY=""
ARGS=()
TEMP_FILES=()

cleanup() {
  for file in "${TEMP_FILES[@]}"; do
    [ -f "$file" ] && rm -f "$file"
  done
}
trap cleanup EXIT

for arg in "$@"; do
  case "$arg" in
    --run-soon)
      RUN_SOON=1
      ;;
    --delete)
      DELETE_ONLY=1
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

if [ ${#ARGS[@]} -lt 2 ]; then
  echo "Usage: $0 [--run-soon] [--delete] PROJECT_ID DISPLAY_NAME [SQL_FILE...]"
  exit 1
fi

PROJECT_ID="${ARGS[0]}"
DATASET_ID="sales01"
DISPLAY_NAME="${ARGS[1]}"
SQL_FILES=("${ARGS[@]:2}")

echo "Project ID: ${PROJECT_ID}"
echo "Dataset ID: ${DATASET_ID}"
echo "Display name: ${DISPLAY_NAME}"
echo "SQL files: ${SQL_FILES[*]}"
echo "Run soon: ${RUN_SOON:+yes}"
echo "Delete only: ${DELETE_ONLY:+yes}"

TRANSFER_NAME="projects/${PROJECT_ID}/locations/${LOCATION}/transferConfigs"
echo "Looking for existing transfer configs with display name '${DISPLAY_NAME}'..."
EXISTING_CONFIG=$(bq ls --project_id="$PROJECT_ID" --transfer_config --transfer_location="$LOCATION" --format=prettyjson | jq -r ".[] | select(.displayName==\"${DISPLAY_NAME}\") | .name")

if [ -n "$EXISTING_CONFIG" ]; then
  echo "Found existing transfer config: ${EXISTING_CONFIG}"
  echo "Deleting existing config..."
  echo "$EXISTING_CONFIG" | xargs -r -n1 bq rm -f --project_id="$PROJECT_ID" --transfer_config
else
  echo "No existing config found."
fi

if [[ -n "$DELETE_ONLY" ]]; then
  echo "Deletion complete. Exiting as requested."
  exit 0
fi

if date -u -d '+23 hours' +%H:%M >/dev/null 2>&1; then
  DUMMY_TIME=$(date -u -d '+23 hours' +%H:%M)
else
  DUMMY_TIME=$(date -u -v+23H +%H:%M)
fi
DUMMY_SCHEDULE="every day ${DUMMY_TIME}"

if [[ -n "$RUN_SOON" ]]; then
  if date -u -d '+2 minutes' +%H:%M >/dev/null 2>&1; then
    FUTURE_TIME=$(date -u -d '+2 minutes' +%H:%M)
  else
    FUTURE_TIME=$(date -u -v+2M +%H:%M)
  fi
  SCHEDULE="every day ${FUTURE_TIME}"
fi

# 1回目（ダミー）用 payload
PAYLOAD=$(mktemp)
TEMP_FILES+=("$PAYLOAD")

cat > "$PAYLOAD" <<EOF
{
  "destinationDatasetId": "${DATASET_ID}",
  "displayName": "${DISPLAY_NAME}",
  "dataSourceId": "scheduled_query",
  "params": {
    "query": "SELECT 'initialized' AS status;",
    "write_disposition": "WRITE_TRUNCATE",
    "destination_table_name_template": "_result_${DISPLAY_NAME}",
    "partitioning_field": ""
  },
  "schedule": "${DUMMY_SCHEDULE}"
}
EOF

echo "Creating transfer config with dummy query..."
ACCESS_TOKEN=$(gcloud auth print-access-token)
CREATE_OUTPUT=$(curl -s -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @"$PAYLOAD" \
  "https://bigquerydatatransfer.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/transferConfigs")

TEMP_JSON="created_config.json"
TEMP_FILES+=("$TEMP_JSON")
echo "$CREATE_OUTPUT" > "$TEMP_JSON"
TRANSFER_CONFIG_ID=$(jq -r .name "$TEMP_JSON")

if [[ "$TRANSFER_CONFIG_ID" == "null" || -z "$TRANSFER_CONFIG_ID" ]]; then
  echo "ERROR: Transfer config creation failed. Cannot continue."
  cat "$TEMP_JSON"
  exit 1
fi

echo "Transfer config created: ${TRANSFER_CONFIG_ID}"
echo "Reading and escaping SQL files..."

COMBINED_SQL=$(cat "${SQL_FILES[@]}")
COMBINED_SQL="${COMBINED_SQL}; SELECT 'done at ' || FORMAT_TIMESTAMP('%F %T', CURRENT_TIMESTAMP(), 'Asia/Tokyo') AS status;"
ESCAPED_SQL=$(echo "$COMBINED_SQL" | sed 's/"/\\"/g' | tr -d '\n')

echo "Updating query and schedule using bq CLI..."

# 実クエリにDDL/DMLが含まれるかチェック
if echo "$COMBINED_SQL" | grep -Ei '^\s*(CREATE|INSERT|UPDATE|DELETE|MERGE)' >/dev/null; then
  PARAMS="{\"query\":\"$ESCAPED_SQL\"}"
else
  PARAMS="{\"query\":\"$ESCAPED_SQL\",\"write_disposition\":\"WRITE_TRUNCATE\",\"destination_table_name_template\":\"_result_${DISPLAY_NAME}\",\"partitioning_field\":\"\"}"
fi

bq update \
  --transfer_config \
  --project_id="$PROJECT_ID" \
  --location="$LOCATION" \
  --params="$PARAMS" \
  --schedule="$SCHEDULE" \
  "$TRANSFER_CONFIG_ID"

echo "Registered scheduled query: ${DISPLAY_NAME} (schedule: ${SCHEDULE})"
