## このプロジェクトについて

このプロジェクトは、BigQuery 上でのスキーマ管理・テストデータ生成・分析クエリの検証・差分比較などを自動化し、CI/CDパイプラインの実現に必要な要素技術を検証することを目的としています。

以下の機能が含まれます：

- テスト用スキーマとデータの一括登録
- joinedテーブルの生成
- リグレッションテストによる差分検出
- NDJSONの構造検証
- SQL分析クエリの一括実行

---

## GCPプロジェクトとBigQuery環境の準備

このプロジェクトを動作させるには、GCP上にBigQueryを有効にしたプロジェクトが必要です。

### 手順の概要

1. GCP コンソールにアクセスする
2. 新しいプロジェクトを作成する
3. BigQuery API を有効化する
4. プロジェクトIDをメモしておく
   - GCPコンソールのナビゲーションバー左上にあるプロジェクト名の右側に表示されています
   - 例：`your-project-id-123456` のような英数字のID

詳細な手順は以下のGoogle Cloudドキュメントをご覧ください：

[プロジェクトの作成と管理|GCPドキュメント](https://cloud.google.com/resource-manager/docs/creating-managing-projects?hl=ja)

---

## 環境構築（MacOS）

このプロジェクトは MacOS上での動作を前提としています。以下の手順で必要な環境をセットアップしてください。

### 前提条件

- MacOS（最新バージョン推奨）
- Python 3.9以降
- Homebrew が導入済み

### 1. Google Cloud SDKのインストールと初期化

```bash
brew install --cask google-cloud-sdk
```

インストール後に以下を実行して認証と初期設定を行ってください：

```bash
gcloud init
gcloud auth application-default login
gcloud config set project [YOUR_PROJECT_ID]
```

※ `[YOUR_PROJECT_ID]` は自身のGCPプロジェクトIDに置き換えてください。

### 2. BigQuery CLI（bq）の動作確認

```bash
bq version
```

正常にバージョン情報が表示されれば完了です。

### 3. Pythonの依存モジュールのインストール

```bash
pip3 install jsonschema
```

---

## テストデータのセットアップ

以後の説明では、"bigquery-study-458607" というプロジェクトIDがあるものとして進めます。全てのコマンドは、このリポジトリのトップをカレントディレクトリにして実行してください。

まず、テストデータを登録します。以下のコマンドを実行してください。

```bash
./scripts/setup_test_datasets.sh bigquery-study-458607
```

customers, products, salesというテーブルが作られ、そこにテスト用のデータが投入されます。各テーブルのスキーマについては、schema/create_table_customers.sqlなどに記述してあります。

salesテーブルには、customer_idおよびproduct_idを外部キーとするcustomersテーブルおよびsalesテーブルへの参照が含まれます。それをLEFT JOINで解決したjoined_salesというテーブルも自動生成されます。

各テーブルが正常に作成されているかどうか、GCPのコンソールで確認してください。

## リグレッションテスト

本プロジェクトには、BigQuery 上のテーブルとローカルに保存された「期待値（expected）」CSVを比較するためのリグレッションテスト機構が含まれています。

### 1. 初回の期待値ダンプ

テストの基準となる「期待値CSV」は以下のコマンドで生成します：

```bash
./scripts/regression_test.sh bigquery-study-458607 --dump
```

`test/expected/` ディレクトリに、BigQuery 上のデータをダンプしたCSVファイルが保存されます。テーブルごとに `ORDER BY` が安定するカラムを指定しているため、差分があっても比較可能です。

### 2. 差分チェック

期待値との差分がないかをチェックするには、以下のコマンドを実行します：

```bash
./scripts/regression_test.sh bigquery-study-458607
```

差分がある場合は、test/diff/ にテーブルごとの*.diffファイルが生成されます。標準出力にも OK/Errorの判定が表示され、差分の有無に応じてプロセスの終了コード（`$?`）も `0` または `1` を返します。

この仕組みにより、クエリやデータ生成スクリプトの変更が既存データに影響していないかを自動で検証できます。

## リトマステスト

一連のタスクを実行した後に、結果として生成されたテーブルに対してルールベースの妥当性検証をしておくと、データやSQLの不備を早期に発見することができます。scripts/litomus_test.shは、SQLのSELECT文を各行に書いたファイルを読み込んで、その結果が1行以上か0行かの判定をします。

結果が1行以上であることを期待するのをポジティブテストと言います。以下のようなファイルを用意します。

```
SELECT count(*) FROM sales01.joined_sales where prefecture = "北海道"
SELECT count(*) FROM sales01.joined_sales where prefecture = "青森県"
SELECT count(*) FROM sales01.joined_sales where gender = "male"
SELECT count(*) FROM sales01.joined_sales where gender = "female"
```

そして、以下のようにテストを実行します。

```bash
./scripts/litmus_test.sh bigquery-study-458607 test/litmus-joined_sales-positive.sql
```

結果が0行であることを期待するのをネガティブテストと言い、以下のようなファイルを用意します。

```
SELECT count(*) FROM sales01.joined_sales where order_id IS NULL
SELECT count(*) FROM sales01.joined_sales where customer_id IS NULL
SELECT count(*) FROM sales01.joined_sales where product_id IS NULL
```

そして、以下のようにテストを実行します。

```bash
./scripts/litmus_test.sh --negative bigquery-study-458607 test/litmus-joined_sales-negative.sql
```

ポジティブテストには、分析結果に当然含まれると期待する条件を書いていきます。ネガティブテストには、各列にNULLなどの不正なデータが入っていないかを調べるのに便利です。各種のコーナーケースをついてポジティブテストやネガティブテストを追加していくと、システムをより堅牢にすることができます。

## ゴールデンテスト

リトマステストは単純なクエリとそれに該当するレコードの存在確認をするのには便利ですが、複雑なクエリとそれに対応する結果の厳密な検証には使えません。ゴールデンテストでは個々のファイルにSELECT文とそれに対する期待値を書くことで、結果が期待値と厳密に一致するかどうかを調べます。まずは、以下のようなゴールデンデータを用意します。

```
SELECT order_id, product_name, customer_name, revenue
FROM sales01.joined_sales
WHERE order_id IN (1, 6)

/*
order_id,product_name,customer_name,revenue
1,けん玉,山下 翼,119720
6,電気毛布,田中 浩,71218
*/
```

このようなファイルを多数用意しておいてから、以下のコマンドを実行します。

```shell
./scripts/golden_test.sh bigquery-study-458607 test/golden-*.sql
```

代表的な正常系は、ゴールデンテストで網羅しておくと良いでしょう。複雑な条件のコーナーケースもゴールデンテストで検査すべきです。それ以外の細かいコーナーケースに関してはリトマステストを大量に書く方が楽です。

## スケジュール付きクエリの登録

現有データの最後の7日間に絞って、かつJOINされたsalesテーブルを作成するタスクを自動実行するとしましょう。スケジュール付きのスクリプトを登録するには、以下のコマンドを実行する。まずは、テストのために、2分後に実行させてみましょう。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  create_table_latest_week_joined_sales \
  schema/create_table_latest_week_joined_sales.sql \
  --run-soon
```

GCPコンソールで、スケジュールされたクエリとしてcreate_table_latest_week_joined_salesが登録されていることを確認します。反映に1分くらい遅延があることがあるので、何度かリロードしてみてください。--run-soonを付けている場合、現在から2分後に実行され、以後毎日同時刻に定期実行されることになります。

登録されているスケジュールクエリを消すには、以下のようにします。実行した後、GCPコンソールで、該当のスケジュール付きクエリが消えていることを確認してください。反映に1分くらい遅延があることがあるので、何度かリロードしてみてください。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  create_table_latest_week_joined_sales \
  --delete
```

本番用に登録するには、以下のようにします。実行後、JSTの14:00に実行されるようになっていることを確認してください。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  create_table_latest_week_joined_sales \
  schema/create_table_latest_week_joined_sales.sql \
```

## JSONのペイロードとJSONスキーマ

salesテーブルには、取引情報がJSON形式のペイロードとして格納されています。パーティショニングと絞り込みのための属性も抽出してあります。

```sql
CREATE OR REPLACE TABLE sales01.sales (
  order_id INT64 NOT NULL,
  date_time TIMESTAMP NOT NULL,
  log_source STRING,
  payload JSON NOT NULL
)
PARTITION BY DATE(date_time)
CLUSTER BY order_id;
```

ペイロードがJSON形式であることで、データ形式の変更に強くなります。一方で、データ形式がSQLスキーマ上で明示されないので、中に何が入っているのか目視で確認するのが大変です。そこで、JSONスキーマを用います。schema/sales-palyoad-schema.jsonに以下のように書いてあります。

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "売上ペイロードスキーマ",
  "description": "sales テーブル内の payload フィールドに格納されている JSON データの構造定義。",
  "type": "object",
  "properties": {
    "order_id": {
      "type": "integer",
      "description": "注文ID。sales テーブルのトップレベルの order_id と一致する。"
    },
    "customer_id": {
      "type": ["integer", "null"],
      "description": "購入した顧客の ID。5% 程度は NULL にすることで不一致のシナリオもテスト可能。"
    },
    "product_id": {
      "type": ["integer", "null"],
      "description": "購入された商品の ID。NULL の場合、商品マスタと JOIN できない想定。"
    },
    "date_time": {
      "type": ["string", "null"],
      "format": "date-time",
      "description": "売上が発生した日時（ISO 8601 形式）。パーティションや時系列分析に利用。"
    },
    "quantity": {
      "type": ["integer", "null"],
      "minimum": 0,
      "description": "購入数量。0 は許容せず、NULL の場合は不明または欠損データ。"
    },
    "revenue": {
      "type": ["integer", "null"],
      "minimum": 0,
      "description": "この売上で発生した収益（単価×数量）。NULL の場合は未確定や非課金取引。"
    },
    "is_proper": {
      "type": ["boolean", "null"],
      "description": "取引が正当かどうかを示すフラグ。精度検証などで使用可能。"
    },
    "log_source": {
      "type": ["string", "null"],
      "enum": ["online", "in_store", null],
      "description": "データの発生元。オンライン注文か実店舗か。NULL の場合は情報不足。"
    }
  },
  "required": ["order_id"]
}
```

test/data-sales.ndjsonがテスト用として投入されるデータですが、それがJSONスキーマに適合しているかどうかは、以下のコマンドで確認できます。

```bash
./scripts/validate_sales_payload.py
```

## 任意の分析クエリの実行

分析クエリは、analyses/ ディレクトリの中にSQLのファイルを置いて、以下のように実行します。単にjoined_salesテーブルの内容を見るなら以下のスクリプトを実行します。

```bash
./scripts/run_analysis.sh bigquery-study-458607 analyses/view_joined_sales.sql
```

関東の女性の間で最も売上高が多い商品を表示するには、以下のようにします。

```bash
./scripts/run_analysis.sh bigquery-study-458607 analyses/view_joined_sales.sql
```

run_analysis.shに複数のSQLファイルを指定した場合、それをcatで結合してから1セッションとして実行します。よって、よく使う一時テーブルを作るようなSQL文を独立させておいて、以下のように実行することもできます。

```bash
./scripts/run_analysis.sh bigquery-study-458607 analyses/make_temp_table.sql analyze_xxx.sql
```

## ChatGPTに分析クエリを提案させる

ChatGPTの最近のバージョン（4o以降）は、BigQuery上のデータの分析を行うための実用的なSQL文を生成する能力がある。ChatGPTをうまく動作させるためには、スキーマなどのコンテキスト情報を適切に渡す必要がある。そのコンテキスト情報を自動的に集めるスクリプトを用意してある。以下を実行する。

```bash
./scripts/generate_chatgpt_context.sh
```

SQLのスキーマとJSONのスキーマをまとめた上で説明文をつけたchatgpt_context.txtというファイルが作られる。ChatGPTのフォームでそれをアップロードしつつ、以下のようなプロンプトを入力する。

```
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
```

すると、SQL文が生成されます。GCPコンソールで実際にそれを実行すると、所望の結果が得られます。

## まとめ：CI/CDの実現に向けて

まず大前提として、運用に必要な全てのファイルはGit上で管理する必要があります。分析対象のデータ、テストデータ、SQLファイル、その他のスクリプトがそれに含まれます。

空のBigQueryプロジェクトを用意して、特定のコマンドを叩くことで、全てが自動的に処理されて、任意のデータ分析が可能な状態をなるべきです。本プロジェクトの各種スクリプトは、その方法をまとめたものです。以下のスクリプトを参考にしてください。

- データのアップロードの方法に関しては、scripts/setup_test_datasets.sh
- リグレッションテストの方法に関しては、scripts/regression_test.sh
- スケジュール付きクエリの登録方法に関しては、scripts/register_scheduled_query.sh
- JSONスキーマによる検証方法に関しては、scripts/validate_sales_payload.py
- 任意のスクリプトをローカルで実行する方法に関しては、scripts/run_analysis.sh
- ChatGPTを使った分析クエリ生成に関しては、scripts/generate_chatgpt_context.sh

GCP上で実験的にクエリを書いて実行しても良いですが、実運用に組み込むものは必ずローカルに保存して実行を確認し、そのファイルをGitで管理してください。GCPとローカルで二重管理になると混乱するので、必ずローカルでGit管理されたSQLファイルを正としましょう。

### CI/CDのその他の方法

本リポジトリでは、scripts/register_scheduled_query.sh を用いたシェルベースの登録スクリプトにより、BigQueryのスケジュール付きクエリを自動デプロイしています。これは軽量で柔軟性が高く、個人開発や小規模プロジェクトに適しています。

一方で、組織開発やチーム連携を見据える場合、より構造化された手段を用いることで運用性・保守性が向上します。以下に代表的なCI/CD構成の選択肢をまとめます。

- 1. Terraform による構成管理（Infrastructure as Code）
  - GCPのスケジュール付きクエリ（BigQuery Data Transfer Config）をterraform applyにより一元管理。
  - Gitで管理された明示的な宣言（HCL）ができ、他のインフラと統一したワークフローが実現できる
  - 初期セットアップに学習コストがかかり、小回りの効く動的スケジューリングには不向き
  - 参考: google_bigquery_data_transfer_config – Terraform Registry
- 2. dbt によるモデル構成とスケジューリング（データ変換中心）
  - SQL変換処理を models/ に定義し、定期的にdbtrunを実行。
  - クエリの依存関係、テスト、文書化が一体化
  - スケジュール付きクエリそのもののデプロイ管理ではなく、個別の運用環境が必要
- 3. Cloud Scheduler + Cloud Functions による動的登録
  - スケジューラがCloud Functionを起動し、BigQuery Transfer ConfigをREST APIで作成・更新。
  - 動的なクエリ生成や条件付き登録が可能で、GCP上で完結する構成
  - Cloud Functionsの保守や認証管理が必要
- 4. 自作シェルスクリプト + REST API（本リポジトリ方式）
  - curl によるREST API呼び出しと bq CLI を組み合わせて登録。
  - 軽量で高速。環境に依存せず動作。GitHub Actionsなどへの組込みも容易
  - エラーハンドリング・構成管理に個別にスクリプトを書く必要あり。
