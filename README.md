## このプロジェクトについて

このプロジェクトは、BigQuery 上でのスキーマ管理・テストデータ生成・分析クエリの検証・差分比較などを自動化し、CI/CDパイプラインの実現に必要な要素技術を検証することを目的としています。

以下の機能が含まれます：

- テスト用スキーマとデータの一括登録
- リグレッションテスト、リトマステスト、ゴールデンテストの自動化
- 任意の分析クエリのローカルからの実行指示
- スケジュール付きクエリのローカルからの登録
- JSONスキーマを使ったJSONデータの構造検証
- ChatGPTを使った分析クエリの自動生成支援

BigQueryを使った案件で上記全てを実践する必要はありませんが、一部でも適宜取り入れることで生産性が上がるかもしれません。自動化のためのほとんどの機能は単純なシェルスクリプトなので、案件の内容に応じて適当にカスタマイズして使うのに都合が良いでしょう。

## GCPプロジェクトとBigQuery環境の準備

このプロジェクトを動作させるには、GCP上にBigQueryを有効にしたプロジェクトが必要です。

### 手順の概要

- [GCPコンソール](https://console.cloud.google.com/)にアクセスする
- BigQueryの新しいプロジェクトを作成する
  - 画面上部のプロジェクト選択ツールを選んで、「新しいプロジェクト」を選ぶ。
  - プロジェクト名は適当に分かりやすくつける。組織は「組織なし」でOK。
- BigQuery APIを有効化する
  - 画面左上の三本線メニューから「APIとサービス」を選ぶ。
  - 画面上部の検索窓で「BigQuery API」を検索して選択、有効化。
- プロジェクトIDをメモしておく
  - GCPコンソールのナビゲーションバー左上にあるプロジェクト名の右側に表示されています
  - 例：`your-project-id-123456` のような英数字のID

詳細な手順は[Google Cloud](https://cloud.google.com/resource-manager/docs/creating-managing-projects?hl=ja)ドキュメントをご覧ください。

## 環境構築

このプロジェクトは MacOSまたはLinux上での動作を前提としています。以下の手順で必要な環境をセットアップしてください。

### 前提条件

- Python 3.9以降
- Homebrewやaptなどのパッケージ管理システム
- Git

### Google Cloud SDKのインストールと初期化

Homebrewの場合は以下のコマンドを実行します。それ以外の場合は適当に調べてください。

```bash
brew install --cask google-cloud-sdk
```

インストール後に以下を実行して認証と初期設定を行ってください。

```bash
gcloud init
gcloud auth application-default login
gcloud config set project [YOUR_PROJECT_ID]
```

※ `[YOUR_PROJECT_ID]` は自身のGCPプロジェクトIDに置き換えてください。

### BigQuery CLI（bq）の動作確認

```bash
bq version
```

正常にバージョン情報が表示されればOKです。執筆時点の最新版は2.1.15です。

### Pythonの依存モジュールのインストール

```bash
pip3 install jsonschema
```

### 本プロジェクトのリポジトリをダウンロード

```bash
git clone https://github.com/estraier/bigquery-study.git
```

カレントディレクトリにbigquery-studyというディレクトリが作られます。以後の作業はその中で行います。

## データ構造

本プロジェクトでは、顧客と商品のマスターデータと、どの顧客がどの商品を買ったかというトランザクションデータを扱います。概念的には以下のような構造になります。実際にはBigQueryではPK制約やFK制約はサポートされていません。

- customers
  - customer_id INT64 (PK)
  - customer_name STRING
  - birtyday DATE
  - gender STRING
  - prefecture STRING
  - is_premium BOOL
- products
  - product_id INT64 (PK)
  - product_name STRING
  - product_category STRING
  - cost FLOAT64
- sales
  - order_id INT64 (PK)
  - customer_id INT64 (FK)  -> customers.customer_id
  - product_id INT64 (FK)  -> products.customer_id
  - date_time TIMESTAMP
  - quantity INT64
  - revenue INT64
  - is_proper BOOL
  - log_source STRING

salesテーブルの多くのプロパティは実際にはJSONに入れてスキーマレスで扱っています。ログやトランザクションのデータではJSONやProtocol Buffersを使ったスキーマレスデータを扱うことが多いので、そのようなユースケースを模倣するためです。

## テストデータのセットアップ

以後の説明では、"bigquery-study-458607" というプロジェクトIDがあるものとして進めます。実際にコマンドを実行する際には、あなたのプロジェクトIDに読み替えてください。全てのコマンドは、このリポジトリのトップをカレントディレクトリにして実行してください。

以下のコマンドで、"sales01" というデータセットを作成してください。テーブルやスケジュール付きクエリはこの中に格納されます。

```bash
bq mk --dataset --location=asia-northeast1 bigquery-study-458607:sales01
```

sales01データセットにテストデータを登録します。以下のコマンドを実行してください。

```bash
./scripts/setup_test_datasets.sh bigquery-study-458607
```

customers, products, salesというテーブルが作られ、そこにテスト用のデータが投入されます。各テーブルのスキーマについては、schema/create_table_customers.sqlなどに記述してあります。

salesテーブルには、customer_idおよびproduct_idを外部キーとするcustomersテーブルおよびsalesテーブルへの参照が含まれます。それをINNER JOINで解決したjoined_salesというテーブルも自動生成されます。普通、このような結合テーブルは分析クエリを実行する際に必要なプロパティのみを抽出して動的に作るものですが、ここではデモ用途で予め作っています。

各テーブルが正常に作成されているかどうか、GCPのコンソールで確認してください。

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
./scripts/run_analysis.sh bigquery-study-458607 \
  analyses/make_temp_table.sql analyses/analyze_xxx.sql
```

## リグレッションテスト

本プロジェクトには、BigQuery 上のテーブルとローカルに保存された「期待値（expected）」CSVを比較するためのリグレッションテスト機構が含まれています。

テストの基準となる「期待値CSV」は以下のコマンドで生成します。

```bash
./scripts/regression_test.sh bigquery-study-458607 --dump
```

`test/expected/` ディレクトリに、BigQuery 上のデータをダンプしたCSVファイルが保存されます。テーブルごとに `ORDER BY` が安定するカラムを指定しているため、差分があっても比較可能です。

期待値との差分がないかをチェックするには、以下のコマンドを実行します。

```bash
./scripts/regression_test.sh bigquery-study-458607
```

差分がある場合は、test/diff/ にテーブルごとの*.diffファイルが生成されます。標準出力にも OK/Errorの判定が表示されます。

この仕組みにより、クエリやデータ生成スクリプトの変更が既存データに影響していないかを自動で検証できます。実運用で継続的に維持すべきデータベースがある場合、開発計画の中でそれらのデータベースが変更されるかどうかに関わらず、念の為にリグレッションテストを通しておいた方が良いでしょう。本番環境でのデプロイ作業の前後でもリグレッションテストを行うと安心です。

## リトマステスト

一連のタスクを実行した後に、結果として生成されたテーブルに対してルールベースの妥当性検証をしておくと、データやSQLの不備を早期に発見することができます。scripts/litmus_test.shは、SQLのSELECT文を各行に書いたファイルを読み込んで、その結果が1行以上か0行かの判定をします。

結果が1行以上であることを期待するのをポジティブテストと言います。以下のようなファイルを用意します。SELECT count(*)であるSQL文を各行に書きます。

```sql
SELECT count(*) FROM sales01.joined_sales where prefecture = "北海道";
SELECT count(*) FROM sales01.joined_sales where prefecture = "青森県";
SELECT count(*) FROM sales01.joined_sales where gender = "male";
SELECT count(*) FROM sales01.joined_sales where gender = "female";
```

そして、以下のようにテストを実行します。

```bash
./scripts/litmus_test.sh bigquery-study-458607 test/litmus-joined_sales-positive.sql
```

結果が0行であることを期待するのをネガティブテストと言います。以下のようなファイルを用意します。書式はポジティブの時と同様です。

```sql
SELECT count(*) FROM sales01.joined_sales where order_id IS NULL;
SELECT count(*) FROM sales01.joined_sales where customer_id IS NULL;
SELECT count(*) FROM sales01.joined_sales where product_id IS NULL;
```

そして、以下のようにテストを実行します。

```bash
./scripts/litmus_test.sh --negative bigquery-study-458607 test/litmus-joined_sales-negative.sql
```

ポジティブテストには、分析結果に当然含まれると期待する条件を書いていきます。ネガティブテストには、各列にNULLなどの不正なデータが入っていないかを調べるのに便利です。各種のコーナーケースをついてポジティブテストやネガティブテストを追加していくと、システムをより堅牢にすることができます。

## ゴールデンテスト

リトマステストは単純なクエリとそれに該当するレコードの存在確認をするのには便利ですが、複雑なクエリとそれに対応する結果の厳密な検証には使えません。ゴールデンテストでは個々のファイルにSELECT文とそれに対する期待値を書くことで、結果が期待値と厳密に一致するかどうかを調べます。まずは、以下のようなゴールデンデータを用意します。任意のSQL文を書き、その下のブロックコメントの中に期待する結果のCSVを書きます。

```sql
SELECT order_id, product_name, customer_name, revenue
FROM sales01.joined_sales
WHERE order_id IN (1, 6)

/*
order_id,product_name,customer_name,revenue
1,けん玉,山下 翼,119720
6,電気毛布,田中 浩,71218
*/
```

このようなファイルをいくつか用意しておいてから、以下のコマンドを実行します。

```shell
./scripts/golden_test.sh bigquery-study-458607 test/golden-*.sql
```

代表的な正常系は、ゴールデンテストで網羅しておくと良いでしょう。複雑な条件のコーナーケースもゴールデンテストで検査すべきです。それ以外の細かいコーナーケースに関してはリトマステストを大量に書く方が楽です。

## スケジュール付きクエリの登録

joined_salesの中身を見るためのview_joined_salesをスケジュール付きクエリとして登録して実行してみましょう。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  view_joined_sales \
  analyses/view_joined_sales.sql \
  --run-soon
```

GCPコンソールで、スケジュールされたクエリとしてview_joined_salesが登録されていることを確認します。反映に1分くらい遅延があることがあるので、何度かリロードしてみてください。

BigQueryの仕様上、スケジュール付きクエリとしてAPI経由で登録したクエリは、即座に実行された上で、以後定期的に実行されることになります。それを回避すべく、このスクリプトでは、何もしないダミーのクエリをまずは登録して即時1回目の実行をさせた上で、内容を上書きしています。--run-soonを付けている場合、現在から2分後に2回目の実行がスケジュールされます。以後毎日同時刻に定期実行されることになります。

2分後にGCPコンソールのテーブル一覧を確認すると、_result_view_joined_salesというテーブルが作られているはずです。そこにクエリの結果が書き込まれています。

登録されているスケジュールクエリを消すには、以下のようにします。実行した後、GCPコンソールで、該当のスケジュール付きクエリが消えていることを確認してください。こちらも反映に時間がかかることがあります。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  view_joined_sales --delete
```

本番用に登録するには、--run-soonを外して登録します。実行後、JSTの14:00に実行されるようになっていることを確認してください。実行時間はスクリプトの中にハードコードされています。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  view_joined_sales \
  analyses/view_joined_sales.sql
```

スケジュール付きクエリではDDLも発行できます。現有データの最後の7日間に絞って、かつJOINされたsalesテーブルを作成するタスクを自動実行するとしましょう。スケジュール付きのスクリプトを登録するには、実行すべきSQLファイルを準備した上で、以下のコマンドを実行します。まずは、テストのために、2分後に実行させてみましょう。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  create_table_latest_week_joined_sales \
  schema/create_table_latest_week_joined_sales.sql \
  --run-soon
```

GCPコンソールで、スケジュールされたクエリとしてcreate_table_latest_week_joined_salesが登録されていることを確認します。反映に1分くらい遅延があることがあるので、何度かリロードしてみてください。

2分後にクエリが実行されると、latest_week_joined_salesというテーブルが生成されているはずです。また、_result_create_table_latest_week_joined_salesも生成されますが、それには特に何も格納されません。

## ダッシュボード

日々更新されるデータの概要を表やグラフで閲覧できるようにするには、各種のダッシュボード機能を使うと便利です。BigQueryと連携する場合、[Looker Studio](https://lookerstudio.google.com/)を使うのが便利です。

どの表示サービスと連携するにせよ、ダッシュボードに表示するためのデータをテーブルとして作成しておく必要があります。また、そのテーブルの内容は定期的に更新されるべきです。そのため、スケジュール付きクエリの結果のテーブルを使うのが便利です。

analyses/category_sales_by_date.sqlは、製品カテゴリ別の売上げ総額を日毎に集計するクエリです。これをスケジュール付きクエリとして登録しましょう。

```bash
./scripts/register_scheduled_query.sh bigquery-study-458607 \
  category_sales_by_date \
  analyses/category_sales_by_date.sql \
  --run-soon
```

該当のスケジュール付きクエリが実行がされると、_result_category_sales_by_dateというテーブルが生成されているはずです。

次に、Looker Studioのページに言って、「空のレポート」「Big Query」と進んで、「データレポートの追加」のところで、「bigquery-study（あなたのプロジェクト名）」「sales01」「_result_category_sales_by_date」を選んで「追加」ボタンを押します。レポート画面になったら「グラフを追加」「折れ線グラフ」を選択して画面に貼り付けます。そのグラフを選択して、「ディメンション」に「sales_date」を、「内訳ディメンション」に「product_category」を、「指標」に「total_revenue」を設定します。その後、「共有」機能で適宜共有すれば良いでしょう。

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

## ChatGPTに分析クエリを提案させる

ChatGPTの最近のバージョン（4o以降）は、BigQuery上のデータの分析を行うための実用的なSQL文を生成する能力があります。ただし、ChatGPTをうまく動作させるためには、スキーマなどのコンテキスト情報を適切に渡す必要があります。そこで、そのコンテキスト情報を自動的に集めるスクリプトを用意してあります。以下を実行してください。

```bash
./scripts/generate_chatgpt_context.sh
```

SQLのスキーマとJSONのスキーマをまとめた上で説明文をつけたchatgpt_context.txtというファイルが作られます。中身を確認してみてください。

ChatGPTのフォームでそれをアップロードしつつ、以下のようなプロンプトを入力します。

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

すると、SQL文が生成されます。GCPコンソールで実際にそれを実行すると、所望の結果が得られます。一撃で常に完璧な結果が得られるとは限りませんが、上記のような単純な例だと9割方は一撃でうまくいきます。実行時にエラーが出た場合は、そのエラーメッセージを貼り付ければ直してくれます。所望の結果と違う場合には、その旨を書き込めば別案を提案してくれます。人間が最初からクエリを書いていくよりは遥かに効率的に作業が完了します。

## クリーンアップ

データセットを削除したくなったなら、以下のコマンドを実行してください。データセットに含まれる全てのテーブルやルーチンも削除されます。

```bash
bq rm -r bigquery-study-458607:sales01
```

全てのスケジュール付きクエリを削除したくなったなら、以下のコマンドを実行してください。

```bash
./scripts/register_scheduled_query.sh --delete-all bigquery-study-458607
```

## まとめ：CI/CDの実現に向けて

大前提として、運用に必要な全てのファイルはGit上で管理する必要があります。分析対象のデータ、テストデータ、SQLファイル、その他のスクリプトがそれに含まれます。

空のBigQueryプロジェクトを用意して、特定のコマンドを叩くことで、全てが自動的に処理されて、任意のデータ分析が可能な状態になるべきです。本プロジェクトの各種スクリプトは、その方法をまとめたものです。以下のスクリプトを参考にしてください。

- データのアップロードの方法に関しては、scripts/setup_test_datasets.sh
- リグレッションテストの方法に関しては、scripts/regression_test.sh
- スケジュール付きクエリの登録方法に関しては、scripts/register_scheduled_query.sh
- JSONスキーマによる検証方法に関しては、scripts/validate_sales_payload.py
- 任意のスクリプトをローカルで実行する方法に関しては、scripts/run_analysis.sh
- ChatGPTを使った分析クエリ生成に関しては、scripts/generate_chatgpt_context.sh

GCP上で実験的にクエリを書いて実行しても良いですが、実運用に組み込むものは必ずローカルに保存して実行を確認し、そのファイルをGitで管理してください。GCPとローカルで二重管理になると混乱するので、必ずローカルでGit管理されたSQLファイルを正本としましょう。

本番と開発とテストで全く同じSQLファイルを使うためには、プロジェクトIDを分ける必要があります。本番、開発、テストでそれぞれプロジェクトを作っておきます。テストを行う際には、テスト環境のプロジェクトを空にして、テストデータのアップロードからテストの実行までを全て自動化して行います。そのためには上述のスクリプトを組み合わせて実行するシェルスクリプトを書きます。

テストが完了したなら、今度は本番環境に適用するための手順をスクリプトとしてまとめます。本番環境のプロジェクトは空にするわけにはいかないことが多いので、必要な部分だけを入れ替える手順になるでしょう。本番環境を模した状態をテスト環境で構築するスクリプトと、それに対して差分を適用するスクリプトに分けておけば、テスト環境で本番デプロイの検証ができます。

### CI/CDのその他の方法

本リポジトリでは、scripts/register_scheduled_query.sh を用いたシェルベースの登録スクリプトにより、BigQueryのスケジュール付きクエリを自動デプロイしています。これは軽量で柔軟性が高く、個人開発や小規模プロジェクトに適しています。

一方で、組織開発やチーム連携を見据える場合、より構造化された手段を用いることで運用性・保守性が向上します。以下に代表的なCI/CD構成の選択肢をまとめます。

- Terraform による構成管理（Infrastructure as Code）
  - GCPのスケジュール付きクエリ（BigQuery Data Transfer Config）をterraform applyにより一元管理。
  - Gitで管理された明示的な宣言（HCL）ができ、他のインフラと統一したワークフローが実現できる
  - 初期セットアップに学習コストがかかり、小回りの効く動的スケジューリングには不向き
- dbt によるモデル構成とスケジューリング（データ変換中心）
  - SQL変換処理を models/ に定義し、定期的にdbtrunを実行。
  - クエリの依存関係、テスト、文書化が一体化
  - スケジュール付きクエリそのもののデプロイ管理ではなく、個別の運用環境が必要
- Cloud Scheduler + Cloud Functions による動的登録
  - スケジューラがCloud Functionを起動し、BigQuery Transfer ConfigをREST APIで作成・更新。
  - 動的なクエリ生成や条件付き登録が可能で、GCP上で完結する構成
  - Cloud Functionsの保守や認証管理が必要
- 自作シェルスクリプト + REST API（本リポジトリ方式）
  - curlによるREST API呼び出しとbq CLIを組み合わせて登録。
  - 軽量で高速。環境に依存せず動作。GitHub Actionsなどへの組込みも容易
  - エラーハンドリング・構成管理に個別にスクリプトを書く必要あり。

デプロイ作業が頻繁にある場合、シェルベースの運用においてもGitHub Actionsで自動化することも視野に入ってきます。しかし、そもそも分析用クエリを足す以外のデプロイ作業が頻繁にある事が望ましくないので、運用体制を考える方が先でしょう。
