# Vivlio Starter 開発ワークフロー

## gem の再インストール

ローカルで `lib/` 配下のコードを変更した場合、`vs` コマンドは rbenv 経由で gem インストール版を実行するため、変更が反映されない。以下のコマンドで gem を再ビルド・再インストールすること。

```bash
rake reinstall
```

内部的には以下を実行している:
1. `gem uninstall vivlio-starter` — 古い gem を削除
2. `gem build vivlio-starter.gemspec` — ローカルソースから gem をビルド
3. `gem install vivlio-starter-*.gem` — ビルドした gem をインストール

**注意**: `lib/` を編集しただけでは `vs` コマンドに反映されない。必ず `rake reinstall` を実行すること。

## ビルドコマンド

```bash
# 通常ビルド（クリーンアップ + フルビルド）
vs build

# 中間ファイルを残してビルド（デバッグ用）
vs build --no-clean

# 全ログを出力してビルド（問題調査用）
vs build --no-clean --log=debug > build.log

# 単章ビルド（特定の章だけビルド）
vs build 71-emoji
```

### ログレベル

| レベル | オプション | 表示内容 |
|--------|-----------|---------|
| error | `--log=error` | エラーのみ |
| warn | `--log=warn` | 警告以上（デフォルト相当） |
| info | `--log=info` | 補足情報・成功メッセージ |
| debug | `--log=debug` | 全ステップの詳細・タイマー |

### ビルドロック

ビルドが異常終了した場合、`.cache/vs/.build.lock` が残ることがある。次のビルドが「別のプロセスが実行中」エラーになった場合は手動で削除する:

```bash
rm -f .cache/vs/.build.lock
```

## テスト

```bash
# 全テスト実行
rake test

# Techbook 関連テストのみ
ruby -Itest -Ilib -e "Dir.glob('test/vivlio/starter/cli/techbook/*_test.rb').each { require_relative it }"

# 特定のテストファイル
ruby -Itest -Ilib test/vivlio/starter/cli/techbook/emoji_replacer_test.rb
```

## scaffold の同期

`config/`、`contents/`、`stylesheets/` 等を編集した後、scaffold テンプレートに反映するには:

```bash
ruby copy_to_scaffold.rb
```

`config/book.yml` は自動的にプレースホルダー記法（`{{MAIN_TITLE}}` 等）に置換される。
