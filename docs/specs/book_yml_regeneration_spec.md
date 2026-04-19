# book.yml 更新時の特殊ページ・カバー再生成仕様

作成日: 2026-04-20
対象: `vs build` / `vs build --no-clean` における
`frontcover` / `titlepage` / `legalpage` / `colophon` / `backcover` の再生成判定

---

## 1. 背景

### 1.1 期待される仕様（ユーザ要求）

> `book.yml` を更新した場合には、キャッシュに頼らず、
> `frontcover` / `titlepage` / `legalpage` / `colophon` / `backcover` は再生成する。

### 1.2 観測された不具合

`config/book.yml` の `page.use` を `a4 → a5` に変更して `vs build --no-clean` を実行しても、
上記ページが再生成されず、既存成果物が使われるケースがある。

---

## 2. 現状のフロー調査

### 2.1 Step 9（titlepage / legalpage / colophon）

関連コード: `lib/vivlio/starter/cli/build/pipeline.rb:425-458`,
`lib/vivlio/starter/cli/build/pdf_builder.rb:160-235`

```
run_step9_front_pages_and_tail
├── ensure_special_page_exists!('titlepage' | 'legalpage' | 'colophon')
│      → .cache/vs/_xxx.md が無い時だけ生成
├── newer_than_any(front_pdf, [title_md, legal_md, book.yml])
│      → true なら CreateCommands.execute_titlepage({}) / execute_legalpage({})
├── newer_than_any(col_pdf, [colophon_md, book.yml])
│      → true なら CreateCommands.execute_colophon({})
└── Build::PdfBuilder.build_front_pages_and_tail!
       ├── SectionBuilder.ensure_chapter_html_up_to_date!('_titlepage', extra_sources: book.yml)
       ├── SectionBuilder.ensure_chapter_html_up_to_date!('_legalpage', extra_sources: book.yml)
       ├── SectionBuilder.ensure_chapter_html_up_to_date!('_colophon', extra_sources: book.yml)
       ├── cache_restore_file(front_pdf)  # 無ければキャッシュ復元
       ├── need_front = missing || newer_than_any(front_pdf, [title_md, legal_md, book.yml])
       └── need_colophon = front_regenerated || missing || newer_than_any(col_pdf, [colophon_md, book.yml])
```

### 2.2 表紙（frontcover / backcover）

関連コード: `lib/vivlio/starter/cli/cover.rb:68-86`,
`lib/vivlio/starter/cli/create.rb:179-198, 319-359, 470-510, 547-551`

```
CoverCommands.ensure_cover_files_for_build!
├── STANDARD_THEMES (light/dark): CreateCommands.execute_cover
│      ├── render_bundled_svg: needs_regeneration?(output_svg, book.yml, template)
│      │       → book.yml 更新で中間 SVG を再生成
│      └── generate_cover_outputs_from_svg
│             → convert_svg: !crop_marks && output_mtime >= input(svg)_mtime なら return
│                出力パス: covers/<side>cover_<theme>_<size>_rgb.pdf （page_size を含む）
└── master / カスタム: CoverCommands.execute_for_size
       └── generate_rgb_pdf_single: PNG → PDF（mtime チェックなし、常に生成）
```

---

## 3. 判定ロジックの弱点

### 3.1 `FileUtils.cp` による mtime 上書き（最重要候補）

`lib/vivlio/starter/cli/build/utilities.rb:40-46`:

```ruby
def cache_restore_file(cache_on, source, dest, step_label)
  return false unless cache_on && source && File.exist?(source) && dest && !File.exist?(dest)

  FileUtils.cp(source, dest)
  ...
end
```

- `FileUtils.cp` は **mtime を保持しない**。復元後、dest の mtime は「現在時刻」になる。
- その直後の `newer_than_any.call(front_pdf, [..., book.yml])` で判定すると、
  `front_pdf.mtime > book.yml.mtime` となり、**book.yml 更新が無視される**。
- 前ビルドで clean されていた場合（キャッシュから復元される条件）、
  a4→a5 の変更が反映されないまま復元 PDF が流用される可能性。

### 3.2 `execute_titlepage` / `execute_legalpage` / `execute_colophon` の早期 return

`lib/vivlio/starter/cli/create.rb:867, 921, 942`:

```ruby
return if File.exist?(path) && !options[:force]
```

- `.cache/vs/_titlepage.md` 等が既存の場合、`force: true` を渡さないと **.md を更新しない**。
- 現在 pipeline.rb は `{}`（= `force: false`）で呼んでいる（`pipeline.rb:451-458`）。
- 影響度: .md 内容は `page.use` に依存しないため **本不具合の直接原因ではない**が、
  「book.yml 更新時は必ず再生成する」という仕様を満たしていない点で **仕様不整合**。
  （例えば book.yml の `title` 変更は .md 再生成されず、HTML 側の mtime 比較で辛うじて反映される）

### 3.3 mtime 比較の根本的な脆さ

- 他ツール（Git チェックアウト、rsync、エディタ保存順など）で mtime が前後すると判定が壊れる。
- `--no-clean` 時に旧成果物の mtime が新しすぎる / 新しい .md の mtime が古すぎる等で
  検出漏れが起きる。
- `book.yml` の **どのキーが変わったか** は見ておらず、
  無関係な変更（コメント追加等）でも全再生成になり、逆に無変更でも再生成が起きる等、
  粗粒度で不正確。

### 3.4 カバー PDF 出力パス自体は page_size を含む（比較的健全）

- `frontcover_<theme>_<size>_rgb.pdf` は `<size>` を含むため、a4→a5 で**新パスになる**。
- 従って「a4 の古いファイルが参照される」現象は merger 側で起きにくい
  （`pdf_merger.rb:41` が新しい `_a5_` パスを探し、なければカバーなしで進む）。
- ただし **PNG ベース (master/カスタムテーマ)** の `generate_rgb_pdf_single` は
  `mtime` チェックすらないため、毎回生成される（問題なし、むしろ冗長）。
- **中間 SVG (`covers/<side>cover_<theme>.svg`)** は `page_size` に依存しない名前で、
  `needs_regeneration?(output_svg, book.yml, template)` を使う → book.yml mtime ベース。
  3.1/3.3 と同じ問題を抱える。

---

## 4. 再生成判定の整理（現状）

| 対象 | 判定関数 | 参照キー | 脆さ |
|---|---|---|---|
| `_titlepage.md` 等 | `File.exist?` のみ | - | book.yml 変更を検知しない |
| `_titlepage.html` 等 | mtime 比較 | `_xxx.md`, `book.yml` | FileUtils.cp で mtime 破壊される可能性 |
| `_titlepage_legalpage.pdf` | mtime 比較 | `_xxx.md`, `book.yml` | キャッシュ復元で mtime 破壊 |
| `_colophon.pdf` | mtime 比較 | `_colophon.md`, `book.yml` | 同上 |
| `covers/<side>cover_<theme>.svg` | mtime 比較 | `book.yml`, テンプレート | 同上 |
| `covers/...<size>_rgb.pdf` | `convert_svg` 内 mtime 比較 | 中間 SVG のみ | book.yml 直接参照なし、中間 SVG 経由 |
| `covers/...<size>_rgb.pdf` (PNG) | チェックなし | - | 常に再生成（冗長だが正確） |

---

## 5. 将来の改善方針

### 5.1 方針 A: mtime 破壊の修正（最小修正）

**目的**: 現行ロジックのまま、キャッシュ復元時の mtime を保持して判定精度を上げる。

**変更箇所**: `lib/vivlio/starter/cli/build/utilities.rb`

```ruby
def cache_store_file(cache_on, source, dest, step_label)
  ...
  FileUtils.cp(source, dest, preserve: true)   # ← preserve を追加
  ...
end

def cache_restore_file(cache_on, source, dest, step_label)
  ...
  FileUtils.cp(source, dest, preserve: true)   # ← preserve を追加
  ...
end
```

**効果**: キャッシュ復元後も元の mtime を保持するため、`newer_than_any` が正しく働く。

**リスク**: 小。`preserve: true` はすでに Ruby 標準機能。

---

### 5.2 方針 B: book.yml のコンテンツハッシュをキャッシュキーに組み込む（根本対処）

**目的**: mtime に頼らず、book.yml の **実際の内容変更** を正確に検出する。

**設計**:

1. ビルド成果物ごとに「依存した book.yml のハッシュ」を記録するサイドカーを作る:
   - `.cache/vs/_titlepage_legalpage.pdf.digest` に `sha256(book.yml)` と任意で
     `sha256(_titlepage.md) / sha256(_legalpage.md)` を JSON で保存。

2. 判定時にサイドカーと現在の `book.yml` ハッシュを比較:
   ```ruby
   def needs_rebuild?(output_pdf, sources)
     return true unless File.exist?(output_pdf)

     digest_path = "#{output_pdf}.digest"
     return true unless File.exist?(digest_path)

     expected = JSON.parse(File.read(digest_path))
     sources.any? { |s| File.exist?(s) && Digest::SHA256.file(s).hexdigest != expected[s] }
   end
   ```

3. 生成後にサイドカーを更新。

**効果**:
- mtime の前後関係に影響されない。
- book.yml の無関係な変更（コメント等）は、対象成果物に影響するキー
  （`page.use`, `book.title` 等）だけを抽出してハッシュ化することでさらに精度向上。

**追加で検討するハッシュ対象キー**:

| 成果物 | 依存キー（案） |
|---|---|
| `_titlepage.md` | `book.title`, `book.subtitle`, `book.author`, `book.series`, `book.release` |
| `_legalpage.md` | `legal.disclaimer`, `legal.trademark` など（あれば） |
| `_colophon.md` | `book.title`, `book.author`, `book.publisher`, `book.contact`, `book.release` |
| `_titlepage_legalpage.pdf` | 上記 + `page.use`, `page.base_font_size` 等レイアウトキー |
| `_colophon.pdf` | 上記 |
| カバー SVG | `book.title`, `book.subtitle`, `book.author`, `output.cover` |
| カバー PDF | SVG の依存キー + `page.use` + `bleed` |

---

### 5.3 方針 C: `execute_titlepage` 等の `force` 呼び出し統一（方針 B の補助）

pipeline.rb から特殊ページ生成を呼ぶ際、`force: true` を条件付きで渡す:

```ruby
# book.yml が _titlepage.md より新しい or ハッシュ差分がある場合のみ force
if needs_rebuild?(title_md, [book_yml])
  CreateCommands.execute_titlepage(force: true)
end
```

これにより「book.yml 更新時は必ず .md から再生成する」という仕様が明示的に満たされる。

---

### 5.4 方針 D: `--no-clean` 時の明示的な無効化フラグ

`vs build` に以下のオプションを追加することも検討:

- `--regen-covers`: カバー系を強制再生成
- `--regen-system-pages`: titlepage/legalpage/colophon を強制再生成
- `--regen-all`: すべて強制再生成（`--clean` に近いが、章 HTML キャッシュは温存）

ユーザが意図的に再生成できる手段を提供することで、ロジックのエッジケース対策になる。

---

## 6. ビルド時間計測（キャッシュ有効 vs 無効）

### 6.1 計測環境
- プロジェクト: vivlio-starter 自体
- コマンド: `vs build --no-clean`（キャッシュ有効） vs `vs clean && vs build`（キャッシュ無効）
- 計測日: 2026-04-20

### 6.2 計測結果

| 条件 | 実時間（total） | user time | system time |
|---|---|---|---|
| キャッシュ有効（--no-clean） | 62.66秒 | 51.89秒 | 9.26秒 |
| キャッシュ無効（clean + build） | 58.50秒 | 51.75秒 | 8.74秒 |
| **差分** | **-4.16秒** | **-0.14秒** | **-0.52秒** |

### 6.3 分析

- **キャッシュ無効の方がわずかに速い**（誤差範囲内だが、キャッシュによる短縮はほぼゼロ）
- 特殊ページ・カバーの再生成に要する時間は全体から見ればごくわずか（数秒以下）
- ビルド時間の大半は章の HTML 変換と vivliostyle レンダリングであり、
  front/title/legal/colophon/backcover のキャッシュ有無は実質的に影響しない

### 6.4 結論

**特殊ページ・カバーのキャッシュによる時間短縮は実質的にないため、mtime比較ロジックを削除して必ず再生成する仕様にしても、パフォーマンス影響は無視できる。**

---

## 7. 推奨アクション（優先順）【更新】

計測結果に基づき、推奨を変更:

| # | 対応 | 方針 | 優先度 | 影響範囲 | 工数 |
|---|---|---|---|---|---|
| 1 | **特殊ページ・カバーの必ず再生成化**（mtime比較削除） | **簡素化** | **高** | pipeline.rb + create.rb + cover.rb | 中 |
| 2 | `--regen-covers` / `--regen-system-pages` フラグ追加 | D | 中 | samovar コマンド層 | 中 |
| 3 | キャッシュ機能自体の削除検討 | 簡素化 | 低 | utilities.rb + 各所 | 小 |

**理由**: キャッシュによるパフォーマンス向上は実測で確認されなかったため、
複雑な判定ロジックを削除してコードを堅牢・シンプルにする方がメリットが大きい。

---

## 8. 次の一手（実装前の確認事項）

1. **特殊ページ・カバーの必ず再生成化を実装**:
   - `pipeline.rb` から `newer_than_any` 判定を削除し、常に `execute_titlepage` 等を呼ぶ
   - `create.rb` の `needs_regeneration?` / `return if File.exist?(path) && !options[:force]` を削除
   - `cover.rb` の `convert_svg` 内 mtime チェックを削除
   - `utilities.rb` のキャッシュ関連関数を削除または無効化

2. **テスト**: a4→a5 切替後のビルドで正しく新しいサイズで生成されることを確認

3. **オプション**: 必要に応じて `--regen-covers` / `--regen-system-pages` フラグを実装

---

## 8. 付録: 関連ソースコード索引

- `lib/vivlio/starter/cli/build/pipeline.rb`
  - `run_step9_front_pages_and_tail` (L425-)
- `lib/vivlio/starter/cli/build/pdf_builder.rb`
  - `build_front_pages_and_tail!` (L161-)
- `lib/vivlio/starter/cli/build/section_builder.rb`
  - `ensure_chapter_html_up_to_date!` (L110-139)
- `lib/vivlio/starter/cli/build/utilities.rb`
  - `cache_store_file` / `cache_restore_file` (L31-46)
- `lib/vivlio/starter/cli/create.rb`
  - `execute_titlepage` (L846-870)
  - `execute_colophon` (L884-924)
  - `execute_legalpage` (L938-)
  - `render_bundled_svg` (L319-332)
  - `apply_text_placeholders_to_svg` (L347-359)
  - `convert_svg` (L547-568)
  - `needs_regeneration?` (L527-532)
  - `resolve_page_size` (L815-818)
- `lib/vivlio/starter/cli/cover.rb`
  - `ensure_cover_files_for_build!` (L68-86)
  - `generate_rgb_pdf_single` (L298-319)
  - `detect_page_size` (L249-255)
