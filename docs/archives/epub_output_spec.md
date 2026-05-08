# 📖 EPUB 出力仕様書

## 1. 概要

Vivliostyle CLI の `--format epub` オプションを利用して、書籍プロジェクトから EPUB ファイルを生成する機能。
PDF ビルドパイプラインとは独立した専用ステップとして実装し、`output.targets` に `epub` が含まれる場合に自動実行する。

### 1.1 EPUB の用途と表紙の扱い

EPUB の配信先によって、表紙（front cover）の扱いが異なる。

| 配信先 | 表紙の扱い | 裏表紙 |
|:---|:---|:---|
| **楽天 Kobo** | EPUB 内に表紙画像を含めて出品 | 不要 |
| **Apple Books** | EPUB 内に表紙画像を含めて出品 | 不要 |
| **Amazon Kindle** | 本文 EPUB と表紙画像を**別々にアップロード** | 不要 |

このため、`book.yml` で **表紙を EPUB に含めるか否か** を設定できるようにする。
裏表紙は電子書籍では不要であり、EPUB には含めない。

---

## 2. 設定（`config/book.yml`）

### 2.1 ビルド対象の判定

`output.targets` に `epub` が含まれている場合に EPUB を生成する。

```yaml
output:
  targets: pdf, epub       # epub を含めると EPUB も生成
  # targets: epub          # EPUB のみ生成
  # targets: [pdf, epub]   # 配列形式も可
```

### 2.2 epub セクション

```yaml
output:
  epub:
    cover:
      embed: true                # 表紙画像を EPUB に埋め込むか（既定: true）
      image: cover.jpg           # 表紙画像ファイル（covers/ ディレクトリ配下）
    layout: reflowable           # reflowable（リフロー型）/ fixed（固定レイアウト型）
```

### 2.3 設定項目の詳細

| キー | 型 | 既定値 | 説明 |
|:---|:---|:---|:---|
| `cover.embed` | Boolean | `true` | 表紙画像を EPUB に埋め込むか。`false` にすると Kindle 向けの表紙なし EPUB を生成。画像ファイル自体はどちらの場合も `vs cover epub` で生成する |
| `cover.image` | String | `cover.jpg` | 表紙画像ファイル名。`covers/` ディレクトリ配下に配置 |
| `layout` | String | `reflowable` | EPUB のレイアウト方式。`reflowable`（リフロー型）または `fixed`（固定レイアウト型） |

> **注**: メタデータ（`title`, `author`, `language`, `isbn`, `publisher`）は `book` セクションから自動的に流用される。`vivliostyle.config.js` の `title`, `author`, `language` と同期する。

### 2.4 Kindle 向け設定例

```yaml
output:
  targets: epub
  epub:
    cover:
      embed: false             # Kindle では表紙を別途アップロードするため埋め込まない
      image: cover.jpg         # 画像自体は生成する（Kindle に別途アップロード用）
```

### 2.5 楽天 Kobo / Apple Books 向け設定例

```yaml
output:
  targets: epub
  epub:
    cover:
      embed: true              # 表紙を EPUB に埋め込む
      image: cover.jpg         # 1600×2560 推奨
```

---

## 3. 実装方針

### 3.1 Vivliostyle CLI の EPUB 出力

Vivliostyle CLI は `--format epub` オプションで EPUB を直接出力できる。

```bash
npx vivliostyle build --format epub --output output.epub
```

既存の `vivliostyle.config.js` をそのまま利用し、`entry`（= `entries.js`）に基づいて EPUB を構成する。

### 3.2 表紙の制御

表紙を含める場合と含めない場合で、`entries.js` の構成を切り替える。

- **`cover.embed: true`**: 表紙画像を EPUB のカバーページとして埋め込む
- **`cover.embed: false`**: 表紙を埋め込まず本文のみの EPUB を生成（表紙画像は別途配信先にアップロード）

Vivliostyle CLI は `vivliostyle.config.js` の `cover` プロパティで表紙画像を指定できる。

```javascript
// cover.embed: true の場合
const vivliostyleConfig = {
  title: '初めてのウェブアプリ開発',
  author: 'アトリヱ未來',
  language: 'ja',
  size: 'A5',
  cover: './covers/cover.jpg',  // ← 表紙画像
  entry: entries,
  output: ['./output.epub']
};
```

### 3.3 EPUB 専用 entries.js の構成

EPUB では PDF 向けの以下の要素を**除外**する。

| 要素 | PDF | EPUB | 理由 |
|:---|:---:|:---:|:---|
| 表紙（`_titlepage`） | ○ | △ | EPUB は `cover` プロパティで別途指定 |
| 権利表記（`_legalpage`） | ○ | ○ | 含める |
| 目次（`_toc`） | ○ | × | EPUB リーダーが自動生成 |
| 中扉（`_part{N}`） | ○ | ○ | 含める |
| 索引（`_indexpage`） | ○ | ○ | リフロー型ではページ番号は無意味だが、リンクは有効なのでそのまま含める |
| 用語集（`_glossarypage`） | ○ | ○ | リンクは有効なのでそのまま含める |
| 奥付（`_colophon`） | ○ | ○ | 含める |
| 裏表紙 | ○ | × | 電子書籍では不要 |

### 3.4 内部で生成されるコマンド例

```bash
# 表紙あり
npx vivliostyle build --format epub --output janken_v0.1.0.epub

# 表紙なし（Kindle 向け）
npx vivliostyle build --format epub --output janken_v0.1.0.epub
# （vivliostyle.config.js から cover プロパティを除外）
```

### 3.5 出力ファイル名

既存の `Common.generate_epub_filename` メソッドに準拠する。

| 出力 | ファイル名例 | 説明 |
|:---|:---|:---|
| EPUB | `janken_v0.1.0.epub` | `project.name` + バージョン |

---

## 4. ビルドパイプラインへの統合

### 4.1 EPUB ビルドの実行タイミング

EPUB ビルドは PDF ビルドとは独立して実行する。
PDF ビルド完了後（Step 12 の後）に EPUB 生成ステップを追加する。

```
Step 0-5:   HTML 生成（PDF/EPUB 共通）
Step 6-12:  PDF ビルド・結合・アウトライン（pdf ターゲット時）
Step 13:    入稿用 PDF 生成（print_pdf ターゲット時）
Step E:     EPUB 生成（epub ターゲット時）
```

### 4.2 HTML の再利用

Step 5 で生成済みの章 HTML をそのまま EPUB の入力として使用する。
EPUB 用に HTML を再生成する必要はない。

### 4.3 vivliostyle.config.js の動的書き換え

EPUB ビルド時に `vivliostyle.config.js` を一時的に書き換える（または EPUB 専用の設定ファイルを生成する）。

変更点:
- `output`: `['./output.epub']` に変更
- `cover`: `cover.embed: true` の場合のみ追加
- `entry`: 目次・裏表紙を除外した entries を使用

### 4.4 pipeline.rb への追加

```ruby
# epub ターゲットが含まれる場合
if epub_target?
  add_step('Step E (generate epub)', -> { run_step_epub })
end
```

---

## 5. 実装詳細

### 5.1 変更対象ファイル

| ファイル | 変更内容 |
|:---|:---|
| `lib/vivlio/starter/cli/pdf.rb` | `EpubCommandRunner` クラスを新規追加（または別ファイル `epub.rb` に分離） |
| `lib/vivlio/starter/cli/build/pipeline.rb` | `epub_target?` 判定と EPUB ビルドステップの追加 |
| `lib/vivlio/starter/cli/build/pdf_builder.rb` | EPUB 用 entries 生成メソッドの追加（目次・裏表紙を除外） |
| `vivliostyle.config.js` | EPUB ビルド時の動的書き換え、または EPUB 専用設定ファイルの生成 |
| `config/book.yml` | `output.epub` セクションの設定項目を整備（既存） |

### 5.2 EpubCommandRunner の概要

```ruby
class EpubCommandRunner
  def initialize(options, target_output = nil)
    @options = options || {}
    @target_output = target_output
    @epub_config = Common::CONFIG.output&.epub
  end

  def call
    prepare_epub_config!
    execute_build
    handle_build_result
  ensure
    restore_config!
  end

  private

  def build_command
    cmd = 'npx vivliostyle build --format epub'
    cmd += " --output #{output_filename}"
    cmd
  end

  def output_filename
    @target_output || Common.generate_epub_filename
  end

  # vivliostyle.config.js を EPUB 用に一時書き換え
  def prepare_epub_config!
    # cover プロパティの追加/除外
    # output を .epub に変更
  end

  def restore_config!
    # vivliostyle.config.js を元に戻す
  end
end
```

### 5.3 表紙画像の仕様

| 項目 | 仕様 |
|:---|:---|
| **推奨サイズ** | 1600 × 2560 px（縦横比 1:1.6） |
| **形式** | JPEG（品質 90% 推奨） |
| **配置場所** | `covers/` ディレクトリ配下 |
| **生成方法** | `vs cover epub` コマンドで自動生成（既存実装） |

> 表紙画像は `vs cover epub` コマンドで `frontcover_master.png` から自動生成できる（cover_spec.md 参照）。

---

## 6. EPUB メタデータ

Vivliostyle CLI は `vivliostyle.config.js` のプロパティから EPUB メタデータを自動設定する。

| EPUB メタデータ | 設定元（`book.yml`） | `vivliostyle.config.js` |
|:---|:---|:---|
| `dc:title` | `book.main_title` + `book.subtitle` | `title` |
| `dc:creator` | `book.author` | `author` |
| `dc:language` | `book.language` | `language` |
| `dc:identifier` | `book.isbn`（任意） | — |
| `dc:publisher` | `book.publisher` | — |

> ISBN が未設定の場合、Vivliostyle CLI は UUID ベースの識別子を自動生成する。

---

## 7. PDF との差異

| 項目 | PDF | EPUB |
|:---|:---|:---|
| **目次** | `_toc.html` を生成・挿入 | EPUB リーダーが自動生成（NCX/nav） |
| **表紙** | `frontcover_rgb.pdf` を結合 | `cover.jpg` を EPUB 内に埋め込み（設定次第） |
| **裏表紙** | `backcover_rgb.pdf` を結合 | 不要（含めない） |
| **ノンブル** | CSS `counter(page)` で表示 | EPUB リーダーが管理 |
| **中扉** | `_part{N}.html` を挿入 | そのまま含める |
| **ページサイズ** | `size: A5` 等で固定 | リフロー型の場合はリーダー依存 |
| **フォント** | Web フォント埋め込み | 埋め込まない（`serif` / `sans-serif` / `monospace` の汎用指定） |
| **索引・用語集** | ページ番号付きで掲載 | ページ番号は無意味だがリンクは有効なのでそのまま掲載 |
| **CSS `@page`** | 版面制御に使用 | EPUB リーダーが無視（問題なし） |

---

## 8. テスト計画

### 8.1 ユニットテスト

| テスト | 検証内容 |
|:---|:---|
| `epub_target?` | `output.targets` に `epub` が含まれる場合に `true` を返す |
| `generate_epub_filename` | `project_name_vX.Y.Z.epub` 形式の出力 |
| `build_command` | `--format epub` オプションが正しく組み立てられる |
| 表紙設定 | `cover.embed: true/false` で `cover` プロパティの有無が切り替わる |
| レイアウト設定 | `layout: reflowable/fixed` が正しく反映されること |

### 8.2 統合テスト

| テスト | 検証内容 |
|:---|:---|
| `targets: epub` | EPUB ファイルが生成されること |
| `targets: pdf, epub` | PDF と EPUB の両方が生成されること |
| `cover.embed: true` | EPUB 内に表紙画像が含まれること |
| `cover.embed: false` | EPUB 内に表紙画像が含まれないこと |
| `layout: reflowable` | リフロー型 EPUB が生成されること |
| `layout: fixed` | 固定レイアウト型 EPUB が生成されること |
| `targets: pdf` のみ | EPUB が生成されないこと |

### 8.3 目視確認

- EPUB リーダー（Apple Books、Calibre 等）で表示を確認
- 目次ナビゲーションが正しく機能すること
- 中扉ページが正しく表示されること
- 表紙画像の有無が設定どおりであること

---

## 9. 実装優先度

| 優先度 | 機能 | 備考 |
|:---|:---|:---|
| **P0** | `vivliostyle build --format epub` による基本 EPUB 生成 | Vivliostyle CLI ネイティブ機能 |
| **P0** | `cover.embed` による表紙の埋め込み/除外切り替え | Kindle vs 楽天/Apple の差異に対応 |
| **P1** | `output.targets` 判定によるパイプライン統合 | 既存の `pdf_target?` / `print_pdf_target?` と同様 |
| **P1** | `layout` 設定（`reflowable` / `fixed`）の反映 | `vivliostyle.config.js` に反映 |
| **P2** | EPUB バリデーション（`epubcheck`） | `vs doctor` 連携 |

---

## 10. 未決事項

- [ ] `vivliostyle.config.js` の書き換え方式: 一時書き換え＋復元と EPUB 専用設定ファイル生成の両方を実装し、安定した方を採用する

### 10.1 決定済み事項

- **裏表紙**: EPUB には含めない
- **目次**: EPUB リーダーの自動生成に委ねる（`_toc.html` は除外）
- **表紙制御**: `cover.embed` で Kindle 向け（埋め込みなし）と楽天/Apple 向け（埋め込みあり）を切り替え。表紙画像自体はどちらの場合も生成する
- **出力形式**: Vivliostyle CLI の `--format epub` をそのまま利用
- **読み方向**: 横書き（`ltr`）で実装する。内部的には `readingProgression: 'ltr'` をハードコーディングし、将来の縦書き対応に備える
- **CSS**: `@page` ルールや `break-before: recto` は EPUB リーダーが無視するため、特別な対応は不要。問題が発生した場合に個別対処する
- **フォント**: EPUB にはフォントを埋め込まない。`serif` / `sans-serif` / `monospace` の汎用ファミリ指定で十分
- **索引・用語集**: リフロー型ではページ番号は無意味だが、リンク自体は有効なのでそのまま EPUB に含める
