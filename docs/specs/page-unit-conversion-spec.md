# 版面単位変換 仕様書（page-unit-conversion-spec）

- 策定日: 2026-07-02
- ステータス: **実装完了（2026-07-02、Claude Opus 4.8）**。Phase A/B/C すべて実装・検証済み。全テスト green（1414 件・両プロバイダ経路）／rubocop 0 offenses／フルビルド完走・`page-settings.css` バイト不変を実測確認。
- 実装担当想定: Claude Opus 4.8（本書のみで実装が完結するよう、参照実装コード・動作表・テスト表・検証コマンドまで記載する）
- 関連文書:
  - [config-access-unification-spec.md](config-access-unification-spec.md) — CONFIG アクセス統一（実装完了）。本書はその続編で、`page:` セクションの**値の単位**を扱う。
  - [config-extension-guidelines.md](config-extension-guidelines.md) — 設定キー追加の手順。

---

## 0. 実装者向けサマリ

やることは 3 つ（Phase A/B/C、§6 参照）:

1. **Phase A（中核）**: 変換定数を一元化した `Units` モジュールを新設し、`common.rb` の `normalize_page_units` 系を書き換える。既知バグ B1（Q 基準文字サイズと倍率行送りの併用で変換順序が逆）・B2（素の数値 font-size が CSS 不正値になる）・B6（Q→pt 係数が近似値）を修正する。
2. **Phase B（パーサ統一）**: `css_updater.rb` の `parse_to_mm` と `theme_image_resolver.rb` の `css_length_to_mm` を `Units.length_to_mm` へ統一する。B3（typography 経由の font_size が Q 変換を通らない）・B4（`folio_font_size` が未消費）・B5（未知単位の黙殺）・B7（`JIS-B5` キー未登録）を解消する。
3. **Phase C（任意・推奨）**: PDF 系 5 ファイルに散在する `72.0 / 25.4` を `Units` の定数参照に差し替える（挙動不変）。

テストは §7 の表をそのまま実装する（従来の「中核設定テスト」タスク③を包含）。
検証は §8 のコマンドで行う。**変更は `lib/` と `test/` のみで、scaffold 同期（`copy_to_scaffold.rb`）は不要**（`config/page_presets.yml`・`stylesheets/` は変更しない）。

---

## 1. 背景と単位ポリシー

### 1.1 経緯

参考書籍が「CSS 組版は Q 単位（級数、1Q = 0.25mm）で行なうと良い」としていたため、Q→pt の変換機構（`q_to_pt`）を用意した。現在、同梱の `page_presets.yml` に Q は登場しないが、**著者がカスタムプリセット（`a5_custom` 等）で Q を使うことは正当な使い方**であり、受理を継続する。

### 1.2 単位の使い分け（意図の明文化）

`page_presets.yml` はキーごとに単位が異なるが、これは**意図的な設計**である:

| 対象 | 単位 | 理由 |
|---|---|---|
| 文字サイズ（`base_font_size` 等） | **pt** | 印刷の慣習（級数を使う場合は Q でも指定可、内部で pt へ変換） |
| 字間（`letter_spacing`） | **em** | CSS 由来の慣習（文字サイズに比例させる） |
| 余白・判型（`margin_*`, `width`, `height`) | **mm** | 実際に定規を当てて測れる |
| 行送り（`base_line_height`） | **倍率**（無次元） | 「文字サイズの何倍か」で考える組版の慣習 |

### 1.3 行送りを倍率のまま CSS に渡さず絶対 pt へ変換する理由

CSS の `line-height: 1.7`（無次元）は**要素ごとのフォントサイズに比例**する。本プロジェクトでは `--base-line-height` を本文（`page-settings.css`）と前書き（`preface.css`）など複数箇所で参照しており、局所の `font-size` が違っても**版面の行グリッド（行送りの絶対値）を揃える**ため、読み込み時に `base_font_size × 倍率` の絶対 pt へ変換する。これは現行仕様であり、本書でも維持する。

---

## 2. 現状調査（2026-07-02 時点）

### 2.1 変換ロジックが 3 系統に分散している

| 系統 | 場所 | 対応単位 | 未知単位の扱い |
|---|---|---|---|
| `normalize_page_units` / `normalize_font_sizes` / `normalize_line_height` / `q_to_pt` / `pt_value` / `format_pt` | `common.rb:278-308` | Q / pt / em / 倍率 → pt | 素通し |
| `parse_to_mm` | `pre_process/css_updater.rb:464-473` | mm / pt → mm | **黙って `to_f`**（`"1.7"` を 1.7mm と解釈） |
| `css_length_to_mm` | `pre_process/theme_image_resolver.rb:340-358` | mm / cm / in / pt → mm | 黙って `to_f`（空文字は nil） |

### 2.2 変換係数が 8 ファイルに散在している

- `72.0 / 25.4`（mm→pt）: `create.rb`（×2）、`build/utilities.rb`、`build/nombre_stamper.rb`、`pdf/standard_provider.rb`、`pdf/pdf_read_command.rb`
- `0.3527777778`（pt→mm）: `css_updater.rb`、`theme_image_resolver.rb`
- `0.709`（Q→pt）: `common.rb` — **近似値**（正確には 0.7086614…）
- `DPI / 25.4`（mm→px）: `cover.rb`

### 2.3 テストが存在しない

`test/` 配下に `normalize_page_units` / `normalize_line_height` / `q_to_pt` / `parse_to_mm` / `css_length_to_mm` / `apply_page_preset` を対象とするテストは 1 件もない（grep で確認済み）。最も込み入ったパターンマッチ分岐が未検証のまま動いている。

### 2.4 発見した潜在バグ・不整合（本仕様で解消するもの）

| # | 内容 | 場所 |
|---|---|---|
| **B1** | `base_font_size: 30Q` と `base_line_height: 1.7` を併用すると、`normalize_line_height` が**変換前の** `pcfg` を参照するため `pt_value("30Q")` が nil → 倍率が生のまま素通しされ、行グリッドが絶対値にならない（変換順序バグ） | `common.rb:279-281` |
| **B2** | YAML で `base_font_size: 10.5`（素の数値）と書くと `pt` が付与されず、CSS 変数値 `--base-font-size: 10.5` は**不正な CSS** として黙って無視される | `common.rb:285-292` |
| **B3** | `typography.column.font_size` は `css_updater.rb:269` で**読み込み後に** `page_cfg` へ注入されるため、`normalize_font_sizes` の Q 変換を通らない（`page:` 直下に書いた場合とで挙動が異なる） | `css_updater.rb:269` |
| **B4** | `folio_font_size` は `FONT_SIZE_KEYS` に含まれ Q 変換の対象だが、**消費者がどこにもいない**（CSS の `--folio-font-size` は `calc()` 派生値）。「設定キーを受理するが消費しない」は本プロジェクトが排除してきたパターン | `common.rb:28` / `css_updater.rb:548-572` |
| **B5** | `parse_to_mm` が未知単位・素の数値を黙って `to_f` する（例: `"0em"` → 0.0mm）。現在の入力（`normalize_page_size!` 済みの mm 値）では顕在化しないが、時限爆弾 | `css_updater.rb:464-473` |
| **B6** | `q_to_pt` の係数 0.709 が近似値（正確には 1Q = 0.25mm = 18/25.4 pt = 0.7086614…pt）。10Q → 7.09pt（正: 7.087pt） | `common.rb:306` |
| **B7** | `PAGE_SIZES` に `'JIS-B5'` キーがなく、`page_presets.yml` の `size: JIS-B5` は**フォールバック先の `'B5'`（=182×257、実は JIS 寸法）に偶然一致**して正しく動いている。ISO B5（176×250）とは区別されていない | `common.rb:602-606` |

### 2.5 現状のデータフロー（変更しない部分の確認）

```
book.yml page: use: a4_compact
  → Common.load_configuration → apply_page_preset
      → load_page_presets（page_presets.yml, symbolize_names: true）
      → プリセット値 ← 著者インライン値で上書き（selected.merge(...)）
      → normalize_page_units（★本書の対象）
  → wrap_config → CONFIG.page（Data、以後 frozen）

消費側:
  css_updater.update_page_settings_css
      → typography 由来キーを page_cfg へ注入（★B3）
      → Common.normalize_page_size!（size 名 → width/height mm）
      → paper_scale / align_max_width / frontispiece_binding_offset（parse_to_mm ★B5）
      → CSS 変数置換（page-settings.css）＋ @page size ＋ vivliostyle.config.js size 同期
  theme_image_resolver.binding_safe_portrait_ratio（css_length_to_mm）
  vivliostyle.resolve_vivliostyle_size（size 名を優先、なければ width×height）
```

---

## 3. 正規仕様

### 3.1 キー別単位ポリシー（正準表）

`page:` セクション（プリセット合成後）の各キーについて、受理する入力と読み込み時の変換結果を以下に定める。**表にない形式は変換せず素通しする**（CSS として有効な値を著者が意図的に書いた可能性を尊重する。ただし §3.4 の mm パーサが解釈できない値は、mm 計算では既定値へフォールバックする）。

| キー | 正規単位 | 受理する入力 | 読み込み時の変換 |
|---|---|---|---|
| `width` / `height` | mm | mm 値、または `size` から導出 | `normalize_page_size!`（変更なし） |
| `size` | — | `A4` / `A5` / `B5` / `JIS-B5`（大文字小文字不問） | `PAGE_SIZES` で寸法解決（B7 修正） |
| `base_font_size` `column_font_size` `folio_font_size` | pt | `10pt` / `24Q` / `10.5`（素の数値） | Q→pt 変換、素の数値→`pt` 付与（B2/B6 修正）。それ以外（`px` 等）は素通し |
| `base_line_height` | 倍率 | `1.7`（倍率・推奨） / `1.7em` / `17pt` / `48Q` | 倍率・em は **変換後の** `base_font_size` × 値 → pt（B1 修正）。pt はそのまま、Q は pt へ。`%` 等は素通し（CSS 有効） |
| `letter_spacing` | em | `0em` / `0.05em` | **変換なし**（既定 `0em` は css_updater 側で付与、現行どおり） |
| `margin_top` `margin_bottom` `margin_inner` `margin_outer` | mm | `22mm`（`pt`/`cm`/`in`/`Q` も可） | **変換なし**（CSS へ素通し。Chromium は CSS 長さ単位 `q` を解する）。内部の mm 計算は §3.4 の統一パーサが解釈する |

### 3.2 変換定数の一元化 — `Units` モジュール（新設）

`lib/vivlio_starter/cli/units.rb` を新設する。**基準となる正確な関係は「1 inch = 25.4mm = 72pt」「1Q = 0.25mm」の 2 つだけ**であり、他の係数はすべてここから導出する。

```ruby
# frozen_string_literal: true

module VivlioStarter
  module CLI
    # 印刷単位の変換定数と長さパーサを一元管理する。
    # 基準は「1 inch = 25.4mm = 72pt」「1Q = 0.25mm」の 2 関係のみで、
    # 他の係数はすべてここから導出する（近似値の直書きを排除するため）。
    # 仕様: docs/specs/page-unit-conversion-spec.md
    module Units
      MM_PER_INCH = 25.4
      PT_PER_INCH = 72.0
      MM_PER_PT   = MM_PER_INCH / PT_PER_INCH   # 0.3527777…
      PT_PER_MM   = PT_PER_INCH / MM_PER_INCH   # 2.8346456…
      MM_PER_Q    = 0.25
      PT_PER_Q    = MM_PER_Q * PT_PER_MM        # 0.7086614…

      module_function

      # CSS 長さ文字列を mm の Float へ変換する。
      # 受理: mm / cm / in / pt / Q（大文字小文字不問）、単位なしの数値（mm とみなす）。
      # 解釈できない値（em・% など文脈依存の単位や非数値）は nil を返し、
      # 既定値の選択は呼び出し側に委ねる（黙って 0 扱いにしない）。
      # @param value [Object] CSS 長さ（例: '22mm', '10pt', '88Q', 22）
      # @return [Float, nil]
      def length_to_mm(value)
        s = value.to_s.strip
        case s
        in '' then nil
        in /\A(-?[\d.]+)\s*mm\z/i then Regexp.last_match(1).to_f
        in /\A(-?[\d.]+)\s*cm\z/i then Regexp.last_match(1).to_f * 10.0
        in /\A(-?[\d.]+)\s*in\z/i then Regexp.last_match(1).to_f * MM_PER_INCH
        in /\A(-?[\d.]+)\s*pt\z/i then Regexp.last_match(1).to_f * MM_PER_PT
        in /\A(-?[\d.]+)\s*q\z/i  then Regexp.last_match(1).to_f * MM_PER_Q
        in /\A-?[\d.]+\z/         then s.to_f
        else nil
        end
      end

      # 文字サイズを正規単位 pt の文字列へ変換する。
      # Q → pt 変換、素の数値 → 'pt' 付与（CSS 不正値の予防）、pt はそのまま。
      # それ以外（px / em 等）は CSS として有効な可能性があるため素通しする。
      # @param value [Object] 文字サイズ（例: '10pt', '24Q', 10.5）
      # @return [String, nil] 'Xpt' 形式など。value が nil/空なら nil
      def font_size_to_pt(value)
        s = value.to_s.strip
        case s
        in '' then nil
        in /\A[\d.]+\s*q\z/i then format_pt(s.to_f * PT_PER_Q)
        in /\A[\d.]+\z/      then format_pt(s.to_f)
        else s
        end
      end

      # pt 文字列から数値部を取り出す（'10.5pt' → 10.5、pt 以外は nil）
      def pt_value(value) = value&.to_s&.strip&.match(/\A([\d.]+)\s*pt\z/i)&.[](1)&.to_f

      # pt 数値を CSS 値文字列へ整形（小数 3 桁丸め。17.0 → '17.0pt'）
      def format_pt(value) = "#{value.to_f.round(3)}pt"
    end
  end
end
```

設計上の注意:

- `length_to_mm` の「単位なしは mm とみなす」は、既存 `parse_to_mm` の `to_f` フォールバックの**意図的だった部分**（YAML で `margin_top: 22` と書かれた場合）を仕様として明文化したもの。一方 `"0em"` のような**単位付きだが解釈できない**値は nil にする（B5 修正。従来の黙殺と違い、呼び出し側の `|| 既定値` が働く）。
- `format_pt` の丸め（`round(3)`）と末尾 `.0` の出方（`17.0pt`）は**現行踏襲**。CSS として有効であり、出力差分を最小にする。
- CSS には `q` 単位が存在する（Chromium 対応）が、文字サイズは pt へ正規化する。理由: (1) `page-settings.css` に書き込まれた値が印刷慣習の pt で読める、(2) 下流の mm 計算パーサへの入力形式が安定する。

### 3.3 `normalize_page_units` の正規動作（common.rb 書き換え）

処理順序を**「(1) 文字サイズを pt 化 → (2) その結果を使って行送りを解決 → (3) compact」**と定める（B1 修正）。参照実装:

```ruby
# page 設定の単位を正規化する（仕様: docs/specs/page-unit-conversion-spec.md §3.3）。
# 文字サイズを先に pt 化し、その結果を基準に行送り（倍率/em）を絶対 pt へ解決する。
# 行送りを倍率のまま CSS へ渡さないのは、参照箇所ごとの font-size に依存させず
# 版面の行グリッドを揃えるため（同 §1.3）。
def normalize_page_units(pcfg)
  sized = pcfg.merge(**normalize_font_sizes(pcfg))
  sized.merge(base_line_height: normalize_line_height(sized)).compact
end

def normalize_font_sizes(pcfg)
  FONT_SIZE_KEYS.each_with_object({}) do |key, memo|
    normalized = Units.font_size_to_pt(pcfg[key])
    memo[key] = normalized if normalized
  end
end

def normalize_line_height(pcfg)
  case [pcfg[:base_line_height]&.to_s&.strip, Units.pt_value(pcfg[:base_font_size])]
  in [nil | '', _]             then nil
  in [/pt\z/i => s, _]         then s
  in [/q\z/i => s, _]          then Units.format_pt(s.to_f * Units::PT_PER_Q)
  in [_, nil]                  then pcfg[:base_line_height]
  in [/em\z/i => s, f_pt]      then Units.format_pt(f_pt * s.to_f)
  in [/\A[\d.]+\z/ => s, f_pt] then Units.format_pt(f_pt * s.to_f)
  in [other, _]                then other
  end
end
```

現行からの変更点:

- `q_to_pt` / `pt_value` / `format_pt` は `common.rb` から**削除**し、`Units` へ移す（`module_function` リスト `common.rb:868-890` からも除去。外部から `Common.q_to_pt` 等を呼ぶ箇所はない — grep 済み）。`common.rb` 冒頭に `require_relative 'units'` を追加する（`loader.rb` は `common` を最初に require するため、common 内で units を読むのが安全）。
- `normalize_line_height` の分岐順を変更: **pt / Q の判定を `[_, nil]`（基準 pt なし）より先に**置く。理由: pt・Q 指定は基準文字サイズに依存せず解決できるため、`base_font_size` が無くても変換すべき（現行は `[_, nil]` が先のため `base_font_size` なし＋`base_line_height: 48Q` で素通しになる）。
- 倍率・em の解決は**変換後の** `base_font_size` を参照する（B1 修正）。

**入出力表（§7 のテストと 1 対 1 対応）:**

`base_font_size` の変換（`column_font_size` / `folio_font_size` も同一規則）:

| 入力 | 出力 | 備考 |
|---|---|---|
| `'10pt'` | `'10pt'` | 素通し |
| `'24Q'` / `'24q'` | `'17.008pt'` | 24 × 0.7086614 = 17.00787…（B6: 現行係数なら 17.016pt） |
| `10.5`（YAML 数値） | `'10.5pt'` | B2 修正: pt 付与 |
| `'10.5'` | `'10.5pt'` | 同上 |
| `'12px'` | `'12px'` | 素通し（CSS 有効値の尊重） |
| なし / `''` | 出力キーなし | |

`base_line_height` の解決（左列 × 上段 = 出力）:

| `base_line_height` \ `base_font_size` | `'10pt'` | `'30Q'`（→ `'21.26pt'`） | なし |
|---|---|---|---|
| `1.7`（数値） / `'1.7'` | `'17.0pt'` | `'36.142pt'`（B1 修正: 21.26 × 1.7） | `1.7` 素通し（unitless line-height は CSS 有効） |
| `'1.7em'` | `'17.0pt'` | `'36.142pt'` | `'1.7em'` 素通し |
| `'17pt'` | `'17pt'` | `'17pt'` | `'17pt'` |
| `'48Q'` | `'34.016pt'` | `'34.016pt'` | `'34.016pt'`（分岐順変更による改善） |
| `'150%'` | `'150%'` 素通し | 同左 | 同左 |
| なし | 出力キーなし（compact） | 同左 | 同左 |

※ `'30Q'` → 30 × 0.7086614… = 21.2598… → round(3) = `'21.26pt'`。行送りは丸め後の 21.26 を基準に 21.26 × 1.7 = 36.142（丸めの二重適用を許容し、決定的な値とする）。

### 3.4 mm パーサの統一（css_updater / theme_image_resolver）

- `css_updater.rb` の `parse_to_mm` を**削除**し、呼び出し 4 箇所を `Units.length_to_mm(x) || 既定値` に置き換える:
  - `calculate_align_max_width`: `w_mm = Units.length_to_mm(width) || 0` （既存の `return '40em' unless w_mm.positive?` がそのまま既定を担う）
  - `calculate_paper_scale`: `w_mm = Units.length_to_mm(width) || 0` / `h_mm = Units.length_to_mm(height) || 0`（既存の `positive?` ガードで 1.0 既定）
  - `calculate_frontispiece_binding_offset`: `inner_mm = Units.length_to_mm(margin_inner) || 0` / outer 同様
- `theme_image_resolver.rb` の `css_length_to_mm` を**削除**し、`binding_safe_portrait_ratio` 内の 4 呼び出しを `Units.length_to_mm(...)` へ置き換える（`|| DEFAULT_PAGE_WIDTH_MM` 等の既定値は現行のまま。**このメソッドは private ヘルパーであり公開インターフェースではないため、削除はコーディング規約の「後方互換性の完全排除」に沿う**）。
- 挙動差分: 入力は `normalize_page_size!` 済みの mm 値が正常系のため**実運用の出力は不変**。異常系（`"abc"` など）は従来 0.0mm 扱い → nil＋既定値となり、いずれも従来と同じ最終結果（既定フォールバック）に落ちる。加えて `Q` / `cm` / `in` が margin で使えるようになる（改善）。

### 3.5 消費配線の修正（B3 / B4 / B7）

- **B3**: `css_updater.rb:269` を `page_cfg[:column_font_size] = Units.font_size_to_pt(typo_cfg&.dig(:column, :font_size))` に変更（typography 経由でも Q・素の数値が正規化される）。
- **B4**: `build_css_variable_mappings` に `['--folio-font-size', page_cfg[:folio_font_size]]` を追加する（`--column-font-size` 行の直後）。値が nil のときは既存のスキップ機構により置換されず、`page-settings.css` の `calc(var(--base-font-size) * 0.75)` 既定が生きる。指定時のみ固定値で上書きされる。これで `FONT_SIZE_KEYS` の全キーに消費者が存在する状態になる。
- **B7**: `PAGE_SIZES` に `'JIS-B5' => { width: '182mm', height: '257mm' }` を明示登録し、`'B5'` は「技術書慣習により JIS 寸法の別名」とコメントする。ISO B5（176×250mm）は**サポートしない**（必要になったら `ISO-B5` キーで追加する。フォールバック既定が `'B5'` である現行動作は変更しない）。

### 3.6 `apply_page_preset` の冗長マージ整理（挙動不変）

`common.rb:260` の `selected.merge(overrides).merge(page_cfg)` は、`overrides ⊆ page_cfg`（`PAGE_PRESET_EXCLUDE_KEYS` を除いただけの部分集合）のため `.merge(overrides)` が後続の `.merge(page_cfg)` に完全に包含される。**`selected.merge(page_cfg)` へ簡約**し、`overrides` 変数を削除する。優先順位「プリセット既定 < 著者インライン値」は不変（§7 のテストで固定する）。

なお `page_cfg` に残る `use:` キー（`PAGE_PRESET_EXCLUDE_KEYS`）はマージ結果にそのまま含まれるが、これは現行も同じであり、`use` はプリセット選択子として消費済みのため問題ない。

---

## 4. 互換性への影響（リリースノート観点）

| 変更 | 影響 |
|---|---|
| Q→pt 係数の精密化（B6） | `10Q` → `7.09pt` が `7.087pt` に。**同梱プリセットに Q は無く実影響なし** |
| 素の数値 font-size の pt 付与（B2） | 従来 CSS 不正値として黙って無視されていた指定が**効くようになる**（改善） |
| 変換順序修正（B1）・pt/Q 分岐の前置 | Q 基準文字サイズ＋倍率行送りの組が正しく絶対 pt になる（従来は素通し） |
| mm パーサ統一（B5） | 未知単位が 0.0 扱い → nil＋既定値。最終出力は同一。margin で Q/cm/in が新たに解釈可能に |
| `JIS-B5` 明示登録（B7） | 解決結果は同一（フォールバック一致だったものが正規ルートに） |
| `Common.q_to_pt` / `pt_value` / `format_pt` の削除 | `Units` へ移動。外部呼び出しなし（grep 確認済み）。後方互換エイリアスは**設けない**（コーディング規約） |

同梱プリセット（`a4_compact` 等）でのフルビルド結果（`page-settings.css` の変数値・PDF レイアウト）は**バイト単位で不変**であること（§8 で検証）。

---

## 5. スコープ外（本仕様では変更しない）

- `letter_spacing` の変換（em のまま素通し、既定 `0em` 付与も css_updater の現行位置のまま）
- `margin_*` の読み込み時正規化（CSS 素通しを維持。統一パーサが解釈できれば内部計算は正しい）
- `cover.rb` の `DPI / 25.4`（mm→px は DPI 文脈固有のため対象外。`MM_PER_INCH` 参照への差し替えのみ Phase C で可）
- ISO B5 対応、`normalize_line_height` の `%` 対応（素通しで CSS 有効）
- `page_presets.yml` / `stylesheets/` / scaffold の変更（一切なし）

---

## 6. 実装計画

### Phase A — Units 新設と common.rb 中核（B1, B2, B6）

| ファイル | 変更 |
|---|---|
| `lib/vivlio_starter/cli/units.rb` | **新設**（§3.2 の参照実装） |
| `lib/vivlio_starter/cli/common.rb` | 冒頭に `require_relative 'units'`。`normalize_page_units` / `normalize_font_sizes` / `normalize_line_height` を §3.3 へ書き換え。`q_to_pt` / `pt_value` / `format_pt` を削除（`module_function` リストからも除去）。`apply_page_preset` の冗長マージ簡約（§3.6）。`PAGE_SIZES` に `JIS-B5` 追加（§3.5 B7） |

### Phase B — パーサ統一と消費配線（B3, B4, B5, B7 の消費側）

| ファイル | 変更 |
|---|---|
| `lib/vivlio_starter/cli/pre_process/css_updater.rb` | `parse_to_mm` 削除 → `Units.length_to_mm` へ（§3.4）。`column_font_size` 注入に `font_size_to_pt`（B3）。`--folio-font-size` マッピング追加（B4） |
| `lib/vivlio_starter/cli/pre_process/theme_image_resolver.rb` | `css_length_to_mm` 削除 → `Units.length_to_mm` へ（§3.4） |

### Phase C — 定数参照の一元化（任意・挙動不変）

`72.0 / 25.4` を `Units::PT_PER_MM`（または `Units::MM_PER_INCH` 系）参照に差し替え:
`create.rb`（`mm2pt` ×2）、`build/utilities.rb:158`、`build/nombre_stamper.rb:31`（`MM_TO_PT` 定数の右辺）、`pdf/standard_provider.rb:44`、`pdf/pdf_read_command.rb:595`、`cover.rb:391`（`DPI / Units::MM_PER_INCH`）。
**数値は同一のため挙動不変**。各ファイルの既存ローカル定数名（`MM_TO_PT` 等）は温存してよい（右辺のみ差し替え）。

---

## 7. テスト計画（従来タスク③「中核設定テスト」を包含）

### 7.1 `test/vivlio_starter/cli/units_test.rb`（新設）

DAMP に、§3.2/§3.3 の表を 1 ケース 1 アサーションで写経する。CONFIG 非依存（純粋関数）のため `Dir.chdir` 等の段取りは不要。

| テスト名 | 検証内容 |
|---|---|
| `test_should_define_exact_conversion_constants` | `PT_PER_Q` が `0.25 * 72 / 25.4` と一致（`assert_in_delta`、近似 0.709 の直書きでないこと） |
| `test_should_convert_lengths_to_mm` | `'22mm'`→22.0 / `'1cm'`→10.0 / `'1in'`→25.4 / `'72pt'`→25.4 / `'88Q'`→22.0 / `'88q'`→22.0 / `22`→22.0 / `'22'`→22.0 |
| `test_should_return_nil_for_unparsable_lengths` | `'0em'`→nil / `'50%'`→nil / `'abc'`→nil / `''`→nil / `nil`→nil |
| `test_should_normalize_font_sizes_to_pt` | `'10pt'`→`'10pt'` / `'24Q'`→`'17.008pt'` / `10.5`→`'10.5pt'` / `'10.5'`→`'10.5pt'` / `'12px'`→`'12px'` / `nil`→nil |
| `test_should_extract_pt_value` | `'10.5pt'`→10.5 / `'10.5PT'`→10.5 / `'10.5mm'`→nil / `nil`→nil |
| `test_should_format_pt_with_three_decimals` | `format_pt(17)`→`'17.0pt'` / `format_pt(21.2598)`→`'21.26pt'` |

### 7.2 `test/vivlio_starter/cli/common_config_loading_test.rb`（既存へ追加）

`Common.normalize_page_units` / `Common.apply_page_preset` の統合テストを追加する。§3.3 の入出力表を網羅すること。

| テスト名 | 検証内容 |
|---|---|
| `test_should_convert_q_font_size_to_pt_in_page_units` | `{base_font_size: '24Q'}` → `'17.008pt'` |
| `test_should_append_pt_to_bare_numeric_font_size` | `{base_font_size: 10.5}` → `'10.5pt'`（B2） |
| `test_should_resolve_ratio_line_height_from_converted_font_size` | `{base_font_size: '30Q', base_line_height: 1.7}` → line_height `'36.142pt'`（**B1 の回帰テスト**。現行実装では `1.7` 素通しになり fail する） |
| `test_should_resolve_em_line_height_to_pt` | `{base_font_size: '10pt', base_line_height: '1.7em'}` → `'17.0pt'` |
| `test_should_keep_pt_line_height_and_convert_q_line_height_without_base` | `{base_line_height: '17pt'}` → `'17pt'` / `{base_line_height: '48Q'}` → `'34.016pt'`（基準なしでも解決） |
| `test_should_pass_through_percent_and_unitless_without_base` | `{base_line_height: '150%'}` → `'150%'` / `{base_line_height: 1.7}`（base なし）→ `1.7` |
| `test_should_omit_blank_line_height` | `{base_font_size: '10pt'}` → 結果に `:base_line_height` キーなし |
| `test_should_apply_page_preset_with_author_overrides_winning` | `page_presets.yml` 相当の一時ファイルを使い、`{page: {use: 'x', margin_top: '30mm'}}` でプリセット値より著者値が勝つこと＋正規化が走ること（§3.6 の簡約後も優先順位不変の固定） |
| `test_should_resolve_jis_b5_page_size` | `resolve_page_size({size: 'JIS-B5'})` → `['182mm', '257mm']`（B7） |

既存の慣習に従うこと: 一時プロジェクトは `Dir.mktmpdir`＋`Dir.chdir`、teardown で `Common.reload_configuration!(silent: true)`。`apply_page_preset` は `PAGE_PRESETS_FILE`（相対パス `config/page_presets.yml`）を読むため、一時ディレクトリに最小プリセット YAML を書いてテストする。

### 7.3 既存テストへの影響

- `theme_image_resolver_ratio_test`: `css_length_to_mm` は private ヘルパー経由の間接検証のため、`Units.length_to_mm` 化後もそのまま通る見込み。fail した場合はスタブの `page` 値が §3.1 の受理形式かを確認する。
- `css_updater` 系テスト（存在すれば）: `parse_to_mm` を直接呼ぶテストは無い（grep 済み）。

---

## 8. 検証手順（実装完了の定義）

```bash
rake test                 # 全テスト green（新設含む）
rake test:standard        # StandardProvider 経路も green
bundle exec rubocop       # 0 offenses
ruby -Ilib bin/vs build   # 実プロジェクトでフルビルド完走
```

加えて次の 2 点を確認する:

1. ビルド後の `stylesheets/page-settings.css` の CSS 変数値（`--base-font-size` / `--base-line-height` / `--page-margin-*` / `--paper-scale` / `--align-max-width`）が**実装前と同一**（同梱プリセットに Q・素の数値がないため差分ゼロのはず。差分が出たら実装ミス）。
2. ビルドログに新規の警告・DEPRECATION が出ていないこと。

`CHANGELOG.md` へ Fixed（B1〜B7 のうち実挙動が変わるもの）と Added（Units モジュール・テスト）を記載する。**scaffold 同期は不要**（`lib/` と `test/` のみの変更のため）。

---

## 9. 確認事項（実装前にユーザー判断が必要なもの）

なし。本仕様の範囲・判断は 2026-07-02 のセッションでユーザーと合意済み:

- 単位の使い分け（pt/em/mm/倍率）は現行設計を追認・明文化（ユーザー提示の意図どおり）
- Q の受理は継続（参考書籍由来の設計意図を維持）
- Phase C は任意（実施推奨だが、時間が無ければ A/B のみで完結する）
