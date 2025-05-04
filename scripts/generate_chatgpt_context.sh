#!/bin/bash
set -e

OUTPUT_FILE="chatgpt_context.txt"
SCHEMA_DIR="./schema"
ANALYSIS_DIR="./analyses"

# List of SQL schema files (in order)
TABLE_FILES=(
  "create_table_customers.sql"
  "create_table_products.sql"
  "create_table_sales.sql"
  "create_table_joined_sales.sql"
)

# Corresponding descriptions (same order as TABLE_FILES)
TABLE_DESCRIPTIONS=(
  "顧客マスタテーブル（id、氏名、性別、住所など）"
  "商品マスタテーブル（id、商品名、カテゴリなど）"
  "売上データ（id、customer_id、product_id、date_time、数量）"
  "顧客・商品・売上を結合した詳細ビュー"
)

# JSON schema file
JSON_SCHEMA_FILE="$SCHEMA_DIR/sales-palyoad-schema.json"

echo "Generating context file for ChatGPT analysis prompt..."
> "$OUTPUT_FILE"

echo "## BigQuery データセット情報（分析支援用）" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "このプロジェクトでは、BigQuery データセット \`sales01\` を使用しています。" >> "$OUTPUT_FILE"
echo "以下は、データスキーマとその構造に関する説明です。" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Iterate over schema files and descriptions
for i in "${!TABLE_FILES[@]}"; do
  sql_file="${TABLE_FILES[$i]}"
  description="${TABLE_DESCRIPTIONS[$i]}"
  path="$SCHEMA_DIR/$sql_file"
  table_name=$(echo "$sql_file" | sed 's/^create_table_//' | sed 's/.sql$//')

  echo "### テーブル名: $table_name" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  echo "$description" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  echo "定義ファイル: \`$sql_file\`" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  awk '/CREATE TABLE|CREATE OR REPLACE TABLE/,/);/' "$path" | sed 's/^/    /' >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
done

# JSON schema
if [ -f "$JSON_SCHEMA_FILE" ]; then
  echo "### JSON スキーマ: $(basename "$JSON_SCHEMA_FILE")" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  echo "このスキーマは、NDJSON形式で取り込まれる sales payload の構造を定義しています。" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  echo '```json' >> "$OUTPUT_FILE"
  cat "$JSON_SCHEMA_FILE" | jq '.' >> "$OUTPUT_FILE"
  echo '```' >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

echo "Generated $OUTPUT_FILE"

# Japanese prompt template
echo ""
echo "----- ChatGPTへのプロンプトテンプレート（入力欄つき）-----"
cat <<EOF

あなたはマーケティング分析に詳しいアシスタントです。

添付ファイル（chatgpt_context.txt）には、BigQueryで管理している sales01 データセットのスキーマや背景情報が記載されています。
この情報をもとに、以下の要件に合致する分析クエリを1つ提案してください。

---

目的：
関東地方の顧客によく売れているのに関西地方の顧客には売れていない商品を調べる。
商品毎に関東地方の顧客への売上と関西地方の顧客への売上の総額を調べ、その差が大きいものから順に20件提示する。

出力例：
商品ID,商品名,関東地方売上,関西地方売上,差額

補足：
salesテーブルを起点にしてcustomersテーブルとproductsテーブルをJOINして集計を行う。
JOINに失敗したレコードや、NULL値により売上が計算できないレコードは除外する。

EOF
