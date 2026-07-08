# VivlioVerso 基盤整備 基本構想（第 2 部）

対象: ビルド系全域のアーキテクチャ / 策定日: 2026-07-03 /
ステータス: **構想確定・個別計画は第 3 部**

第 1 部 = [vivlioverso-build-investigation.md](vivlioverso-build-investigation.md)（現状調査）、
第 3 部 = [vivlioverso-foundation-workplans.md](vivlioverso-foundation-workplans.md)（個別改修計画 P1〜P5）。

## 0. 設計哲学

調査で特定した課題 A〜D への処方を **4 本柱**として定める。全体を貫く原則:

1. **骨格は変えない** — `pre_process → convert → post_process → build` の 4 段は
   実証済みの正しい骨格。壊れているのは骨格ではなく「段の間の契約」なので、
   契約を明示化する（書き直しではなく蒸留）。
2. **挙動不変のリファクタと機能追加を分離** — 各柱は「出力 PDF/EPUB がビット単位で
   不変」を完了条件とする移行段階を持つ（Units 一元化・CONFIG 統一で実証済みの流儀）。
   安全網は既存の `target_consistency_test`（実 6 ビルドの出力比較）。
3. **暗黙の契約を型と宣言に置き換える** — 「この正規表現がマッチする CSS で
   あること」「このステップの後に呼ぶこと」という暗黙知を、
   値オブジェクト・宣言テーブル・生成ファイルの形に固定する。
4. **著者の資産に書き込まない** — ビルドが書いてよいのは `.cache/` と最終成果物のみ。
   `contents/` `stylesheets/` `config/` は読み取り専用（CatalogUpdater 等、
   著者の代行として明示的に編集するコマンドは除く）。

```
                     V2.0 機能（小説・テーマ・直接ビルド・print_pdf 導出）
                    ┌──────────────┬──────────────┬──────────────┐
柱 3: CSS 注入層    │ 柱 1: BuildPlan 宣言化        │ 柱 4: ワークスペース分離
（テーマ差し替え可）│（ステップ表・ターゲット値対象）│（snapshot 撲滅）
                    └──────────────┴──────────────┴──────────────┘
柱 2: マスキング一元化（すべての記法処理の土台）
```

---

## 1. 柱 1: BuildPlan — ステップ列の宣言的導出（課題 A）

### 1.1 ターゲットの値オブジェクト化

CONFIG の都度解析（4 メソッド重複）を、ビルド開始時に **1 回だけ**解決する
不変値オブジェクトへ:

```ruby
# Build::Targets — output.targets の解決結果（ビルド中は不変）
Targets = Data.define(:pdf, :print_pdf, :epub, :kindle) do
  def self.resolve(config = Common::CONFIG)
    raw = PdfMerger.extract_targets(config.dig(:output, :targets))
    raw = PdfMerger.extract_targets(config.dig(:output, :pdf, :targets)) if raw.empty?
    raw = ['pdf'] if raw.empty?   # 既定
    new(pdf: raw.include?('pdf'), print_pdf: raw.include?('print_pdf'),
        epub: raw.include?('epub'), kindle: raw.include?('kindle'))
  end

  def epub_or_kindle? = epub || kindle
  def any_pdf?        = pdf || print_pdf
end
```

### 1.2 ステップ表（条件付き宣言）

5 分岐の手組みを、**1 枚の順序付き表**に置き換える。各行 =
「ラベル・実行条件・ハンドラ」。分岐は表の `if:` に吸収され、
経路の組み合わせは**表を上から評価するだけ**で一意に定まる:

```ruby
# 疑似コード（実体は第 3 部 P2）
FULL_STEPS = [
  step('clean',              -> { run_step0_clean }),
  step('optimize images',    -> { run_step1_optimize_images }),
  ...,                                                        # 共通prep（無条件）
  step('build overall pdf',  -> { ... },          if: :pdf),
  step('snapshot for epub',  -> { ... },          if: :epub_or_kindle?),
  step('backlink dedup',     -> { ... },          if: :any_pdf?),
  ...,
  step('print pdf',          -> { ... },          if: :print_pdf),
  step('generate epub',      -> { ... },          if: :epub_or_kindle?),
  step('final clean',        -> { run_final_clean })
]
```

- ステップ番号は撤去し、**安定したラベル名**をログ・計時・ドキュメントの共通語彙に
  する（「Step 13 と Step 10 が同じもの」という矛盾の根絶）。
- `:single` / `:preflight` は別テーブル（現行どおり）。将来の「直接ビルド」
  「小説モード」も**テーブルの追加**で表現でき、既存分岐に触れない。

### 1.3 実装分離

zip 手術（identifier 安定化・OPF id 修正）は `EpubBuilder` へ、print_pdf の
6 フェーズは `Build::PrintPdfBuilder`（新設）へ移し、pipeline.rb は
「表の評価と計時」だけの 200 行級に痩せる。

---

## 2. 柱 2: マスキングの一元化（課題 B）

### 2.1 唯一実装への集約

12 実装のうち**最も正しい `IndexCommands::CodeBlockStripper` の状態機械**
（可変長・入れ子・`~~~`・`include:` 対応）を共通層へ昇格し、
3 つの API に統一する:

```ruby
# CLI::Masking（新設・唯一のフェンス/インラインコード解釈）
module Masking
  # (a) 行走査: コード外の行だけを yield（行番号維持）— lint/metrics/index 系向け
  def each_prose_line(text) { |line, lineno| ... }

  # (b) 除去: コードを空行/空白化したテキストを返す — 統計・スキャン向け
  def strip_code(text)  # 現 CodeBlockStripper.strip と同一意味論

  # (c) 保護→復元: コードをプレースホルダ退避し、処理後に復元 — 変換系向け
  def protect_code(text)         # => [protected_text, spans]
  def restore_code(text, spans)  # 現 MarkdownUtils と同一意味論
end
```

- 「フェンスとは何か」の解釈（開始・終了・入れ子・`include:` 指令の除外）が
  **全コマンドで単一**になる。新記法（例: 会話文ブロック）を追加しても
  「コード内では無効」が自動で保証される。
- `guards/code_fence_check`（整合性検証）は検証器として独立を維持するが、
  判定定数（FENCE パターン）は Masking のものを参照する。

### 2.2 前処理 21 ステップへの適用

`MarkdownPreprocessor` の各 `transform_*` は「保護済みテキストを受け取る」前提に
段階移行する。最終形は run が一度 `protect_code` し、全 transform 後に
`restore_code` する **サンドイッチ構造**（各ステップの自前検出が不要になる）。
ただしコードを**見る必要がある**ステップ（コードインクルード・
インラインコードエスケープ）があるため、移行は per-step に判断する（第 3 部 P1）。

---

## 3. 柱 3: CSS 設定注入層の分離（課題 C・**VivlioVerso の核心**）

### 3.1 原理: 「書き換え」から「カスケードによる上書き」へ

CSS カスタムプロパティは**後から同名を再宣言すれば上書きされる**。
つまり `theme.css` の中の値を書き換える必要はそもそもなく、
**生成した変数定義ファイルを後段に読み込ませれば同じ効果**が得られる:

```
現在:  theme.css（書き換え）→ chapter.css（書き換え）→ custom.css
将来:  theme.css（無傷）→ chapter.css（無傷）→ .cache/vs/book-settings.css（生成）→ custom.css
                                               ↑ book.yml 由来の変数を全文生成
```

- `book-settings.css`（仮名）は **`:root { … }` と `@page { size: … }` を全文生成**
  する短いファイル。正規表現照合は不要（生成なので契約は「書く側」だけが知ればよい）。
- 読み込み順は `custom.css` の**直前**。著者の custom.css 最優先は不変。
- frontmatter の `link` 注入（`frontmatter_generator.rb:121`）に 1 エントリ足すだけで
  配線できる。既存 CSS には**一切触れない**。

### 3.2 効果

| 現在 | 移行後 |
|---|---|
| 著者が theme.css の該当行を消すと黙って設定不能 | theme.css は自由に編集・削除・差し替え可（生成ファイルが常に変数を供給） |
| ビルドごとに stylesheets/ の git diff 汚染 | stylesheets/ は不変。生成物は .cache/ |
| `--prop: 値;` 形式の暗黙契約 22+ 箇所 | 契約は「生成ファイルの変数名一覧」1 箇所（テスト可能） |
| テーマ CSS 差し替え不能 | **CSS セットを丸ごと差し替えても設定が届く** = テーマシステムの土台 |

### 3.3 書き換えが残る 2 箇所の扱い

1. **chapter.css の header import 切替**（simple ⇄ image）— `@import` は変数で
   切替不可。生成ファイル側に「ヘッダー用スタイルの実体」を移すか、
   `--header-mode` 変数化＋両 CSS 常時ロード（適用条件を変数で分岐）で解消する。
   方式は P3 実装時に決定（第 3 部に判断材料を記載）。
2. **vivliostyle.config.js の size/title 同期** — こちらは JS 設定ファイルで
   CSS カスケードの外。当面書き換えを維持し（被害が静的 CSS より小さい）、
   V2.0 の「config.js 全文生成化」（テンプレートから毎回生成）で解消する。

### 3.4 テーマシステムへの接続（V2.0 本体）

注入層が完成すると、テーマは次の 3 層構造で自然に定義できる:

```
① テーマ CSS セット（gem 同梱 themes/<name>/ or 著者の stylesheets/）
② book-settings.css（book.yml 由来の変数 — テーマ非依存の一様な受け口）
③ custom.css（著者の最終上書き）
```

小説対応（縦書き・挿絵・章扉）も「①を novel テーマに差し替え、
②の変数語彙（`--page-*` / `--font-*` / `--theme-*`）を共有する」だけで成立する。
**②の変数語彙を「公開インターフェース」として文書化・凍結する**ことが
テーマ互換性の要（第 3 部 P3 で語彙表を確定）。

---

## 4. 柱 4: ワークスペース分離（課題 D）

### 4.1 原理: 「順序で守る」から「場所で守る」へ

中間生成物をプロジェクトルートから `.cache/vs/build/` 配下へ移し、
**消費者ごとにディレクトリを分ける**:

```
.cache/vs/build/
  html/          # convert + post_process 済みの正典 HTML（dedup 前）
  pdf/           # dedup 適用済み HTML・_sections.pdf 等（PDF 系の作業場）
  epub/          # クリーン EPUB 用 HTML（html/ からコピーして加工）
  kindle/        # Kindle 用 HTML（html/ からコピーして劣化加工）
```

- dedup は `pdf/` の中だけを書き換える → EPUB スナップショット（2 系統）が
  **構造的に不要**になる。
- clean 処理は `.cache/vs/build/` を消すだけ → 成果物 PDF の `.keep` 退避ハックも
  パターン誤爆の緊張も消える。
- コピーコストは HTML 数十ファイル（数 MB）で、ビルド全体（数十秒〜数分）に対し無視できる。

### 4.2 適用時期

vivliostyle.config.js の `entry` パス・テーマ相対パス・既存テストの前提など
**影響範囲が最大**のため、柱 1〜3 の完了後、V2.0 パイプライン刷新の本体として
実施する（第 3 部 P4）。それまでは現行 snapshot 方式を「正しく動く暫定」として維持。

---

## 5. 実施順序と依存関係

```
P1 マスキング一元化      （独立・即効・回帰小）────────┐
P2 BuildPlan 宣言化      （独立・pipeline.rb 内で完結）─┼─→ P4 ワークスペース分離 ─→ V2.0 機能群
P3 CSS 注入層            （独立・テーマシステムの前提）─┘    （小説・テーマ・直接ビルド・
                                                              print_pdf 導出・会話記法…）
```

| 段階 | 時期の目安 | 完了条件 |
|---|---|---|
| P1〜P3 | RC 後〜1.x 系（独立に着手可・任意順） | 全テスト緑＋実ビルド出力の同一性確認 |
| P4 | V2.0 開発期の最初 | snapshot/restore・退避ハックのコード消滅 |
| P5（機能群） | V2.0 | PLANNED.md の各項目（第 3 部 P5 に依存マップ） |

### この構想が課題をどう消すか（対応表）

| 課題（第 1 部） | 処方 | 消える防御コード |
|---|---|---|
| A: 分岐爆発 | 柱 1（Targets 値オブジェクト＋ステップ表） | 5 分岐・判定 4 重複・番号矛盾 |
| B: マスキング 12 実装 | 柱 2（Masking 唯一実装） | 各所の自前フェンス検出、入れ子バグ 4 件 |
| C: CSS 密結合 | 柱 3（book-settings.css 生成） | CssUpdater の正規表現置換 6 系統・awesomebook 遺物 |
| D: 可変ワークスペース | 柱 4（.cache/vs/build/ 分離） | snapshot 2 系統・.keep 退避・entries.js 再生成 |

---

## 6. 非目標（この基盤整備でやらないこと）

- **vivliostyle CLI の呼び出し方の変更**（preview/build の 2 段構成、
  backlink dedup の高速化）— PLANNED の独立項目。土台整備とは切り離す。
- **post_process の Nokogiri 処理群の再設計** — 現状で凝集しており、課題 A〜D の
  いずれにも該当しない。触らない。
- **CSS ファイル自体の再編**（分割・統合・命名変更）— 柱 3 は「触らなくて済む」
  仕組みであり、既存 CSS の中身は資産としてそのまま生かす。
- **後方互換の破壊** — P1〜P3 は 1.x 系に入れられる挙動不変リファクタ。
  著者プロジェクトの book.yml / stylesheets / custom.css は無修正で動き続ける。
  （唯一の可視変化: stylesheets/ がビルドで書き換わらなくなる＝改善方向）
