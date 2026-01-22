# CLI TokenResolver 移行・統合指示書

## 1. 概要
`cli_token_resolver_spec.md` で定義した `TokenResolver` を用い、CLI の章指定を一元化する。これに伴い、従来の `Common.normalize_tokens` への依存を排除し、ビルドパイプラインおよび内部コマンドの構造を刷新する。

## 2. TokenResolver への移行対象
以下の `Common.normalize_tokens` 依存箇所を、すべて `TokenResolver` を使用するように書き換える。

* **SamovarCommands::BuildCommand#expanded_target_tokens**
    * ビルド対象を解決する処理 (@lib/vivlio/starter/cli/samovar/build_command.rb#146-151)
* **CreateCommands.execute_create**
    * 生成対象章のトークン正規化に利用 (@lib/vivlio/starter/cli/create.rb#53-58)
* **DeleteCommands::TargetResolver#normalized_tokens**
    * 削除対象の解析に利用 (@lib/vivlio/starter/cli/delete.rb#179-188)
* **RenameCommandExecutor#rename_single_chapter**
    * 旧名/新名を解析 (@lib/vivlio/starter/cli/rename.rb#295-300)
* **ConvertCommands.execute_convert**
    * Markdown 変換対象の抽出に利用 (@lib/vivlio/starter/cli/convert.rb#26-33)
* **PreProcessCommands.execute_pre_process**
    * 前処理対象の章決定に利用 (@lib/vivlio/starter/cli/pre_process.rb#54-69)
* **PostProcessCommands.execute_post_process**
    * HTML 後処理対象の決定に利用 (@lib/vivlio/starter/cli/post_process.rb#70-85)
* **IndexCommands.resolve_chapters**
    * 対象章の決定に利用 (@lib/vivlio/starter/cli/index.rb#181-196)
* **EntriesCommands.execute_entries**
    * entries.js 生成対象を決める処理 (@lib/vivlio/starter/cli/entries.rb#35-58)
* **MetricsCommands#all_paths**
    * 計測対象の Markdown を列挙 (@lib/vivlio/starter/cli/metrics.rb#126-132)
* **Metrics::Runner#resolve_target_paths**
    * metrics runner の対象を決定 (@lib/vivlio/starter/cli/metrics/runner.rb#446-455)
* **PostProcessCommands::HeadingProcessor 等**
    * 間接参照箇所の正規化処理の更新

## 3. 引数解決のルール
* コマンド引数は `TokenResolver` により解決すること。
* コマンド内部で章番号やパスが必要な場合は、Resolver から返される `Entry` オブジェクトの属性（`entry.number`, `entry.basename`, `entry.path` 等）を使用すること。

## 4. ビルドパイプラインの刷新
* `BuildCommands::TokenExpander` および basename ベースの古い解決処理を廃止する。
* Resolver で取得した `Entry` リストを `pre_process`, `convert`, `post_process`, `entries` の各処理へ直接渡すフローに変更する。
* これら内部処理側も `Entry` オブジェクトの受け取りを前提としたインターフェースに更新する。

## 5. 内部コマンドの完全独立・非公開化
以下のコマンドを CLI から直接実行可能にする機能を廃止し、`build` コマンド等から呼び出される「純粋な内部ロジック」に変更する。
* 廃止対象 CLI 機能：`entries`, `create:titlepage`, `create:colophon`, `create:legalpage`, `pre_process`, `convert`, `post_process`, `toc`, `pdf`, `vivliostyle`
* 不要となる Samovar へのコマンド登録処理および関連コードを削除する。