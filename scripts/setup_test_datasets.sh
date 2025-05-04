#!/bin/bash
set -e

# Parse arguments
PROJECT_ID="$1"
DATASET_ID="sales01"
LOCATION="asia-northeast1"

if [ -z "$PROJECT_ID" ]; then
  echo "Usage: $0 PROJECT_ID"
  exit 1
fi

echo "Using project: $PROJECT_ID"
echo "Using dataset: $DATASET_ID"

# Step 1: Create tables from schema files
echo "Creating tables from schema files..."

for f in schema/create_table_customers.sql schema/create_table_products.sql schema/create_table_sales.sql; do
  if [[ -f "$f" ]]; then
    echo "Executing $f..."
    bq query \
      --project_id="$PROJECT_ID" \
      --location="$LOCATION" \
      --use_legacy_sql=false < "$f"
  else
    echo "Warning: $f not found. Skipping."
  fi
done

# Step 2: Load CSV data into customers and products
echo "Loading CSV data into customers and products..."

echo "Loading customers..."
bq load \
  --project_id="$PROJECT_ID" \
  --location="$LOCATION" \
  --source_format=CSV \
  --skip_leading_rows=1 \
  "${DATASET_ID}.customers" \
  test/data-customers.csv

echo "Loading products..."
bq load \
  --project_id="$PROJECT_ID" \
  --location="$LOCATION" \
  --source_format=CSV \
  --skip_leading_rows=1 \
  "${DATASET_ID}.products" \
  test/data-products.csv

# Step 3: Load JSON data into sales (using explicit schema file)
echo "Loading JSON data into sales..."
bq load \
  --project_id="$PROJECT_ID" \
  --location="$LOCATION" \
  --source_format=NEWLINE_DELIMITED_JSON \
  --schema=schema/sales-schema.json \
  "${DATASET_ID}.sales" \
  test/data-sales.ndjson

# Step 4: Execute SQL to create joined_sales table
echo "Waiting 5 seconds for table creation operations."
sleep 5
JOINED_SQL="schema/create_table_joined_sales.sql"
if [[ -f "$JOINED_SQL" ]]; then
  echo "Creating joined_sales table from $JOINED_SQL..."
  bq query \
    --project_id="$PROJECT_ID" \
    --location="$LOCATION" \
    --use_legacy_sql=false \
    < "$JOINED_SQL"
else
  echo "Warning: $JOINED_SQL not found. Skipping joined_sales creation."
fi
