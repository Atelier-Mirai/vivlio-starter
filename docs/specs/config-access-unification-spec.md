# Common::CONFIG アクセス記法統一 仕様（Data オブジェクト統一リファクタリング）

対象: `lib/` 全域（＋テストの設定偽装方法） / 策定日: 2026-07-02 / ステータス: 提案

## 背景 / 目的

`config/book.yml` は本プロジェクトの中核設定であり、`Common::CONFIG`（再帰的 Data ラッパー）
として全コマンドから参照される。Data 化の際、旧コマンドとの互換のために `[]` / `dig` /
`fetch` / `deconstruct_keys` を後付けした結果、**7 種類の記法が混在する継ぎ接ぎ**になった。

本仕様は「唯一の正しい書き方」を定め、防衛的な二重アクセス・Hash/Data 両対応ブリッジ・
CONFIG を経由しない独自読み込みルートを段階的に撲滅する。

## 1. 現状調査の結果（2026-07-02 時点）

### 1.1 記法の分布（lib 配下・約 92 箇所）

| 記法 | 件数 | 例 |
|---|---:|---|
| ドット記法 | 34 | `CONFIG.book.main_title` / `CONFIG&.directories&.config` |
| dig（文字列） | 14 | `CONFIG.dig('output', 'cover')` |
| `[]`（文字列） | 14 | `CONFIG['pdf'] \|\| {}` |
| dig（シンボル） | 12 | `CONFIG.dig(:output, :targets)` |
| `respond_to?` ガード | 6 | `CONFIG.respond_to?(:legal) ? CONFIG.legal&.twemoji : nil` |
| `Common.load_config` 直接（生 Hash） | 5 | cover.rb ×4 / clean.rb ×1 |
| `[]`（シンボル） | 4 | `CONFIG[:index]` |
| `fetch` | 3 | `CONFIG.fetch('book', {})` |
| 独自 YAML 読み込み | 1 系統 | metrics/config_loader.rb（文字列キーの生 Hash） |

### 1.2 発見された問題点

1. **`[]` のメソッド漏れ（実証済み）** — `def [](key) = respond_to?(key) ? public_send(key) : nil`
   のため、`CONFIG[:to_h]` は設定 Hash 全体を、`CONFIG['inspect']` は inspect 文字列を返す。
   YAML キーが Data の予約メソッド（`with` / `hash` / `class` / `members` 等）と衝突すると静かに誤動作する。
2. **ドット記法の NoMethodError リスク** — 既定値マージは 6 セクション
   （directories / cache / commands / files / vivliostyle / vfm）のみ。`CONFIG.lint`・
   `CONFIG.spellcheck`・`CONFIG.project`・`CONFIG.book` 等（`lint.rb:80`, `lint.rb:267`,
   `build/pipeline.rb:804-805` ほか）は、**該当セクションを book.yml から削除した
   最小構成プロジェクトでクラッシュする**。ガードの有無も場所により不統一
   （`index.rb:56` は無ガード、`index_library.rb:55` は `respond_to?` ガード）。
3. **`fetch` の意味論の乖離** — Hash#fetch と異なり KeyError を出さず、
   「キーは存在するが値が nil/false」も default に落ちる。真偽値 false を保持できない。
4. **文字列/シンボルの二重防衛コード** —
   `heading_processor.rb:247`: `dig(:theme, :markers, :h3) || dig('theme', 'markers', 'h3')`（完全に冗長）、
   `css_updater.rb:382`: `cfg[:book] || cfg['book'] || {}` ＋ 全リーフで二重アクセス。
5. **Hash/Data 両対応ブリッジが 3 箇所** — `common.rb resolve_page_size`（to_h 正規化）、
   `variable_font_injector.rb config_value`（case Hash/else）、`common.rb fetch_bool`。
   セクションを引数で受け取るメソッドの型が呼び出し元によって Hash だったり Data だったりするため。
6. **CONFIG を経由しない読み込みが 2 系統** —
   (a) `cover.rb`（4 回）と `clean.rb` が `Common.load_config` で**毎回ディスクから再読込**した
   生 Hash（シンボルキー）を使用。
   (b) `metrics/config_loader.rb` は `YAML.safe_load_file` 直読みの**文字列キー** Hash。
   ページプリセット適用・既定値マージ・単位正規化のロジックが CONFIG と乖離し得る。
7. **`deconstruct_keys(nil)` の仕様逸脱** — 標準は「nil なら全体を返す」だが、
   現実装 `to_h.slice(*nil)` は空 Hash を返すため `in { **rest }` が空になる。
8. **reload 後の stale 参照** — `pdf.rb:163` 等がセクションを ivar にメモ化しており、
   `reload_configuration!` で CONFIG 定数が差し替わっても古い Data を持ち続ける。
9. **無意味なフォールバック** — `epub.rb:80` `(CONFIG['vivliostyle'] || {})` は
   既定値マージ済みセクションなので `|| {}` は到達しないデッドコード。

### 1.3 ファイル別スタイル分布（移行作業の対象一覧）

| ファイル | 現在の主なスタイル |
|---|---|
| lint.rb / lint/dict_manager.rb | ドット＋`&.[](:key)` ハイブリッド |
| pdf.rb | `['pdf']` 文字列ブラケット＋ivar メモ化 |
| epub.rb | 文字列ブラケット |
| clean.rb | dig 文字列＋load_config 直接 |
| cover.rb | **load_config 直接（生 Hash）のみ** |
| create.rb | dig シンボル＋fetch 文字列 |
| index.rb / index/*.rb | ドット＋respond_to? ガード＋`[:index]` |
| build/pipeline.rb, pdf_builder.rb, utilities.rb, backlink_dedup_orchestrator.rb | ドット・文字列ブラケット・dig 文字列の混在 |
| build/epub_builder.rb, post_process/section_wrapper.rb | dig 文字列 |
| build/pdf_merger.rb, image_optimizer.rb, nombre_stamper.rb, samovar/build_command.rb | dig シンボル（新スタイルに近い） |
| build/outline_extractor.rb | fetch 文字列 |
| post_process/heading_processor.rb | 二重 dig（シンボル‖文字列） |
| pre_process/css_updater.rb | シンボル‖文字列 二重ブラケット |
| pre_process/frontmatter_generator.rb, link_image_validator.rb, pdf/pdf_read_command.rb | dig シンボル |
| pre_process/theme_image_resolver.rb, samovar/index_command.rb | 文字列ブラケット |
| techbook/variable_font_injector.rb | 独自 config_value（Hash/Data 両対応） |
| metrics/config_loader.rb | **独自 YAML 直読み（文字列キー）** |
| common.rb（派生ヘルパー） | ドット`&.`＋dig 文字列＋dig シンボル混在 |

## 2. 正規記法の仕様（The One Way）

### 2.1 基本原則 — 「静的キーはドット、動的キーはシンボル dig」

```ruby
# ✅ 正: キーが静的に決まっているとき（原則こちら）
Common::CONFIG.book.main_title
Common::CONFIG.output.pdf.combined

# ✅ 正: キーが変数のとき（1 段は []、多段は dig — シンボルのみ）
Common::CONFIG[section]              # section は Symbol
Common::CONFIG.dig(section, key)

# ✅ 正: パターンマッチ（シンボルキーのみ）
case Common::CONFIG
in { page: { size: String => size } } then ...
end

# ❌ 禁止: 文字列キー（'book' / 'output' 等）
# ❌ 禁止: CONFIG.fetch（Phase 3 で削除）
# ❌ 禁止: CONFIG.respond_to?(:legal) ガード（既定値スキーマにより不要化）
# ❌ 禁止: CONFIG.lint&.[](:key) のような &.[] ハイブリッド
# ❌ 禁止: セクション取得時の || {} フォールバック（存在保証により不要）
# ❌ 禁止: Common.load_config の直接呼び出し（CONFIG を使う）
# ❌ 禁止: book.yml の独自 YAML 読み込み（metrics 含め CONFIG に一本化）
```

ドット記法に `&.` を書いてよいのは **Common 内の派生ヘルパーだけ**（2.5）。
各コマンドは冒頭で `Common.ensure_configured!` を通過している前提で、`&.` なしで書く。

### 2.2 既定値スキーマ（全セクションの存在保証）

ドット記法を安全にする土台として、既定値マージを現在の 6 セクションから
**book.yml が持ち得る全 16 セクション**に拡大する:

```
book, project, theme, page, typography, legal, output, vfm, build,
index_glossary, index, glossary, metrics, lint, spellcheck, pdf_read,
directories, cache, commands, files, vivliostyle
```

- 第 1 階層: 全セクションが常に Data として存在する（book.yml に無ければ既定値のみ）。
- 第 2 階層以下: コードが参照する既知キーはスキーマに列挙し、値未設定なら nil を持たせる。
  これにより `CONFIG.legal.twemoji` は常に呼べて、未設定なら nil が返る。
- スキーマは `common.rb` 内の Hash 定数（`DEFAULT_CONFIG` 等）として定義する
  （gem 同梱 YAML の読込失敗という故障モードを増やさないため）。
- book.yml にあってスキーマに無いキーは従来どおり動的に取り込む（自由拡張は維持）。
- キー名は `/\A[a-z_][a-zA-Z0-9_]*\z/` を推奨（`hardLineBreaks` は既存互換で許容）。

### 2.3 `wrap_config` の改修仕様

| メソッド | 新仕様 |
|---|---|
| `[]` | **メンバー限定**の参照に修正（メソッド漏れ排除）。生成時に member 集合を保持し、非メンバーは nil。String キーは to_sym 正規化（Phase 3 で警告→将来削除） |
| `dig` | `[]` ベースの現行チェーンを維持（`[]` の安全化を自動的に継承） |
| `fetch` | Phase 2 で deprecation 警告、Phase 3 で削除 |
| `deconstruct_keys` | `keys.nil?` なら `to_h` を返すよう修正（Ruby 標準仕様に一致） |
| 予約名検査 | Data の既存メソッド（`with` / `to_h` / `members` / `hash` / `inspect` / `dig` 等）と衝突するキーをロード時に `log_warn` |
| freeze | 維持（不変性の保証は変えない） |

### 2.4 セクションの受け渡しと保持のルール

- メソッド引数にセクションを渡すときは **Data のまま**渡す（存在保証により nil は来ない）。
- Hash が必要な境界（YAML 書き出し・外部 gem への受け渡し）でのみ、その場で `.to_h`。
- テストで設定を偽装するときは Hash を直接渡さず `Common.wrap_config({...})` で包む。
  → `resolve_page_size` の to_h 正規化、`variable_font_injector#config_value`、
  `fetch_bool` の Hash/Data 両対応は Phase 3 で削除できる。
- **セクションの長期保持（ivar メモ化）は禁止**。`reload_configuration!` で CONFIG 定数が
  差し替わるため、必要な都度 `Common::CONFIG` から辿る（1 メソッド内のローカル変数は可）。

### 2.5 Common の派生ヘルパー（`config_dir` / `pdf_combined?` 等）

- ヘルパー自体は維持する（呼び出し側の簡潔さと nil 吸収の一元化に有効）。
- CONFIG が nil のケース（プロジェクト外での `new` / `doctor` / `help`）を吸収する
  **唯一の場所**として、ヘルパー内部に限り `CONFIG&.` を許可する。
- 内部実装を正規記法へ統一する:
  `cover_theme = CONFIG.dig('output', 'cover')` → `CONFIG&.output&.cover` 等。
- 真偽値は既定値スキーマで型を保証し、`fetch_bool` は不要化する。

## 3. 移行計画

影響範囲が大きい（lib 28 ファイル・約 92 箇所＋テスト）ため 3 フェーズに分ける。
Phase 1 は挙動完全互換なので RC 前でも実施可。Phase 2 以降は **RC (2026-07-07) 後を推奨**。

### Phase 1: 基盤整備（挙動互換・回帰リスク小）

1. `wrap_config` 改修（2.3）: `[]` メンバー限定化＋String→Symbol 正規化、
   `deconstruct_keys(nil)` 修正、予約名検査。
2. 既定値スキーマ導入（2.2): `merge_hardcoded_defaults` を全セクションに拡大。
3. 設定アクセスの単体テスト新設（棚上げ中の「設定テスト」タスクと合流）:
   - 記法ごとの参照テスト（ドット / [] / dig / パターンマッチ）
   - メソッド漏れの回帰テスト（`CONFIG[:to_h]` が nil を返すこと）
   - 最小 book.yml（セクション欠落）で全セクションがドット参照可能なこと
   - reload 後の値更新

### Phase 2: 呼び出し側の一斉移行（§1.3 の表が対象一覧）

1. 文字列キー → ドット記法 or シンボル dig へ書き換え（約 31 箇所）。
2. `respond_to?` ガード・`&.[]` ハイブリッド・`|| {}` フォールバックの削除。
3. `cover.rb` / `clean.rb` の `Common.load_config` 直接呼び出しを CONFIG 参照へ。
4. `metrics/config_loader.rb` の入力を `Common::CONFIG.metrics` に変更
   （プリセット解決・しきい値正規化のロジックは維持）。
5. `heading_processor.rb` の二重 dig、`css_updater.rb` の二重ブラケットを単一化。
6. `pdf.rb` の ivar メモ化を都度参照に変更（2.4）。
7. `CONFIG.fetch` に deprecation 警告を追加。

### Phase 3: 互換層の削除

1. `fetch` 削除。`[]`/`dig` の String キー受け付けに警告を追加（→ 次のメジャーで削除）。
2. Hash/Data ブリッジ削除: `resolve_page_size` の正規化分岐、
   `variable_font_injector#config_value`、`fetch_bool`。
3. `common.rb` 冒頭のハイブリッド仕様コメント（7-16 行目）を本仕様への参照に更新。

### 検証

- 各 Phase 完了時: `rake test` / `rake test:standard`、Phase 2 以降は `rake test:layout` と
  実プロジェクトでの `vs build`（PDF / EPUB / Kindle 全ターゲット）。
- Phase 2 は §1.3 の表をチェックリストとしてファイル単位でコミットを分ける。

## 4. 本仕様の範囲外（関連タスク）

- 単位変換（Q/pt/em）の仕様書化 — 別タスク（config-core-refactor タスク 2）。
- `catalog.yml` / `page_presets.yml` / `post_replace_list.yml` のアクセス統一 —
  book.yml の統一完了後に同じ原則を適用するか判断する。
