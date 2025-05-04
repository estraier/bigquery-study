#!/bin/bash
set -e

# Default output format
FORMAT="csv"
ARGS=()

# Parse options
for arg in "$@"; do
  case "$arg" in
    --json)
      FORMAT="prettyjson"
      ;;
    -*)
      echo "Unknown option: $arg"
      exit 1
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

if [ ${#ARGS[@]} -lt 2 ]; then
  echo "Usage: $0 [--json] PROJECT_ID SQL_FILE [SQL_FILE...]"
  exit 1
fi

PROJECT_ID="${ARGS[0]}"
SQL_FILES=("${ARGS[@]:1}")

echo "Project ID: $PROJECT_ID"
echo "SQL files: ${SQL_FILES[*]}"
echo "Output format: $FORMAT"

# Concatenate SQL files
COMBINED_SQL=$(cat "${SQL_FILES[@]}")

# Run query
bq query \
  --project_id="$PROJECT_ID" \
  --nouse_legacy_sql \
  --format="$FORMAT" \
  <<< "$COMBINED_SQL"
