# 索引の主要参照仕様書 — 「出現箇所」から「説明箇所」へ

> 作成日: 2026-08-02
> ステータス: **実装完了**（Phase 1〜2・R3 は 2026-08-02、Phase 3〜6 は 2026-08-03。§7 に実装記録）
> 対象: 索引ページが全出現を同格のページ番号として並べる問題。主要参照（説明箇所）の指定・強調・並び順と、ページ番号の範囲圧縮
> 前提: `index-code-protection-unification-spec.md` → `index-term-selection-spec.md` の順に先行実装すること。特に後者の `TermSpread` を本仕様が使う
> 決定事項:
> - 主要参照は**辞書 `config/index_glossary_terms.yml` の `main:` フィールド**で指定する。原稿には手を入れない
> - `main:` は**著者の判断＝語彙の一次データ**なので辞書に残す（`score` を辞書から外すのと逆の扱い。判断基準は「原稿から導出できるか否か」）
> - 自動判定は**候補の提示までに留める**。見出し一致から候補を出し、レビューファイルへ書き込むが、確定は著者が行う
> - `main:` 未指定は**完全な現状維持**。既存プロジェクトの辞書をそのまま読め、出力も変わらない
> - ビルド時の警告は**要約 1 行**に留め、語ごとの詳細と候補はレビューファイルへ出す（58 語ぶんの警告行はノイズにしかならない）
> - 未指定を促す閾値は**章数の比率**で持つ。絶対章数だと薄い本と厚い本で意味が変わる（`book.yml` のキーにはせず定数へ固定した。理由は §7.2）
> 関連: `lib/vivlio_starter/cli/index/unified_page_builder.rb`, `index_match_scanner.rb`, `unified_terms_manager.rb`, `review_markdown_generator.rb`, `unified_index_manager.rb`, `lib/vivlio_starter/cli/build/backlink_deduplicator.rb`, `stylesheets/index.css`, `backlink-dedup-pdf-map-spec.md`, `vivliostyle-css-pitfalls.md`

## 0. 背景

索引の役割は**所在の網羅ではなく、説明の在り処への案内**である。
商業書の索引が主要参照（その語を腰を据えて説明している箇所）を太字などで区別しているのは
そのためで、「で、どこを読めばいいのか」に答えるのが索引の仕事である。

現状の索引ページは語が出るたびに項目を作るため、頻出語ほどページ番号の壁になり、
**索引としての価値が下がる**という逆転が起きている。

実測（全 27 章）: 「用語集」は 13 章に 100 回出現する。索引ページはこうなる。

```
用語集 ……… 12, 13, 18, 19, 24, 25, 26, 31, 38, 44, 45, 52, 66, 67, 68, 71, 88, …
```

「用語集」を腰を据えて説明しているのは 33 章（`33-index-glossary.md`）だけである。
本仕様はその 1 箇所を先頭に立て、太字にする。

**土台は既にある**: `IndexMatchScanner#process_term` は初出を判定して `is_definition` を立て、
タグも `<dfn>` と `<span>` で書き分けている（`index_match_scanner.rb:437-448`）。
ところが `is_definition` は**どこでも消費されていない**——`UnifiedPageBuilder` は
全出現を同格のリンクとして並べる（`unified_page_builder.rb:286-292`）。

ただし**初出＝説明箇所ではない**。前書きで軽く触れてから第 3 部で腰を据えて説明する構成のほうが
普通なので、`is_definition` をそのまま主要参照に流用はしない。

## 1. 主要参照の決め方

### 1.1 なぜ辞書フィールドか（記法にしない理由）

| 方式 | 評価 |
|---|---|
| **辞書 `main:`** | 原稿 27 章を書き換えない／「どの語の主要参照がどこか」が 1 ファイルで見える／レビュー画面で一括編集できる／記法が増えないので `21-markdown-tutorial` `90-notation-cheatsheet` の改訂が要らない |
| 原稿記法 `[用語\|読み\|*]` | 章内の一点を精密に指せるが、原稿改変を伴う（`vs furigana` と同じ慎重さが要る）。粒度は §1.3 の節指定で後から補える |
| `@index:main` | 記法が増える。`at-directive-ideas.md` §3 でも「既存の索引システムと要すり合わせ」として保留のまま |

**辞書を採る。** 原稿記法は本仕様では扱わない。

### 1.2 自動判定の限界（実測）

見出し（h1〜h3）に語が現れる箇所を主要参照とみなす案を実測した。

- 索引語 153 語のうち **120 語（78%）**が何らかの見出しに現れる
- ただし見出しヒット数の分布は偏る:

| 見出しヒット数 | 語数 |
|---|---|
| 0 件 | 33 語 |
| 1〜2 件 | 50 語 | ← 自動判定がよく効く帯 |
| 3〜5 件 | 38 語 |
| 6 件以上 | 32 語 | ← 「ファイル」は **42 見出し**にヒットする |

**自動判定だけでは頻出語を救えない。** よって自動判定は「候補の提示」に留め、
確定は著者が行う（本プロジェクトの他の記法と同じ「著者の明示を最優先、自動判定はその補助」）。

### 1.3 粒度 — 本仕様は章単位のみ

| 書き方 | 意味 | 本仕様 |
|---|---|---|
| `main: 33-index-glossary` | その章での**初出**を主要参照とする | ○ |
| `main: [33-index-glossary, 41-book-yml]` | 複数章で腰を据えて説明している場合 | ○ |
| `main: 33-index-glossary#用語集ページの生成` | 節まで指定 | 本仕様では対象外。**`index-main-reference-section-spec.md` で実装した**（2026-08-04） |

## 2. 要件

### R1: 辞書スキーマ `main:`

```yaml
- term: 用語集
  yomi: ようごしゅう
  flags: i
  main: 33-index-glossary          # 単一章
  definition: ''
  source: auto_extracted
  pattern: "/用語集/"
```

```yaml
  main:                             # 複数章
    - 33-index-glossary
    - 41-book-yml
```

- 値は章の **basename**（`.md` なし）。`TokenResolver` の慣習に合わせる
- `unified_terms_manager.rb`
  - `build_term_entry`: `entry['main'] = term['main'] if term['main']`
  - `merge_term_data`: `merged['main'] = new_data['main'] if new_data.key?('main')`
    （`nil` を明示的に渡せば消せるよう `key?` で判定する。レビューで行を消した＝指定解除）
  - `save_terms!` の `except` には**加えない**（`score` と違い一次データなので永続化する）

**妥当性の検査**（`vs index:apply` 時・親切警告の流儀）:

| 状況 | 挙動 |
|---|---|
| 指定章が `contents/` に存在しない | 🟡 警告＋実在する近い章名を候補提示。値は保存する（改名途中を壊さない） |
| 指定章に語が 1 度も出現しない | 🟡 警告＋実際に出現する章の一覧を提示 |
| 指定章が今回のビルド対象（catalog）に無い | **黙る**。部分ビルド・catalog 外運用を壊さない（`unified_index_manager.rb#full_catalog_scope?` と同じ立場） |

### R2: 候補の自動提示

`vs index:auto` が、`main:` 未指定の語について候補を 1 つ算出する。

優先順位:

1. その語を含む**見出し（h1〜h3）が最も多い章**（同数なら章番号の若い方）
2. 見出しヒットが 0 なら、**定義パターン**（`IndexCandidateExtractor::DEFINITION_PATTERNS`）が
   当たった章
3. どちらも無ければ候補なし（`主要参照:` 行を出さない）

候補は**あくまで候補**として提示し、`vs index:apply` は
**レビューファイルに書かれている値だけ**を辞書へ書く。

### R3: レビューファイルの書式とパース

`## 1. 登録済み用語の確認` の各語の**子項目**として出す。

```markdown
- [i] **用語集** (ようごしゅう) - スコア: 353.0
  - 主要参照: 33-index-glossary
  - 12-quickstart: …用語集ページが生成されます。索引と同じく…
  - 41-book-yml: …glossary: 用語集の設定です。title で…

- [i] **アインシュタイン** (あいんしゅたいん) - スコア: 429.0
  - 主要参照: `NEW!` 95-further-inspiration        ← 今回はじめて提示した候補
  - 95-further-inspiration: …アインシュタインの特殊相対性理論は…
```

- 複数章は `主要参照: 33-index-glossary, 41-book-yml`（カンマ区切り）
- **行を消せば指定なし**、書き換えれば別の章
- 既存の候補提示と同じく `` `NEW!` `` ラベルで新規提示を示す
- **用語行そのものの書式は変えない**。`- [i] ` と `**用語** (読み)` の間に何も差し込まない
  ——既存 7 つのパーサの正規表現が軒並みマッチしなくなるため（`index-term-selection-spec.md` §3 R5.2 と同じ制約）

新設パーサ `parse_main_references`:

```ruby
# 用語ブロック（"- [flag] **用語** (読み)" とそれに続くインデント行）ごとに
# 主要参照の行を読む。行単位で独立に scan する既存パーサと違い、
# 用語と子項目の対応が要るためブロック単位で見る。
def parse_main_references
  return {} unless exists?

  content = File.read(review_file_path, encoding: 'utf-8')
  boundary = content.index('## 4. 除外済みリスト')
  search = boundary ? content[0...boundary] : content

  result = {}
  search.scan(/^- \[[^\]]*\](?: `(?:NEW!|Today)`)? \*\*(.+?)\*\* \([^)]+\)[^\n]*\n((?:[ \t]+[^\n]*\n)*)/) do |term, body|
    line = body[/^\s*- 主要参照:\s*(?:`(?:NEW!|Today)`\s*)?(.+)$/, 1]
    # 行が無ければ「指定なし」を意味する nil を入れる（既存指定の解除を表現するため）
    result[term] = line ? line.split(',').map(&:strip).reject(&:empty?) : nil
  end
  result
end
```

`apply_markdown_review!` は、承認された索引語について
`@terms_manager.update_main!(term, chapters_or_nil)` を呼ぶ。

### R4: タグ付け側で主要参照を立てる（`IndexMatchScanner`）

`process_term` で `is_main` を算出する。

```ruby
# 章ごとの出現順（主要参照は「指定章での初出」と定める）
@chapter_occurrence = Hash.new(0)
```

```ruby
def process_term(term_text, yomi, file_basename)
  @term_occurrence[term_text] += 1
  occurrence_num = @term_occurrence[term_text]
  @chapter_occurrence[[term_text, file_basename]] += 1

  # 主要参照＝辞書 main: が指す章での初出。章内の 2 回目以降は副次参照。
  is_main = main_chapters(term_text).include?(file_basename) &&
            @chapter_occurrence[[term_text, file_basename]] == 1
  …
  @index_data[term_text] << {
    'yomi' => yomi,
    'link' => "#{file_basename}.html##{anchor_id}",
    'file' => file_basename,
    'is_definition' => is_first,
    'is_main' => is_main
  }
```

`@matches` にも `'is_main'` を足す。HTML タグ側（`<dfn>`/`<span>`）は**変更しない**
——主要参照かどうかは索引ページ側の表現であり、本文の見た目を変える話ではない。

`main_chapters` は辞書（`@unified_terms`）から引く。`Array()` で単一値とリストを吸収する。

### R5: 索引ページの出力（`UnifiedPageBuilder`）

```ruby
def generate_index_page_links(term)
  occurrences = order_occurrences(@index_data[term])
  occurrences = apply_reference_style(term, occurrences)

  occurrences.map do |occ|
    link = occ['link'] || occ[:link]
    classes = []
    classes << 'main-ref' if occ['is_main']
    classes << 'frontmatter' if link.start_with?('00-')
    attr = classes.empty? ? '' : %( class="#{classes.join(' ')}")
    %(<a href="#{link}"#{attr}></a>)
  end.join
end

# 主要参照を先頭へ。同種のなかでは元の走査順（章順）を保つ。
def order_occurrences(occurrences)
  occurrences.to_a.partition { it['is_main'] }.flatten(1)
end
```

**並べ替えは dedup より前に行う必要がある。** `BacklinkDeduplicator#deduplicate_links_in_dd!` は
同一ページを指すリンクの **DOM 上で最初の 1 本**を残すので、主要参照が先頭にあれば
それが生き残る。順序が逆だと主要参照が消える。

### R6: 出し方の選択（`book.yml`）

```yaml
index:
  # 参照の出し方
  reference_style: main_and_sub   # 既定
  #   main_and_sub … 主要参照を太字で先頭＋副次参照（max_sub_references 件まで）
  #   main_only    … 主要参照のみ（ページ単価を詰めたい本向け）
  #   all          … 太字も間引きもしない（従来どおり）

  # main_and_sub のときの副次参照の上限（0 で無制限）
  max_sub_references: 8
```

- `main:` 未指定の語は、`main_only` でも**従来どおり全出現を出す**
  （主要参照が無いのに間引くと語が索引から消える）
- **間引いたことは黙らない**（`no silent caps`）。ビルド末尾に 1 行:

  ```
  ℹ️ 索引の副次参照を 14 語で 8 件までに絞りました（index.max_sub_references: 8）
  ```

### R7: 主要参照が未指定の語を促す

`index-term-selection-spec.md` の `TermSpread` を使う。

```yaml
index:
  # この比率以上の章に出る語は、主要参照の指定を促す
  main_reference_hint_ratio: 0.33
```

- 対象: `TermSpread#ratio >= main_reference_hint_ratio` かつ `main:` 未指定
- 下限は `TermSpread` と共通（全章数 6 未満の本では判定しない／`chapter_count < 3` は対象外）
- 実測では **38 語**が該当する（`index-term-selection-spec.md` の一般語 20 語を著者が外せば、
  残るのは 30 語前後）

**ビルド時は要約 1 行だけ**にする:

```
🟡 主要参照が未指定の索引語が 30 語あります（索引が引きにくくなります）
   vs index:auto を実行すると、章の候補付きで一覧できます
```

- `IssueRegistry` へは **1 件**だけ記録する（`category: :index`・特定の章の欠陥ではないので `chapter` なし）
- 語ごとの詳細と候補はレビューファイル（R3）に出す。ビルドログに 30 行並べても
  そこから修正には進めない——修正の場はレビューファイルであり、導線はそこへ向ける

### R8: ページ番号の範囲圧縮

「ファイル」が 12〜38 ページに連続して出るとき「12, 13, 14, …, 38」ではなく
「**12-38**」と出す。主要参照の判定精度に依存せず効くので、R1〜R7 と独立に価値がある。

#### 8.1 なぜ dedup 段でやるか

ページ番号は CSS `target-counter` がレンダ時に解決するため、Ruby 側は本来ページ番号を知らない。
ただし `BacklinkDeduplicator` だけは `PdfPageMapExtractor` の
`index_anchor_to_page`（`anchor_id → [spine_index, page_index]`・`page_index` は**通しページ番号**）
を持っている。連続判定はここでしかできない。

#### 8.2 出力形式を「解決済み」へ切り替える

現行 CSS は区切りのカンマを `a:not(:last-child)::after` で出しており、
リンクを `<span>` でくくると**兄弟セレクタの前提が壊れる**。
そこで dedup 済みの `<dd>` は区切りを**リテラルのテキストノード**で持つ形へ書き換え、
CSS はページ番号の描画だけを担う。

```html
<!-- dedup 前（UnifiedPageBuilder の出力・従来どおり） -->
<dd><a href="…#idx-a"></a><a href="…#idx-b"></a><a href="…#idx-c"></a></dd>

<!-- dedup 後 -->
<dd class="resolved">
  <a href="…#idx-a" class="main-ref"></a>, <span class="page-range"><a href="…#idx-b"></a>–<a href="…#idx-c"></a></span>
</dd>
```

```css
/* 解決済み: 区切りはマークアップが持つ。CSS はページ番号だけ描く */
.index-list dd.resolved a::after {
  content: target-counter(attr(href url), page);
}
.index-list dd.resolved a.frontmatter::after {
  content: target-counter(attr(href url), page, lower-roman);
}

/* 未解決（EPUB / Kindle / dedup 無効時）は従来の :not(:last-child) 方式で組む */
.index-list dd:not(.resolved) a:not(:last-child)::after { … }
```

既存ルールは `dd:not(.resolved)` へ限定するだけで、削除はしない。
**EPUB / Kindle 経路では dedup が走らない**（`epub_flow.rb` は dedup を通らない `html/` の原本から作る）ため、
そちらは従来どおりのフォールバックで組まれる。

#### 8.3 範囲にまとめる条件

```yaml
index:
  page_range_min: 3   # 連続がこの数以上のときだけ範囲表記にする（2 なら "12, 13" のほうが読みやすい）
```

- 連続判定は `page_index` の連番で行う
- **前付け（`.frontmatter`・ローマ数字）と本文（アラビア数字）はまたがない**。
  番号系が違うため「iv-12」のような無意味な範囲ができる
- **主要参照は範囲に含めない**。太字の一点であることに意味があるので、単独で先頭に置く

## 3. CSS

`stylesheets/index.css` に追加する。

```css
/* 主要参照（説明箇所）は太字にする。
   <a> は空要素で、見えている数字は ::after の target-counter が描く。
   font-weight は ::after へ継承されるので <a> 側に置けばよい。 */
.index-list a.main-ref {
  font-weight: bold;
}

/* ページ範囲のダッシュは前後を詰める */
.index-list .page-range {
  white-space: nowrap;
}
```

**Kindle(KFX) 対応**: `font-weight: bold` はリテラル値で `var()` を使わないため、
`vivliostyle-css-pitfalls.md` §11 の「`var()` を含む宣言ごと破棄される」問題に該当せず、
`body.vs-kindle` 向けの別書きは**不要**。ただし実機確認は必要（§5.3）。

## 4. `book.yml` スキーマ差分

```yaml
index:
  reference_style: main_and_sub
  max_sub_references: 8
  main_reference_hint_ratio: 0.33
  page_range_min: 3
```

`common.rb` の CONFIG スキーマ（`:247`）へ 4 キーを追加する。
既定値はスキーマ側を正とし、同梱 `book.yml` はサンプル値という役割分担を守る
（`PLANNED.md`「既定値の二重管理」）。

## 5. テスト

### 5.1 単体

| 対象 | 検証 |
|---|---|
| `UnifiedTermsManager` | `main` の保存・単一/リストの往復・`nil` 指定で解除・`save_terms!` が落とさない |
| `IndexMatchScanner` | 指定章の初出だけ `is_main`／章内 2 回目は立たない／未指定なら全件 false／複数章指定で各章の初出に立つ |
| `UnifiedPageBuilder` | 主要参照が先頭へ来る／`class="main-ref"` が付く／`main_only` で副次参照が落ちる／未指定語は `main_only` でも全出現が残る／`max_sub_references` の上限 |
| `ReviewMarkdownGenerator` | `主要参照:` 行の生成とパース／行が無ければ `nil`（解除）／カンマ区切りの複数章／**用語行の書式が変わっていないこと**（既存パーサの回帰） |
| `TermSpread` 連携 | 警告が要約 1 行であること／`IssueRegistry` へ 1 件だけ積むこと |
| `BacklinkDeduplicator` | 連続 3 ページが範囲になる／2 ページは範囲にしない／前付けと本文をまたがない／主要参照は範囲に含めない／`dd.resolved` が付く |

### 5.2 結合

- `test/vivlio_starter/page_layout/` に 1 本追加し、実ビルドで
  `_indexpage.html` の主要参照が太字クラスを持ち先頭にあることを確認する
- EPUB 経路で `dd.resolved` が**付かない**こと（フォールバック CSS が効く形であること）

### 5.3 実機・目視

- **Kindle Previewer**: 主要参照の太字が効くか。`PLANNED.md`「Kindle Previewer 実機確認の積み残し」に
  既に 3 件たまっているので、**まとめて 1 回で消化**する
- PDF: 「用語集」の索引項目が「**130**, 12, 18, 24, …」の形になること

## 6. 実装フェーズ

| Phase | 内容 | 単独で価値があるか |
|---|---|---|
| 1 | R1（辞書 `main:`）＋ R4（`is_main` のタグ付け） | データが通るだけ。出力は不変 |
| 2 | R5（先頭ソート＋`main-ref`）＋ CSS | ○ 手で `main:` を書けば効く |
| 3 | R2 + R3（候補提示・レビュー往復） | ○ 著者の導線が完成する |
| 4 | R7（未指定の要約警告） | ○ |
| 5 | R6（`reference_style` / `max_sub_references`） | ○ |
| 6 | R8（ページ範囲圧縮） | ○ **他と独立**。CSS の切り替えが難航したら RC 後へ回せる |

Phase 6 だけは触る層が違う（PDF の dedup 段・CSS の描画契約）ため、
**最後に単独で入れる**。ここで詰まっても Phase 1〜5 の価値は毀損しない。

## 7. 実装記録（2026-08-03・Phase 3〜6）

Phase 1〜2 と R3 は 2026-08-02 に実装済み。ここでは残る Phase 3〜6 で分かったことを残す。

### 7.1 R2 の対象を「広く散らばっている語」に絞った（仕様の変更）

R2 は「`main:` 未指定の語について候補を 1 つ算出する」と書いていたが、**実装では
`main_reference_hint_ratio` 以上の広がりを持つ語だけに絞った**。

理由は 2 つある。

1. **全語に出すと事実上の一括自動適用になる。** レビューファイルに書かれた値は
   `vs index:apply` がそのまま辞書へ書く（フラグ `[i]` が既定で埋まっているのと同じ）。
   実測で索引語 153 語のうち候補を出せるのは大半なので、著者が 1 行も消さなければ
   150 語近くに `main:` が付く。「自動判定は候補の提示までに留める」という決定事項
   （冒頭）と実質的に矛盾する。
2. **狭い語には要らない。** 2〜3 章にしか出ない語は、索引のページ番号がそのまま
   案内として働く。指定が要るのは「ページ番号の壁」になる語だけである。

対象集合を R7 の警告と**同一**にしたことで導線が閉じた——ビルドで「30 語あります」と
言われた著者がレビューファイルを開くと、まさにその 30 語に候補が並んでいる。

実測（本書・全 27 章・索引語 153 語）: 対象 55 語／候補を出せたのは 53 語。

### 7.2 `main_reference_hint_ratio` は設定にしなかった（仕様の変更）

R7 は `index.main_reference_hint_ratio` として `book.yml` に出す前提だったが、
**キーを置かず定数 `0.33` に固定した**。実装後のレビューで、このつまみが
担う 2 つの役割のうち後者が破綻していると分かったため。

| 役割 | 評価 |
|---|---|
| 促す範囲の微調整（0.33 → 0.4） | 著者が「0.4 が適切」と判断する材料が無い |
| 警告を止める（`1.0`） | **無効化の意図が値から読めない**。魔法の数字になる |

しかも**無効化の導線は既にあった**。`reference_style: all` は主要参照の扱いを
丸ごと切る設定なので、それを選んでいる著者に「主要参照が未指定です」と促すのは
筋が通らない。当初の実装はそこを見ておらず、`all` でも警告と候補提示が動いていた。

`all` のとき `warn_missing_main_references` と `suggest_main_references` の
両方を止めることで、つまみを 1 本減らしつつ無効化を意味の読める操作にした。

`common_term_ratio`（一般語＝索引から外すことを推奨する閾値）は残す。
「どこから外すべきか」は本の性格で変わるので、調整の実需がある。

### 7.3 `all` は並べ替えも太字も切る

R6 の表は `all` を「太字も間引きもしない（従来どおり）」としている。「従来どおり」を
**Phase 2 以前の索引と完全に同じ**と解釈し、`order_occurrences` による並べ替えも
`main-ref` クラスの付与も行わない。この機能を丸ごと切るための逃げ道として置く。

### 7.4 R8 の連続判定は `spine_index` も見る

`PdfPageMapExtractor` は `spine_index` を 0 固定で作るので実運用では `page_index` の
連番だけで足りるが、`BacklinkDeduplicator` の同一ページ判定は `(spine_index, page_index)`
の組で行っている。範囲判定だけ `page_index` 単独で見ると、判定の単位が dedup と
ずれる。組が一致することを条件に加えた。

### 7.5 レビューファイルの凡例に記法例を載せると、素朴な文字列置換が凡例に当たる

凡例へ `- 主要参照: 21, 22` という**例文**を足したところ、既存テストの
`content.sub('- 主要参照: 21, 22', …)` が凡例のほうを書き換えるようになった。
パーサ（`term_blocks`）は用語行から始まるブロックしか見ないので解釈には影響しないが、
**レビューファイルを文字列で書き換えるコードは行頭 2 スペースのインデントで
アンカーする**こと（`^ {2}- 主要参照:`）。

同じ理由で、R7 の警告文に「レビューファイル」という語を含めると、
`refute_includes message, 'ファイル'` のようなテストが誤爆する。

### 7.6 §5.2 の結合テストは単体テストへ置き換えた

仕様は `test/vivlio_starter/page_layout/` へ 1 本追加するとしていたが、そこは判型検証
専用のファイルで、実ビルド（`vs build`）を回すため `rake test` から除外されている
——**回帰検知としてほとんど働かない**（誰も走らせない）。代わりに次の形にした。

- 主要参照の先頭ソートと `main-ref` クラス → `unified_page_builder_test`（実 HTML を生成して検査）
- `dd.resolved` が EPUB 側の原本に付かないこと → `backlink_deduplicator_test`（`html/` と `pdf/` の
  両方にファイルを置き、書き換わるのが後者だけであることを見る）
- 通し確認 → 実ビルドを 1 回実行し、PDF のテキスト抽出で確認（下記）

実ビルドでの実測（`main:` を 3 語に仮設定した状態）:

```
用語集 …… 196, ii, 24, 27, 51, 102      ← 196 が主要参照（33-index-glossary の初出）
ビルド …… i, ii, 1, 3–6, 11, 15, 20, …, 105–107, …, 128–130, …
```

範囲圧縮が効き、前付け（ローマ数字 `ii, v`）と本文をまたぐ範囲は作られていない。
ビルド末尾には R6・R7 の報告が両方出た。

**太字（`.main-ref`）の見た目だけは PDF のテキスト抽出では確認できない。** Kindle も
含めて実機目視が残る（`PLANNED.md`「Kindle Previewer 実機確認の積み残し」）。

### 7.7 `TermPattern` を新設した

辞書エントリ → 照合 Regexp の 3 行が `TermSpread` と `IndexCandidateExtractor` に重複して
おり、`MainReferenceSuggester` で 3 箇所目になったため 1 つに集めた。剥がし方がずれると
「広さは数えるのに候補は出ない」という噛み合わない挙動になる。

Ruby の `\b` が日本語を語構成文字として扱う（`/\bRuby\b/` が「Rubyの基礎」に当たらない）
点は、本文タグ付け（`IndexMatchScanner`）と同じ側に揃えてある。ここだけ緩めると、
索引に載らない章を主要参照として勧めることになる。

## 8. 完了時の作業

- `PLANNED.md` の「索引を『出現箇所』でなく『説明箇所』を指すものにする」項目を削除する
- 本ファイルを `docs/archives/` へ `git mv` し、`STATUS.md` の該当行を削除する
- `contents/33-index-glossary.md` に `main:` の書き方・レビューでの指定方法・
  `reference_style` の解説を追記し、`ruby copy_to_scaffold.rb` で雛形へ同期する
- 節指定（`main: 章#見出し`）と原稿記法は本仕様の対象外。必要になったら
  `PLANNED.md` へ改めて起こす
