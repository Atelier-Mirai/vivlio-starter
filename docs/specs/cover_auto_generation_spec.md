# カバー自動生成仕様書

## 概要

`book.yml` の `output.cover` 設定値に基づいて、適切なカバー画像を自動生成する機能の仕様です。

## 背景

現在のシステムでは：
- SVGカバー生成: `vs create:cover` コマンド（表紙・裏表紙両方生成）
- PDF用カバー: `frontcover_master.png` からの変換
- EPUB用カバー: 同じマスター画像からのJPEG変換

これらを統一し、`output.cover` 設定値だけで自動的に適切なカバーを生成します。

---

## 仕様

### 1. 設定値と動作

#### 1.1 `output.cover: "light"`

**生成されるファイル（ビルド対象サイズのみ）:**
- `covers/frontcover_light_{size}_rgb.pdf` - PDF用表紙（`targets: pdf` の場合）
- `covers/frontcover_light_{size}_cmyk.pdf` - 印刷用表紙（`targets: print_pdf` の場合）
- `covers/backcover_light_{size}_rgb.pdf` - PDF用裏表紙（`targets: pdf` の場合）
- `covers/backcover_light_{size}_cmyk.pdf` - 印刷用裏表紙（`targets: print_pdf` の場合）
- `covers/cover_light.jpg` - EPUB用表紙画像（`targets: epub` の場合）

`{size}` は `book.yml` の `page_size` 設定値（`a4` / `b5` / `a5`）から決定されます。

**targets設定による生成制御:**
指定されたtargetsに応じて、それぞれの形式のカバーを生成します：

- `targets: pdf` → RGB系PDFファイルのみ生成
- `targets: print_pdf` → CMYK系PDFファイルのみ生成  
- `targets: epub` → EPUB用JPEGファイルのみ生成
- `targets: pdf, epub` → RGB系PDF + EPUB用JPEGを生成
- `targets: pdf, print_pdf, epub` → 全てのファイルを生成

**設定の組み合わせ:**
```yaml
output:
  cover: light    # テーマ指定
  targets: pdf, print_pdf, epub  # 生成形式
```

#### 1.2 `output.cover: "dark"`

**生成されるファイル（ビルド対象サイズのみ）:**
- `covers/frontcover_dark_{size}_rgb.pdf` - PDF用表紙（`targets: pdf` の場合）
- `covers/frontcover_dark_{size}_cmyk.pdf` - 印刷用表紙（`targets: print_pdf` の場合）
- `covers/backcover_dark_{size}_rgb.pdf` - PDF用裏表紙（`targets: pdf` の場合）
- `covers/backcover_dark_{size}_cmyk.pdf` - 印刷用裏表紙（`targets: print_pdf` の場合）
- `covers/cover_dark.jpg` - EPUB用表紙画像（`targets: epub` の場合）

#### 1.3 `output.cover: "myawesome"` （カスタム画像）

**カスタム画像名について:**
- `myawesome` は例であり、`myspecial`、`mydesign` など任意の名前が使用可能
- 画像名はファイル名と一致させる必要あり
- 命名規則: 小文字英数字とアンダースコアのみ使用可（`/\A[a-z0-9_]+\z/`）
- `light`、`dark` との重複不可

**前提条件:**
著者が以下のPNGファイルを `covers/` ディレクトリに配置:
- `covers/frontcover_{theme}.png` - カスタム表紙画像（高解像度PNG）
- `covers/backcover_{theme}.png` - カスタム裏表紙画像（高解像度PNG）

**例:**
- 画像名 `myspecial` の場合: `covers/frontcover_myspecial.png`, `covers/backcover_myspecial.png`
- 画像名 `mydesign` の場合: `covers/frontcover_mydesign.png`, `covers/backcover_mydesign.png`

**自動生成されるファイル（ビルド対象サイズのみ）:**
- `covers/frontcover_myawesome_{size}_rgb.pdf` - PDF用表紙（`targets: pdf` の場合）
- `covers/frontcover_myawesome_{size}_cmyk.pdf` - 印刷用表紙（`targets: print_pdf` の場合）
- `covers/backcover_myawesome_{size}_rgb.pdf` - PDF用裏表紙（`targets: pdf` の場合）
- `covers/backcover_myawesome_{size}_cmyk.pdf` - 印刷用裏表紙（`targets: print_pdf` の場合）
- `covers/cover_myawesome.jpg` - EPUB用表紙画像（`targets: epub` の場合）

**変換プロセス:**
1. 著者が用意したPNGファイルを検出
2. `book.yml` の `page_size` に合わせてリサイズ
3. RGB/CMYKカラースペースでPDFに変換
4. EPUB用に1600×2560 JPEGに変換（Kindle/kobo/Apple Books 推奨解像度に準拠）

---

### 2. 自動生成のタイミング

#### 2.1 `vs build` 実行時

**PDFビルドの場合:**
1. `book.yml` の `page_size` を検出（a4 / b5 / a5）
2. `output.cover` 設定値を読み取り
3. 必要なカバーPDFが存在するか確認
4. 存在しない場合、自動生成を実行
5. 生成されたカバーをPDF結合処理に使用

**EPUBビルドの場合:**
1. `output.cover` 設定値を読み取り
2. 対応する `cover_{theme}.jpg` が存在するか確認
3. 存在しない場合、自動生成を実行
4. EPUBに埋め込む

#### 2.2 日時比較による最適化

再生成の要否は以下の順序で判定します：

1. 出力ファイルが存在しない → 生成
2. `book.yml` の更新日時が出力より新しい → 再生成
3. 上記いずれにも該当しない → スキップ

---

### 3. カスタム画像対応

#### 3.1 カスタム画像の使用方法

カスタム画像を使用するには、著者が以下の手順でPNGファイルを準備します：

**ステップ1: 画像名の決定**
- 任意の名前を設定可能: `myspecial`、`mydesign`、`custom2024` など
- 小文字英数字とアンダースコアのみ使用可（正規表現: `/\A[a-z0-9_]+\z/`）
- ハイフン・スペース・大文字は使用不可
- 既存の `light`、`dark` と重複しないようにする

**ステップ2: PNGファイルの準備**
- 高解像度の表紙画像: `covers/frontcover_{theme}.png`
- 高解像度の裏表紙画像: `covers/backcover_{theme}.png`
- 推奨解像度: 350dpi以上
- 推奨サイズ: 各ページサイズの最大寸法以上

**ステップ3: book.ymlでの設定**
```yaml
output:
  cover: myspecial  # 自由に決めたテーマ名を指定
```

**ステップ4: 自動変換**
- `vs build` 実行時に自動的に各形式に変換
- 必要なサイズ・フォーマットが存在しない場合のみ生成

#### 3.2 PNGファイルの要件

**解像度:**
- 最小: 300dpi
- 推奨: 350dpi以上
- 用途: 印刷品質を確保するため

**カラースペース:**
- RGB: PDF/EPUB用に推奨
- CMYK: 印刷用に推奨（RGBから自動変換も可能）

**ファイル形式:**
- PNGのみ対応
- PNGを採用している理由: 可逆圧縮による品質劣化なし、透明背景のサポート（PDF変換時に白色背景に変換）
- 透明背景: サポート（PDF変換時に白色背景に変換）

**解像度要件:**
- **推奨解像度**: 350dpi以上（現在の `frontcover_master.png` は 350×350dpi）
- **最小解像度**: 300dpi以上
- **A4サイズ相当**: 2894×4092px（350dpi時）
- **印刷サイズ**: 8.27×11.69インチ（A4）

#### 3.3 カスタム画像の検出とフォールバック

**検出順序:**
1. `covers/frontcover_{theme}.png` の存在確認
2. `covers/backcover_{theme}.png` の存在確認
3. 両方存在しない場合はエラー

**エラーハンドリング:**
- PNGファイルが見つからない場合: エラーメッセージを表示しビルドを中断
- ファイル形式がPNGでない場合: エラーメッセージを表示しビルドを中断
- 解像度が低い場合: 警告を表示し処理は続行

**エラーメッセージ例:**
```
❌ カスタム画像 'myspecial' のPNGファイルが見つかりません
   欠落ファイル: covers/frontcover_myspecial.png
   covers/ ディレクトリに配置してください
   対応形式: PNGのみ

⚠️ カスタム画像 'myspecial' の解像度が不足しています
   現在: 250dpi（推奨: 350dpi以上、最小: 300dpi以上）
   ビルドは続行しますが、印刷品質が低下する可能性があります
```

---

### 4. 生成プロセス

#### 4.1 標準テーマ（light/dark）の変換

1. **SVG生成**: `generate_{theme}_frontcover_svg()` / `generate_{theme}_backcover_svg()`
2. **一時PNG変換**: SVG → 高解像度PNG（350dpi）
3. **PDF生成**: PNG → 対象サイズPDF（RGB/CMYK）
4. **EPUB用JPEG**: PNG → 1600×2560 JPEG

#### 4.2 カスタム画像（PNG）の変換

1. **PNG検出**: `covers/frontcover_{theme}.png` / `covers/backcover_{theme}.png`
2. **解像度確認**: 300dpi以上であることを検証（300dpi未満は警告のみ）
3. **PDF生成**: PNG → 対象サイズPDF（RGB/CMYK）
4. **EPUB用JPEG**: PNG → 1600×2560 JPEG

#### 4.3 使用ツール

- **SVG→PNG**: `rsvg-convert` または `inkscape`
- **PNG→PDF**: `convert` (ImageMagick)
- **PNG→JPEG**: `convert` (ImageMagick)
- **CMYK変換**: ImageMagickのカラープロファイル

---

### 5. 設定例

#### 5.1 基本設定

```yaml
output:
  cover: light  # light, dark, またはカスタム画像名
  targets: pdf, epub

pdf:
  combined: true   # 表紙と本文を結合して出力
  compress: false  # PDF圧縮

epub:
  embed: true      # カバー画像をEPUBに埋め込む
```

#### 5.2 カスタム画像設定

```yaml
output:
  cover: myspecial  # 任意のカスタム画像名を指定
  targets: pdf, epub

pdf:
  combined: true
  compress: false

epub:
  embed: true
```

**他のテーマ名の例:**
```yaml
# 例1: mydesign
output:
  cover: mydesign

# 例2: custom2024
output:
  cover: custom2024

# 例3: publisher_x
output:
  cover: publisher_x
```

**必要なファイル（myspecial の場合）:**
- `covers/frontcover_myspecial.png` - カスタム表紙画像
- `covers/backcover_myspecial.png` - カスタム裏表紙画像

---

### 6. エラーハンドリング

#### 6.1 カスタム画像のPNGファイル未検出

- `covers/frontcover_{theme}.png` または `covers/backcover_{theme}.png` が見つからない場合
- エラーメッセージを表示しビルドを中断
- `Common.log_error("カスタム画像 '#{theme}' のPNGファイルが見つかりません: #{missing_file}")`

#### 6.2 テーマ名の判定フロー

テーマ名の判定は以下の順序で行います：

1. `light` または `dark` → 標準テーマとして処理
2. それ以外 → カスタム画像テーマとして扱い、対応するPNGの存在を確認
3. カスタムPNGが存在しない場合 → エラーを出力しビルドを中断

> **注意**: 未定義テーマへの自動フォールバック（`light` への置き換え）は行いません。
> 意図しないテーマ名の場合にサイレントで処理が続行されることを防ぐためです。

#### 6.3 ツール未インストール

- 必要な変換ツールが見つからない場合
- エラーメッセージを表示し、処理を中断
- インストールガイドを提示

#### 6.4 生成失敗

- SVG生成やPDF変換が失敗した場合
- 詳細なエラーログを出力
- 既存のカバー（あれば）を使用してビルド続行

---

### 7. パフォーマンス最適化

#### 7.1 キャッシュ機構

- 生成済みカバーのキャッシュ管理
- `book.yml` の変更検出（更新日時ベース）
- 変更があった場合のみ再生成

---

### 8. 設定構造の変更

#### 8.1 PDFカバー設定の構造変更

##### 8.1.1 階層構造の簡素化

**旧構造（廃止）:**
```yaml
pdf:
  cover:
    enabled: true        # true で front/back を結合、false で除外
```

**新構造:**
```yaml
pdf:
  combined: true        # 表紙と本文を結合して出力
  # combined: false     # 表紙なしで本文のみ出力
```

##### 8.1.2 変更の理由

- 階層が浅くなり直感的に理解できる
- `output.cover` がメイン設定になるため、`pdf.combined` は補助設定としてシンプルに
- 他のPDF設定（`compress`）と同じ階層構造に統一

##### 8.1.3 影響範囲

**修正が必要なコード:**
- `lib/vivlio/starter/cli/build/pdf_merger.rb`
  - `cover_enhanced_files` メソッドでの設定参照
  - `cfg.output&.pdf&.cover&.enabled` → `cfg.output&.pdf&.combined`

#### 8.2 EPUBカバー設定の構造変更

##### 8.2.1 階層構造の簡素化

**旧構造（廃止）:**
```yaml
epub:
  cover:
    embed: true              # 表紙画像を EPUB に埋め込むか
    image: cover.jpg         # EPUBカバー画像
```

**新構造:**
```yaml
epub:
  embed: true               # カバー画像を EPUB に埋め込む
  # embed: false            # カバー画像を埋め込まない
```

##### 8.2.2 変更の理由

- `output.cover` からカバー画像名が自動生成されるため `image` キーが不要に
- 階層が浅くなり直感的に理解できる

**カバー画像の自動生成:**
- `output.cover: light` → `cover_light.jpg` を自動生成
- `output.cover: myawesome` → `cover_myawesome.jpg` を自動生成

##### 8.2.3 影響範囲

**修正が必要なコード:**
- `lib/vivlio/starter/cli/build/epub_builder.rb`
  - `build_cover_config_line` メソッドでの設定参照
  - `config.output&.epub&.cover&.embed` → `config.output&.epub&.embed`
  - `config.output&.epub&.cover&.image` の削除（自動生成に置き換え）

#### 8.3 PDF圧縮設定の構造変更

##### 8.3.1 階層構造の簡素化

**旧構造（廃止）:**
```yaml
pdf:
  compress:
    enabled: false         # 自動圧縮を有効にするか
    suffix: '_compressed'  # 圧縮ファイル名のサフィックス
```

**新構造:**
```yaml
pdf:
  compress: false         # 圧縮を有効にするか
  # compress: true        # 圧縮を有効にする
```

##### 8.3.2 変更の理由

- サフィックスは `_compressed` で固定（ユーザーによるカスタマイズ不要）
- 他のPDF設定（`combined`）と同じ階層構造に統一

**圧縮ファイル名:**
- `compress: true` の場合 → `元のファイル名_compressed.pdf` を自動生成

##### 8.3.3 廃止される設定

- `pdf.compress.enabled` → `pdf.compress` に統合
- `pdf.compress.suffix` → `_compressed` で固定（変更不可）

##### 8.3.4 影響範囲

**修正が必要なコード:**
- `lib/vivlio/starter/cli/build/` 関連ファイル
  - `cfg.output&.pdf&.compress&.enabled` → `cfg.output&.pdf&.compress`
  - サフィックスの参照: 固定値 `_compressed` を使用

#### 8.4 Common::Config 読み込み処理の変更

##### 8.4.1 設定構造の変更による影響

```yaml
# 旧構造（廃止）
output:
  pdf:
    cover:
      enabled: true
      front: "frontcover_rgb.pdf"
      back: backcover_rgb.pdf
  epub:
    cover:
      embed: true
      image: cover.jpg

# 新構造
output:
  cover: light  # メイン設定

pdf:
  combined: true    # カバー結合
  compress: false   # PDF圧縮

epub:
  embed: true       # EPUB埋め込み
```

##### 8.4.2 Common::Config の修正箇所

**設定キーの変更:**
```ruby
# 修正前
cfg.output&.pdf&.cover&.enabled
cfg.output&.pdf&.cover&.front
cfg.output&.epub&.cover&.embed
cfg.output&.epub&.cover&.image

# 修正後
cfg.output&.cover          # メイン設定
cfg.output&.pdf&.combined  # カバー結合
cfg.output&.pdf&.compress  # PDF圧縮
cfg.output&.epub&.embed    # EPUB埋め込み
```

**Dataオブジェクトへのアクセス:**
```ruby
# Common::CONFIG は Data オブジェクト
# 推奨されるドット記法でのアクセス

theme = Common::CONFIG.output&.cover        # output.cover 設定
combined = Common::CONFIG.pdf&.combined     # pdf.combined 設定
compress = Common::CONFIG.pdf&.compress     # pdf.compress 設定
embed = Common::CONFIG.epub&.embed           # epub.embed 設定
```

> **注意**: Dataオブジェクトのプロパティアクセスでは、`nil`（キー未設定）と `false`（明示的に無効化）を区別せず、どちらも `nil` として扱われます。
> `true` の値を持つ場合のみ `true` として扱われます。

##### 8.4.3 影響を受けるファイル

**修正が必要なファイル:**
- `lib/vivlio/starter/common/config.rb` - 設定読み込みクラス
- `lib/vivlio/starter/cli/build/pdf_merger.rb` - PDFマージャー
- `lib/vivlio/starter/cli/build/epub_builder.rb` - EPUBビルダー
- `lib/vivlio/starter/cli/create.rb` - カバー生成コマンド

**テストファイルの更新:**
- `test/common/config_test.rb` - 設定読み込みテスト
- `test/build/pdf_merger_test.rb` - PDFマージャーテスト
- `test/build/epub_builder_test.rb` - EPUBビルダーテスト

#### 8.5 実装詳細

##### 8.5.1 設定バリデーション

```ruby
def validate_cover_settings
  theme = cfg.output&.cover

  if theme.nil?
    Common.log_error("output.cover 設定が見つかりません")
    return false
  end

  # 標準テーマはそのまま通す
  return true if %w[light dark].include?(theme)

  # テーマ名の命名規則チェック（英小文字・数字・アンダースコアのみ）
  unless theme.match?(/\A[a-z0-9_]+\z/)
    Common.log_error("テーマ名 '#{theme}' は無効な形式です")
    return false
  end

  # カスタムテーマ：表紙・裏表紙のPNGが両方存在するか確認
  front = File.join(covers_dir, "frontcover_#{theme}.png")
  back  = File.join(covers_dir, "backcover_#{theme}.png")

  if File.exist?(front) && File.exist?(back)
    true
  else
    Common.log_error("カスタム画像 '#{theme}' のPNGファイルが見つかりません")
    false
  end
end
```

##### 8.5.2 再生成判定

```ruby
def should_regenerate_cover?(theme, size, format)
  output_file = "frontcover_#{theme}_#{size}_#{format}.pdf"
  output_path = File.join(covers_dir, output_file)

  return true unless File.exist?(output_path)

  book_yml_path = File.join(project_root, "book.yml")
  File.mtime(book_yml_path) > File.mtime(output_path)
end
```

##### 8.5.3 PDFマージャーの修正

```ruby
# 新しい設定構造に対応
if cfg.output&.cover && cfg.output&.pdf&.combined
  cover_setting = build_cover_setting(cfg.output.cover)
  files.unshift(cover_setting)
end
```

##### 8.5.4 EPUBビルダーの修正

```ruby
# 新しい設定構造に対応
if config.output&.cover && config.output&.epub&.embed
  return build_cover_config_line(config, esc)
end
```

##### 8.5.5 内部コマンドについて

カバー生成は `vs build` 実行時に自動的に行われます。
利用者が直接コマンドを実行する必要はありません。

---

### 9. 実装計画

#### Phase 1: 基本機能
- [ ] `output.cover` 設定の読み取り
- [ ] light/dark テーマの自動生成
- [ ] PDF/EPUB用変換処理

#### Phase 2: カスタム画像
- [ ] カスタム画像検出機能
- [ ] PNGファイル読み込みと検証
- [ ] 画像変換とエラーハンドリング


---

### 10. テスト計画

#### 10.1 単体テスト

```ruby
# test/cover_test.rb
class CoverTest < Minitest::Test
  def test_light_theme_generation
    # lightテーマ指定でカバー生成
    assert CoverCommands.generate('light', 'a5')
    assert File.exist?("covers/frontcover_light_a5_rgb.pdf")
  end

  def test_custom_theme_valid
    # PNGが存在する場合はtrueを返す
    assert CoverCommands.valid_theme?('myspecial')
    # カスタムテーマでカバー生成
    assert CoverCommands.generate('myspecial', 'a5')
    assert File.exist?("covers/frontcover_myspecial_a5_rgb.pdf")
  end

  def test_invalid_theme_name_format
    # 不正な命名（ハイフン・大文字）はエラー
    refute CoverCommands.valid_theme_name?('My-Theme')
    refute CoverCommands.valid_theme_name?('my theme')
    refute CoverCommands.valid_theme_name?('MyTheme')
  end

  def test_reserved_theme_names
    # light/darkは予約語として使用不可
    refute CoverCommands.valid_theme_name?('light')
    refute CoverCommands.valid_theme_name?('dark')
  end

  def test_custom_theme_missing_files
    # PNGファイルが存在しない場合はfalse
    refute CoverCommands.valid_theme?('nonexistent')
  end

  def test_valid_theme_names
    # 有効な命名規則
    assert CoverCommands.valid_theme_name?('my_light')
    assert CoverCommands.valid_theme_name?('custom2024')
    assert CoverCommands.valid_theme_name?('publisher_x')
    assert CoverCommands.valid_theme_name?('a1_b2_c3')
  end
end
```

#### 10.2 結合テスト
- `vs build` との連携
- 複数ターゲット（PDF/EPUB）での動作
- エラーシナリオ（PNG未配置、ツール未インストール等）
- 日時比較によるスキップ動作の確認

---

## まとめ

この仕様により：
- **設定一つで自動生成**: `output.cover: light` だけで必要なカバーが自動生成
- **画像柔軟性**: light/darkだけでなくカスタム画像も対応
- **最適化**: ソースファイルと `book.yml` の日時比較で無駄な再生成を防止
- **シンプルな構造**: 2階層設定で直感的に理解できる
- **安全なエラー処理**: 未定義テーマへのサイレントフォールバックなし

ユーザーはカバー生成についてほとんど意識することなく、`book.yml` の設定値だけで適切なカバーを得られるようになります。
