# リンク・画像の自動検証 実装仕様書

**対象バージョン**: Vivlio Starter v0.38.0（予定）
**作成日**: 2026-04-09
**優先度**: High

---

## 1. 概要

`vs build` 実行時に、Markdown 原稿内のリンクと画像パスを自動検証し、問題があれば警告を表示する機能。PDF 出力後に壊れたリンクや欠落した画像に気づく手戻りを防ぐ。

### 1.1 解決する課題

- 存在しない画像パスを参照していても、現状はプレースホルダーに置換されるだけで見落としやすい
- 外部 URL のリンク切れ（404 等）はビルド時に一切検出されない
- 裸 URL（Markdown リンク記法でない直書き URL）の到達性も未検証

### 1.2 設計方針

- **ビルドを止めない** — 検証結果は警告として報告し、ビルド自体は続行する
- **既存処理との統合** — 画像の存在チェックは `ImagePathNormalizer` が既に実施しているため、その結果を集約する
- **外部 URL チェックはオプション** — ネットワーク依存のためデフォルト無効。オプションで有効化する

---

## 2. 検証対象

### 2.1 画像パス（ローカルファイル）

Markdown 内の画像記法を検証する。

```markdown
![代替テキスト](foo.png)
![代替テキスト](bar.webp){width=50% align=right}
![](images/01-quickstart/screenshot.webp)
```

**検証内容:**

| チェック項目 | 説明 |
|---|---|
| ファイル存在 | 正規化後のパス（`images/<章>/` 配下）にファイルが存在するか |
| 拡張子変換後の存在 | `.png` / `.jpg` → `.webp` 変換後のパスに存在するか |
| SVG の直接参照 | `.svg` ファイルが存在するか |

**パス正規化ルール**（既存の `ImagePathNormalizer` と同一）:

1. `images/` で始まるパスはそのまま使用
2. 相対パス（例: `foo.png`）は `images/<章ディレクトリ>/foo.png` に正規化
3. `.png` / `.jpg` / `.jpeg` は `.webp` に変換して存在確認

**除外対象:**

- `https://` / `http://` で始まる外部画像 URL
- `data:` URI（プレースホルダー等）
- コードブロック（`` ``` `` 〜 `` ``` ``）内の画像記法

### 2.2 Markdown リンク（外部 URL）

```markdown
[テキスト](https://example.com/page)
[参考](http://example.org/doc.pdf)
```

**検証内容:**

| チェック項目 | 説明 |
|---|---|
| URL 形式 | `https://` または `http://` で始まる有効な URL 形式か |
| HTTP 到達性 | HEAD リクエストを送信し、レスポンスステータスを確認（オプション） |

**HTTP 到達性チェックの判定基準:**

| ステータス | 判定 |
|---|---|
| 2xx | OK |
| 3xx | OK（リダイレクト先は追跡しない） |
| 4xx | 警告（リンク切れの可能性） |
| 5xx | 警告（サーバーエラー） |
| タイムアウト | 警告（到達不能） |
| DNS 解決失敗 | 警告（ホスト名不正） |

### 2.3 裸 URL（ベアリンク）

Markdown リンク記法を使わずに本文中に直接記述された URL。

```markdown
詳しくは https://foobar.com/hoge?fuga=piyo を参照してください。
```

**検証内容:**

| チェック項目 | 説明 |
|---|---|
| URL 形式 | 有効な URL 形式か |
| HTTP 到達性 | HEAD リクエストによるステータス確認（オプション） |
| リンク記法の推奨 | 裸 URL が検出された場合、`[テキスト](URL)` 記法の使用を提案する警告を出す |

**裸 URL の検出パターン:**

```
(?<!\[.*\]\()https?://[^\s)\]>]+
```

ただし以下は除外:
- 脚注定義行（`[^urlN]: https://...`）内の URL
- コードブロック内
- インラインコード内

### 2.4 内部相互参照（将来拡張）

現時点ではスコープ外とする。`[テキスト](#id)` 形式の内部リンクの検証は将来バージョンで検討。

---

## 3. ビルドパイプラインへの統合

### 3.1 実行タイミング

**Step 3（Markdown 前処理）の中で実行する。**

```
Step 0: クリーンアップ
Step 1: 画像最適化（WebP 変換）
Step 2: テーマ画像準備・CSS 更新
Step 3: Markdown 前処理 ← ★ ここで検証
  3a. フロントマター生成
  3b. 画像パス正規化（既存の ImagePathNormalizer）
  3c. リンク・画像検証 ← ★ 新規追加
  3d. コードインクルード展開
  3e. リンク脚注化
  …
Step 4: 索引スキャン
Step 5: HTML 変換
…
```

**理由:**

- 画像パス正規化（3b）の直後に実行することで、正規化済みのパスに対して正確に存在チェックできる
- HTML 変換（Step 5）の前に実行するため、Markdown の生テキストをパースできる
- 外部 URL チェック（オプション有効時）は全ファイルの 3c を処理後にまとめてバッチ実行する

### 3.2 処理フロー

```
[各 Markdown ファイル]
    │
    ├─ 画像パス収集 ──→ ローカル画像の存在チェック（即時）
    │                    → 結果を ValidationReport に蓄積
    │
    ├─ リンク URL 収集 ──→ URL 形式チェック（即時）
    │                      → URL リストを蓄積
    │
    └─ 裸 URL 収集 ──→ URL 形式チェック（即時）
                        → URL リストを蓄積

[全ファイル処理後]
    │
    ├─ (--verify-links 有効時) HTTP 到達性チェック（バッチ）
    │   → 並列リクエスト（最大同時接続数: 5）
    │   → タイムアウト: 10 秒/リクエスト
    │
    └─ ValidationReport をサマリー表示
```

---

## 4. モジュール設計

### 4.1 新規ファイル

```
lib/vivlio/starter/cli/pre_process/link_image_validator.rb
```

### 4.2 モジュール構造

```ruby
module Vivlio::Starter::CLI::PreProcessCommands
  module LinkImageValidator
    module_function

    # Markdown コンテンツから画像・リンク・裸URLを抽出し検証する
    # @param content [String] Markdown テキスト（画像パス正規化済み）
    # @param filename [String] 対象ファイル名（警告表示用）
    # @return [ValidationReport] 検証結果
    def validate(content, filename)
    end

    # 蓄積された外部 URL に対して HTTP 到達性チェックを実行する
    # @param urls [Array<UrlEntry>] URL エントリのリスト
    # @return [Array<UrlCheckResult>] チェック結果
    def check_urls(urls)
    end

    # 検証結果のサマリーを表示する
    # @param reports [Array<ValidationReport>] 各ファイルの検証結果
    def print_summary(reports)
    end
  end
end
```

### 4.3 データ構造

```ruby
# 画像検証の単一結果
ImageIssue = Data.define(
  :filename,      # 原稿ファイル名（例: "01-quickstart.md"）
  :line_number,   # 行番号
  :image_path,    # 参照している画像パス
  :resolved_path, # 正規化後のパス
  :issue_type     # :missing（存在しない）
)

# URL 検証の単一結果
LinkIssue = Data.define(
  :filename,      # 原稿ファイル名
  :line_number,   # 行番号
  :url,           # URL 文字列
  :issue_type,    # :invalid_format / :unreachable / :bare_url
  :status_code,   # HTTP ステータスコード（nil = チェック未実施）
  :message        # 詳細メッセージ
)

# ファイル単位の検証結果
ValidationReport = Data.define(
  :filename,       # 対象ファイル名
  :image_issues,   # Array<ImageIssue>
  :link_issues     # Array<LinkIssue>
)
```

---

## 5. MarkdownPreprocessor への組み込み

### 5.1 パイプラインへの追加

`MarkdownPreprocessor#run` メソッドのパイプラインに `validate_links_and_images!` ステップを追加する。

```ruby
def run
  apply_frontmatter!
  strip_html_comments!
  process_data_streams!
  normalize_image_paths!
  validate_links_and_images!    # ← 新規追加
  process_code_includes!
  normalize_html_block_boundaries!
  escape_inline_code_html!
  transform_text_right_inlines!
  transform_book_cards!
  transform_table_rotations!
  transform_links!
  expose_container_footnotes!
  write_output!
end
```

### 5.2 ImagePathNormalizer との連携

`ImagePathNormalizer.fix_image_paths` は既に存在しない画像を検出し `Common.log_warn` で警告を出力している。この情報を `ValidationReport` にも集約するため、以下のいずれかの方法で連携する。

**方式 A（推奨）: validate ステップで独立に再スキャン**

- `normalize_image_paths!` 後のコンテンツに対して、画像記法をパースし存在チェック
- `ImagePathNormalizer` がプレースホルダーに置換済みの箇所は `data:` URI になっているため、それを検出して issue に記録
- 既存の `ImagePathNormalizer` を変更しない

**方式 B: ImagePathNormalizer が issue リストを返す**

- `fix_image_paths` の戻り値を `[content, issues]` に変更
- 既存コードへの影響が大きいため、方式 A を推奨

---

## 6. 出力フォーマット

### 6.1 ファイルごとの警告（処理中に即時表示）

```
⚠️  01-quickstart.md:15 - 画像 'foo.png' が見つかりません
                          画像の場所: images/01-quickstart/foo.webp
⚠️  01-quickstart.md:42 - 裸 URL を検出しました（リンク記法 [テキスト](URL) の使用を推奨します）
                          URL: https://foobar.com/hoge?fuga=piyo
```

### 6.2 検証サマリー（全ファイル処理後にまとめて表示）

```
🔍 リンク・画像検証の結果:
   画像: 2 件の問題（存在しない画像: 2）
   リンク: 1 件の問題（裸 URL: 1）
   外部URL到達性チェック: スキップ（--verify-links で有効化）
```

`--verify-links` 有効時:

```
🔍 リンク・画像検証の結果:
   画像: 2 件の問題（存在しない画像: 2）
   リンク: 3 件の問題（リンク切れ: 1, 裸 URL: 2）
   外部URL: 15 件チェック → 14 OK, 1 NG
     ❌ https://example.com/deleted-page → 404 Not Found
        参照元: 12-markdown-tutorial.md:88
```

### 6.3 問題なしの場合

```
✅ リンク・画像の検証が完了しました（問題なし）
```

---

## 7. CLI オプション

### 7.1 `vs build` のオプション追加

| オプション | 説明 | デフォルト |
|---|---|---|
| `--[no]-verify` | 画像・リンクの基本検証を実行する | `true` |
| `--verify-links` | 外部 URL の HTTP 到達性チェックを実行する | `false` |

```bash
# 標準ビルド（画像存在チェック + 裸URL検出 = ON、HTTP到達性 = OFF）
vs build

# 外部URLの到達性もチェック
vs build --verify-links

# 検証を完全にスキップ（高速ビルド）
vs build --no-verify
```

### 7.2 `book.yml` での設定

```yaml
build:
  verify:
    images: true          # 画像パスの存在チェック（デフォルト: true）
    bare_urls: true       # 裸 URL の検出と警告（デフォルト: true）
    external_links: false  # 外部 URL の HTTP 到達性チェック（デフォルト: false）
    timeout: 10           # HTTP チェックのタイムアウト秒数
    max_concurrency: 5    # HTTP チェックの最大同時接続数
```

CLI オプションが `book.yml` の設定より優先される。

### 7.3 CLI オプションと `book.yml` の対応関係

| CLI オプション | `book.yml` 相当 | 画像存在チェック | 裸 URL 検出 | 外部 URL 到達性 |
|---|---|---|---|---|
| （なし＝デフォルト） | `images: true`, `bare_urls: true`, `external_links: false` | ✅ ON | ✅ ON | ❌ OFF |
| `--verify-links` | `external_links: true` | ✅ ON | ✅ ON | ✅ ON |
| `--no-verify` | `images: false`, `bare_urls: false`, `external_links: false` | ❌ OFF | ❌ OFF | ❌ OFF |

**設計意図:**

- **CLI**: 大まかに ON/OFF する（`--verify-links` で全有効化 / `--no-verify` で全無効化）
- **`book.yml`**: プロジェクト固有の恒久設定を細かく個別制御する（例: 画像チェックだけ OFF にしたい）

**優先順位**: CLI オプション > `book.yml` 設定

| 状況 | 結果 |
|---|---|
| `book.yml: external_links: true` + CLI オプションなし | HTTP チェック実行 |
| `book.yml: external_links: true` + `--no-verify` | 全チェックスキップ |
| `book.yml: external_links: false` + `--verify-links` | HTTP チェック実行 |
| `book.yml: images: false` + CLI オプションなし | 画像チェックのみスキップ |

---

## 8. エッジケース

### 8.1 画像

| ケース | 挙動 |
|---|---|
| `![](foo.png)` で `foo.webp` のみ存在 | OK（拡張子変換で解決） |
| `![](foo.png)` で `foo.png` も `foo.webp` も不在 | 警告 |
| `![](https://example.com/img.png)` | 外部画像のためスキップ（`--verify-links` 有効時はチェック） |
| VFM 属性付き `![](bar.webp){width=50%}` | `{...}` を除去してパス部分のみ検証 |
| コードブロック内の `![](...)` | スキップ |
| インラインコード内の `` `![](...)` `` | スキップ |

### 8.2 リンク

| ケース | 挙動 |
|---|---|
| `[text](https://example.com)` | URL 形式チェック（HTTP チェックはオプション） |
| `[text](#section-id)` | 内部リンク → 現時点ではスキップ |
| `[text](./other.md)` | 相対リンク → ファイル存在チェック |
| 脚注定義 `[^url1]: https://...` | 脚注化後のため検証不要（元のリンクで検証済み） |
| 同一 URL の重複 | HTTP チェック時は URL を重複排除してリクエストを最小化 |

### 8.3 裸 URL

| ケース | 挙動 |
|---|---|
| `https://example.com` が本文中に直書き | 警告 + リンク記法の推奨 |
| 脚注定義行の URL | 除外（裸 URL 警告の対象外） |
| コードブロック内の URL | 除外 |
| HTML コメント内の URL | 除外（`strip_html_comments!` で先に削除済み） |

---

## 9. パフォーマンス考慮

### 9.1 ローカルチェック

- ファイル存在チェックは `File.exist?` のみ。十分高速
- 各ファイルの前処理パイプライン内で逐次実行（既存の並列処理に組み込まれる）

### 9.2 外部 URL チェック

- HEAD リクエストのみ使用（レスポンスボディを取得しない）
- HEAD が 405 Method Not Allowed の場合は GET にフォールバック（Range: bytes=0-0）
- URL の重複排除により不要なリクエストを削減
- 最大同時接続数（デフォルト 5）で並列実行
- タイムアウト（デフォルト 10 秒）で長時間ブロックを防止
- Ruby 標準ライブラリ `net/http` を使用（外部 gem 不要）

---

## 10. テスト方針

### 10.1 ユニットテスト

| テスト対象 | 内容 |
|---|---|
| 画像パス抽出 | Markdown から画像記法を正しくパースできる |
| コードブロック除外 | コードブロック内の画像・リンクは無視される |
| VFM 属性の除去 | `{width=50%}` 等がパス解析に影響しない |
| 裸 URL 検出 | 本文中の裸 URL を正しく抽出できる |
| 脚注行の除外 | `[^urlN]:` 行の URL は裸 URL 警告の対象外 |
| ValidationReport の集約 | 複数ファイルの結果が正しくマージされる |

### 10.2 統合テスト

| テスト対象 | 内容 |
|---|---|
| `vs build` でのサマリー出力 | 問題がある場合にサマリーが表示される |
| `--no-verify` | 検証がスキップされる |
| `--verify-links` | HTTP チェックが実行される（モックサーバー使用） |
| 問題なし時の出力 | 「問題なし」メッセージが表示される |

---

## 11. 実装ステップ

### Phase 1: ローカル検証（最小実装）

1. `LinkImageValidator` モジュールを作成
2. Markdown から画像パス・リンク URL・裸 URL を抽出するパーサーを実装
3. 画像ファイルの存在チェックを実装
4. 裸 URL の検出と警告を実装
5. `MarkdownPreprocessor` のパイプラインに組み込み
6. 検証サマリーの表示を実装
7. ユニットテストを作成

### Phase 2: 外部 URL チェック

1. `net/http` を使った HEAD リクエストチェックを実装
2. 並列実行（`Thread` ベース）を実装
3. `--verify-links` オプションを `BuildCommand` に追加
4. `book.yml` の `build.verify` 設定を読み込む処理を追加
5. 統合テストを作成

---

## 12. 将来拡張

- **内部相互参照の検証**: `[テキスト](#id)` のリンク先が存在するか確認
- **画像サイズの警告**: 極端に大きい画像（例: 10MB 超）への警告
- **外部画像のキャッシュ**: HTTP チェック結果をキャッシュし、再ビルド時のリクエストを削減
- **`vs verify` コマンド**: ビルドとは独立にリンク・画像を検証する単体コマンド
