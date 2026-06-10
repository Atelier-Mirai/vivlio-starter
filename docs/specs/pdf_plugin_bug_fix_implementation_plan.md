# 実装計画: vivlio-starter-pdf から VivlioStarter へのリファクタリング

`vivlio-starter` 本体の名前空間および配置パス変更（`vivlio/starter` から `vivlio_starter`）に伴い、プラグインである `vivlio-starter-pdf` を `vivlio_starter` にリファクタリングし、Enhanced モードでの統合動作を復旧させます。

既存のファイルを新規作成するのではなく、**既存のファイルを配置パスの変更（移動）した上で、名前空間や require などの依存関係のみを微修正する**方針で進めます。

## ユーザーレビューが必要な項目

> [!IMPORTANT]
> この計画では、`vivlio-starter` の隣にある `vivlio-starter-pdf` ディレクトリ内のファイルを修正します。
> また、動作確認のために `vivlio-starter/Gemfile` を一時的に変更し、ローカルの `vivlio-starter-pdf` を参照するように設定します。

## 変更内容

### プラグイン: `vivlio-starter-pdf`

既存の `lib/vivlio/starter/` ディレクトリ配下にあるファイルを、`lib/vivlio_starter/` 配下に移動し、内容を修正します。

#### [MOVE & MODIFY] [pdf.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/pdf.rb)
- `lib/vivlio/starter/pdf.rb` を移動
- 名前空間: `VivlioStarter::Pdf`
- 読み込みパスの修正 (`vivlio/starter` -> `vivlio_starter`)

#### [MOVE & MODIFY] [version.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/pdf/version.rb)
- `lib/vivlio/starter/pdf/version.rb` を移動
- 名前空間: `VivlioStarter::Pdf`

#### [MOVE & MODIFY] [utilities.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/pdf/utilities.rb)
- `lib/vivlio/starter/pdf/utilities.rb` を移動
- 名前空間: `VivlioStarter::Pdf`

#### [MOVE & MODIFY] [reader.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/pdf/reader.rb)
- `lib/vivlio/starter/pdf/reader.rb` を移動
- 名前空間: `VivlioStarter::Pdf::Reader`

#### [MOVE & MODIFY] [log_helper.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/cli/pdf/log_helper.rb)
- `lib/vivlio/starter/cli/pdf/log_helper.rb` を移動
- 名前空間: `VivlioStarter::Pdf::LogHelper`
- 本体のログ出力機能の参照先を `Vivlio::Starter::CLI::Common` から `VivlioStarter::CLI::Common` に変更

#### [MOVE & MODIFY] [outline_writer.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/cli/pdf/outline_writer.rb)
- `lib/vivlio/starter/cli/pdf/outline_writer.rb` を移動
- 名前空間: `VivlioStarter::Pdf::OutlineWriter` のように修正

#### [MOVE & MODIFY] [utilities.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/cli/pdf/utilities.rb)
- `lib/vivlio/starter/cli/pdf/utilities.rb` を移動
- 名前空間: `VivlioStarter::Pdf::Utilities`

#### [MOVE & MODIFY] [enhanced_provider.rb](file:///Users/mirai/projects/vivlio-starter-pdf/lib/vivlio_starter/cli/pdf/enhanced_provider.rb)
- `lib/vivlio/starter/cli/pdf/enhanced_provider.rb` を移動
- 名前空間: `VivlioStarter::Pdf::EnhancedProvider`

#### [DELETE] 旧ディレクトリ: `lib/vivlio` (移動後に空になったら削除)

#### [MODIFY] [vivlio-starter-pdf.gemspec](file:///Users/mirai/projects/vivlio-starter-pdf/vivlio-starter-pdf.gemspec)
- バージョンファイルの読み込み先を修正: `require_relative "lib/vivlio_starter/pdf/version"`
- gemspecのバージョン変数: `VivlioStarter::Pdf::VERSION`

#### [MOVE & MODIFY] [outline_writer_test.rb](file:///Users/mirai/projects/vivlio-starter-pdf/test/vivlio_starter/cli/pdf/outline_writer_test.rb)
- `test/vivlio/starter/cli/pdf/outline_writer_test.rb` を移動
- 名前空間: `VivlioStarter::Pdf::OutlineWriterTest`
- 読み込み先: `vivlio_starter/cli/pdf/outline_writer`

#### [MODIFY] [reader_test.rb](file:///Users/mirai/projects/vivlio-starter-pdf/test/reader_test.rb)
- 定数参照を `Vivlio::Starter::PDF::Reader` から `VivlioStarter::Pdf::Reader` に変更

#### [MODIFY] [test_helper.rb](file:///Users/mirai/projects/vivlio-starter-pdf/test/test_helper.rb)
- `require 'vivlio/starter/pdf'` から `require 'vivlio_starter/pdf'` に変更

#### [DELETE] 旧テストディレクトリ: `test/vivlio` (移動後に空になったら削除)

---

### 本体: `vivlio-starter`

#### [MODIFY] [Gemfile](file:///Users/mirai/projects/vivlio-starter/Gemfile)
- ローカルのリファクタリング中プラグインをロードさせるため、`gem 'vivlio-starter-pdf'` を一時的に `gem 'vivlio-starter-pdf', path: '../vivlio-starter-pdf'` に変更

## 検証計画

### 自動テスト
- プラグイン側のディレクトリで以下のテストを実行し、すべて通過することを確認します。
  ```bash
  cd /Users/mirai/projects/vivlio-starter-pdf
  bundle install
  bundle exec rake test
  ```

### 手動確認
- 本体側のディレクトリ `/Users/mirai/projects/vivlio-starter` で動作確認を行います。
  ```bash
  bundle install
  bundle exec vs build
  ```
- ビルドログをチェックし、`standard` モードから `enhanced` モードに自動で切り替わっていること、および生成された PDF にしおり（アウトライン）が正しく付与されていることを確認します。
