#!/bin/bash
set -e

# Dataset and hardcoded table list
DATASET="sales01"
TABLES=("customers" "products" "sales" "joined_sales")

# Usage help
usage() {
  echo "Usage: $0 --save|--restore|--clean <PROJECT_ID>"
  exit 1
}

# Initialize variables
PROJECT_ID=""
ACTION=""

# Parse arguments in any order
for arg in "$@"; do
  case "$arg" in
    --save|--restore|--clean)
      ACTION="$arg"
      ;;
    *)
      if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="$arg"
      else
        echo "Too many arguments"
        usage
      fi
      ;;
  esac
done

# Validate inputs
if [[ -z "$ACTION" || -z "$PROJECT_ID" ]]; then
  usage
fi

# Execute action for each table
for table in "${TABLES[@]}"; do
  source="${PROJECT_ID}:${DATASET}.${table}"
  backup="${PROJECT_ID}:${DATASET}.${table}_bak"

  case "$ACTION" in
    --save)
      echo "Saving ${source} to ${backup}"
      bq cp -f "$source" "$backup"
      ;;
    --restore)
      echo "Restoring ${backup} to ${source}"
      bq cp -f "$backup" "$source"
      ;;
    --clean)
      echo "Deleting ${backup}"
      bq rm -f -t "$backup"
      ;;
  esac
done
