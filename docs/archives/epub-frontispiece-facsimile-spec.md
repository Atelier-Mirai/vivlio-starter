# EPUB 章扉ファクシミリ合成仕様（縦長章扉の完全再現・裾桜ドリフト根治）

- 作成日: 2026-07-19
- 対象実装者: Opus 4.8（本仕様のみで実装が完結するよう、根拠・座標・変更差分・テスト・検証手順を全て記す）
- バグ実測: `docs/archives/epub_chapter.png`（クリーン EPUB）・`docs/archives/kindle_chapter.png`（Kindle）
- 期待レイアウトのモック: `docs/archives/epub_chapter_facsimile_mock.png`
  （本仕様 §5 の座標で rsvg-convert により実レンダリング済み。衝突なしを確認済み）
- 先行仕様: `math-frontispiece-svg-spec.md`（③-a 合成画像化）— 本仕様は同仕様の
  「扉絵の上下分割（FRONTISPIECE_SPLIT）」設計を**廃止**して置き換える
- 関連仕様（実装待ち・本仕様と整合済み）:
  - `kindle-inline-math-textify-spec.md` — 数式テキスト化は Kindle 専用フェーズで走るため
    リード内数式には届かない。リード内数式の扱いは本仕様 §4.2 が持つ（同仕様 §4.5 参照）
  - `kindle-simple-header-svg-spec.md` — 将来の simple 見出し画像化は本仕様が変えた
    `heading_image_src`（LAYOUT_VERSION ソルト）と h1 冪等ガードに追随する（同仕様 §2・§3 参照）

---

## 0. 確定済みの設計意図（ユーザー決定 2026-07-19・再検討不要）

章扉の意匠は次のとおり（PDF 版は既に実現済み）:

> 2048×2048 の装飾原画を右上から左下へ伸びる対角線で分割し、
> **左上に桜 → 中央に `:::{.chapter-lead}` → 右下に桜** を、
> 判型・余白設定に応じた**縦長**ページとして構成する。

**この縦長章扉を EPUB / Kindle でも 1 ページとして再現する**のが本仕様のゴール。
「正方形（1:1）合成でリードを画像の外に出す」代替案は 2026-07-19 にユーザーが**棄却済み**。
縦長レイアウトが正であり、変更してはならない。

## 1. 症状と経緯

### 1.1 現行バグ

EPUB / Kindle の章扉で、**右下の桜だけが次ページ先頭へ落ちる**。

- 1 ページ目: 左上の桜＋「第N章」＋章タイトル＋リード文 …… 正常
- 2 ページ目: 右下の桜だけがポツンと単独表示 …… 破綻（実測 PNG 参照）

### 1.2 経緯（3 ラウンド）

| ラウンド | 実装 | 結果 |
| :--- | :--- | :--- |
| 第 1（6月・`74319a9e`） | portrait 全面 1 枚（リード文は含まない）を h1 に合成 | 章扉画像の後にあるリードが次画面へ追いやられ、章扉ページの中央にリードが入らない |
| 第 2（7月・`7e5ba9e3`） | 原画を 62% で上下分割（`FRONTISPIECE_SPLIT`）。上帯を h1 へ、裾帯（右下桜）を `img.vs-frontispiece-tail` として chapter-lead 直後へ注入 | **裾帯が同一画面に入り切らず次ページへ落ちる（現行バグ）** |
| 第 3（2026-07-19 提案） | 1:1 square 合成（リードは画像の外） | **ユーザー棄却**（縦長章扉が仕様） |

### 1.3 根本原因

リフロー型 EPUB には「ページ下部に要素を留める」「複数要素を同一ページに固定する」手段が**存在しない**。

- 裾帯 `<img>` は分割不能ブロック。「h1 画像＋リード＋裾帯」の合計高さが 1 画面を超えた瞬間、
  リーダーは裾帯を丸ごと次ページへ送る。画面サイズとフォントサイズは読者ごとに変わるため、
  ビルド時の分割比調整では**原理的に防げない**。
- Kindle KFX は `break-inside: avoid` / `page-break-inside` を解さない
  （`vivliostyle-css-pitfalls-notes.md` の既知系）。

**帰結: 縦長章扉（桜—リード—桜）を千切れずに運ぶ唯一の決定的方法は、リード文まで含めた
「章扉全体を 1 枚の分割不能画像」にすること**（以下「ファクシミリ合成」）。

## 2. 採用方式: ファクシミリ合成

PDF と同じ portrait 画像（`{base}_portrait.webp`・判型比率でビルド済み）に、
**章番号＋章タイトル＋リード文**を焼き込んだ縦長 1 枚を h1 の `<img>` として配置し、
HTML 側の `div.chapter-lead` は（焼き込み成功時のみ）除去する。

これで章扉は:

- 両方の桜・タイトル・リードが**常に同一の 1 枚**に収まり、どの端末・フォント設定でも千切れない（決定的）
- 各章は独立 xhtml のため章頭は必ず新ページ開始、次の節は既存の
  `article.vs-section-topic-epub { page-break-before: always }` で改ページ
  → **「章扉だけの 1 ページ」という PDF と同じページ構造**が成立する
- Kindle は画面より大きい画像を 1 画面に収まるよう自動縮小するため、縦長 1.44:1 でも 1 画面表示になる

### 2.1 受け入れるトレードオフ（本仕様の前提として明記）

| 項目 | 内容 | 緩和策 |
| :--- | :--- | :--- |
| リードが実テキストでなくなる | 端末内検索・選択・読者フォントサイズ変更の対象外になる | `<img alt>` と SVG `aria-label` にリード全文を格納（読み上げ・画像非表示時のフォールバック）。クリーン EPUB は SVG の `<text>`（ベクタ）なのでズームしても鮮明 |
| リード内のインライン装飾が消える | `` `code` ``・強調などはプレーン文字化して焼き込まれる | 本文リードは装飾なし運用が通常。仕様上の許容とする |
| リード内のインライン数式（SVG `<img>`）が画像として運べない | `.text` 抽出では `<img>` が無音で脱落する | 抽出時に alt（元 LaTeX）のデリミタを剥いだ文字列へ置換して焼き込み＋著者向け警告（§4.2）。Kindle 数式テキスト化仕様は本注入より後のフェーズのため頼れない |
| 字形がビルド機フォント依存 | 見出しと同じ（③-a §B-7 で既に合意済みの性質） | フォールバックスタック（§5.3）で明朝系を保証 |
| Kindle はラスター | 拡大でぼやける可能性 | frontispiece のラスタライズ幅を 1000→1400px へ引き上げ（§5.5） |

## 3. 現状コードマップ（変更前）

| ファイル | 該当箇所 | 役割 |
| :--- | :--- | :--- |
| `lib/vivlio_starter/cli/build/heading_image_composer.rb` | `FRONTISPIECE_SPLIT`(L63) / `frontispiece_svg`(L109) / `frontispiece_tail_svg`(L135) / `RENDER_WIDTH`(L57) / `svg_wrapper` の `view_y`(L271) | 合成 SVG 生成。上帯は viewBox 0〜62% 帯切り出し |
| `lib/vivlio_starter/cli/build/epub_builder.rb` | `inject_heading_images_for_epub!`(L887) / `inject_frontispiece_headings!`(L1121) / `inject_frontispiece_tail!`(L1145) / `apply_image_heading!`(L1189) / `heading_image_src`(L1216) / `epub_heading_font_family`(L1079) | h1 注入・裾帯注入・キャッシュ・フォント |
| `lib/vivlio_starter/cli/pre_process/frontmatter_generator.rb` | `parse_theme_settings`(L44) | `frontispiece_path`（portrait）・`lead_width_value` 等を返す |
| `stylesheets/components.css` | `img.vs-frontispiece-tail`(L227 付近) | 裾帯 CSS |
| `lib/project_scaffold/stylesheets/components.css` | 同上 | scaffold 側（**直接編集禁止**・`ruby copy_to_scaffold.rb` で同期） |

補足事実（実装時に前提としてよい）:

- 章リードは Markdown の `:::{.chapter-lead}` 由来で、変換後 HTML では **h1 の直後の要素**に
  `class="chapter-lead"` が付く（現行 `inject_frontispiece_tail!` L1152 のアンカー判定が実証）。
  内部は `<p>` 1 つ以上（複数段落があり得る）。リードが無い章もある。
- portrait 画像はバンドル 12 種すべて対角デザイン（sakura 実測 2880×4153: 左上装飾 y=0〜31%・
  右下装飾 y=67.2%〜100%・x=47%〜100%、中央は空白帯）。番号 y=0.30H・タイトル中心 y=0.50H の
  現行配置は実証済みで**変更しない**。
- `theme.frontispiece.lead_width`（既定 88mm）と判型幅から、リード焼き込み幅の比率を導ける。

## 4. 実装仕様 — EpubBuilder

`lib/vivlio_starter/cli/build/epub_builder.rb`

### §4.1 裾帯注入の全廃

- `inject_frontispiece_headings!` から `inject_frontispiece_tail!(h1, doc, context)` の呼び出しを削除。
- `inject_frontispiece_tail!` メソッド（L1143-1160）を丸ごと削除。
- L866-877・L1117-1120 の「上下 2 分割」説明コメントをファクシミリ方式の説明へ書き換え。

### §4.2 リードの抽出・焼き込み・除去

`inject_frontispiece_headings!` を次の形にする:

```ruby
# 章扉（data-chapter-number-display を持つ h1）へファクシミリ合成画像を注入する。
# PDF の縦長章扉（左上飾り→番号→タイトル→リード→右下飾り）を 1 枚に焼き込み、
# リフローでも千切れない完全なページとして運ぶ（epub-frontispiece-facsimile-spec.md）。
# 焼き込みに成功した章のみ、二重表示を避けるため HTML 側の chapter-lead を取り除く。
def inject_frontispiece_headings!(doc, context)
  return false unless context[:frontispiece]

  changed = false
  doc.css('h1').each do |h1|
    next if h1['class'].to_s.split.include?('vs-image-heading-epub') # 冪等ガード（§4.5）

    number = h1['data-chapter-number-display'].to_s.strip
    next if number.empty?

    title = h1['data-chapter-title'].to_s.strip
    lead_el = frontispiece_lead_element(h1)
    lead = extract_lead_text(lead_el)

    src = heading_image_src(
      image_path: context[:frontispiece], number:, title:, kind: :frontispiece,
      lead:, lead_font_family: context[:lead_font_family], lead_ratio: context[:lead_ratio],
      font_family: context[:font_family], flavor: context[:flavor], base_dir: context[:base_dir]
    )
    next unless src

    apply_image_heading!(h1, src, [number, title, lead], doc)
    lead_el&.remove
    changed = true
  end
  changed
end

# h1 直後の chapter-lead 要素（無ければ nil）。
def frontispiece_lead_element(h1)
  el = h1.next_element
  el&.[]('class').to_s.split.include?('chapter-lead') ? el : nil
end

# chapter-lead の段落テキストを抽出する。段落は "\n" 区切り（合成側で段落ごとに字下げ）。
# インライン装飾はプレーン文字化される（仕様 §2.1）。空白・改行は 1 空白へ正規化する。
#
# リード内の <img>（インライン数式 SVG 等）は alt テキストへ置換して統合する——
# .text だけだと <img> は無音で脱落する。数式 SVG の alt には元 LaTeX が保存されている
# （math_transformer.rb）ため、$…$ / \(…\) デリミタを剥いだ素の式文字列を焼き込む。
# 注意: 本注入は両フレーバ共通フェーズで走り、Kindle 数式テキスト化
# （kindle-inline-math-textify-spec.md・Kindle 専用フェーズ）より前にリードを除去する。
# リード内数式の救済は本メソッドが唯一の機会（同仕様側では対処不能）。
def extract_lead_text(lead_el)
  return '' unless lead_el

  el = lead_el.dup
  imgs = el.css('img')
  imgs.each do |img|
    alt = img['alt'].to_s.sub(/\A\s*(?:\$|\\\()/, '').sub(/(?:\$|\\\))\s*\z/, '').strip
    img.replace(Nokogiri::XML::Text.new(alt, img.document))
  end
  warn_lead_contains_images(lead_el) unless imgs.empty?

  paragraphs = el.css('p')
  texts = paragraphs.empty? ? [el.text] : paragraphs.map(&:text)
  texts.map { |t| t.gsub(/\s+/, ' ').strip }.reject(&:empty?).join("\n")
end
```

`warn_lead_contains_images` は著者向けの親切警告を 1 回出す（章名・件数・
「章リードでは数式・画像を避けるか、本文へ移してください。alt テキストで焼き込みます」
という修正案を添える。warning-messages-actionable の流儀）。

要点:

- **リード除去は `src` 取得成功後のみ**。合成不能（rsvg 不在等）なら従来どおり
  テキスト見出し＋テキストリードの simple 縮退（§B-5 維持）。
- `apply_image_heading!` は現行実装のまま流用（segments にリードを加えるだけで
  `alt="第N章 タイトル リード全文"` になる）。
- リードが無い章は `lead` 空文字で合成（リード無しの縦長章扉。PDF と同じ）。

### §4.3 コンテキストへの追加（フォント・幅比率）

`inject_heading_images_for_epub!` の context に 2 項目を足す:

```ruby
context = {
  frontispiece: theme[:frontispiece],
  ornament: theme[:ornament],
  font_family: epub_heading_font_family,
  lead_font_family: epub_lead_font_family,          # 追加
  lead_ratio: frontispiece_lead_ratio,              # 追加
  number_color: theme[:number_color],
  flavor:
}
```

```ruby
# リード焼き込み用の本文フォントスタック（PDF の本文=明朝系に合わせる）。
def epub_lead_font_family
  body_font = Common::CONFIG.typography.body.font.to_s.strip
  stack = []
  stack << "'#{body_font}'" unless body_font.empty?
  stack.concat(["'Hiragino Mincho ProN'", "'Noto Serif JP'", "'Noto Serif CJK JP'", 'serif'])
  stack.join(', ')
end

# リード焼き込み幅の画像幅比。theme.frontispiece.lead_width（例 88mm）÷ 判型幅（page.width）。
# 単位が解けない場合は 0.60（A5 で 88/148 相当）。portrait 画像幅は綴じ補正で判型幅と数 % ずれ得るが
# 誤差として許容する。
def frontispiece_lead_ratio
  settings = PreProcessCommands::FrontmatterGenerator.parse_theme_settings
  lead_mm = Units.length_to_mm(settings[:lead_width_value])
  page_mm = Units.length_to_mm(Common::CONFIG.page[:width])
  return 0.60 unless lead_mm && page_mm&.positive?

  (lead_mm / page_mm).clamp(0.40, 0.75)
rescue StandardError
  0.60
end
```

（`Units` の参照方法は `ThemeImageResolver.binding_safe_portrait_ratio` L352-367 と同じ流儀に合わせる。
`parse_theme_settings` は `read_theme_heading_assets` でも呼んでいるため、1 回にまとめて
context 生成時に併用してよい。）

### §4.4 キャッシュキー（重要）

`heading_image_src` に `lead:`・`lead_font_family:`・`lead_ratio:` を追加し、
キーへ **リードとレイアウト版数ソルト**を混ぜる:

```ruby
def heading_image_src(image_path:, number:, title:, kind:, font_family:,
                      lead: '', lead_font_family: nil, lead_ratio: 0.60,
                      number_color: '#333333', flavor: :epub, base_dir: '.')
  key = Digest::SHA256.hexdigest(
    [HeadingImageComposer::LAYOUT_VERSION, flavor, kind, image_path,
     number, title, lead, lead_ratio, font_family, lead_font_family, number_color].join('|')
  )[0, 16]
  ...
  data = HeadingImageComposer.render(image_path:, number:, title:, lead:, kind:,
                                     font_family:, lead_font_family:, lead_ratio:, number_color:)
  # （:epub フレーバは compose、:kindle は render——現行の分岐構造は維持）
```

**ソルトが必須の理由**: `image_path`・番号・タイトルが同一のままレイアウト（帯切り出し→全高
＋リード焼き込み）が変わるため、`--no-clean` ビルドで `images/headings/` に残る旧 62% 帯画像を
キー一致で掴み、本修正が効かない事故を防ぐ。

### §4.5 冪等性

`vs-image-heading-epub` クラスが既に付いた h1 はスキップする（§4.2 冒頭の `next`）。
**理由**: 処理済み HTML を再処理すると chapter-lead が既に除去されており、リード空文字で
別キーの「リード無し合成」を作って差し替えてしまう（リード消失）。従来の裾帯側にあった
冪等チェック（L1153）は裾帯ごと消えるため、h1 側のガードが唯一の再入防止になる。

## 5. 実装仕様 — HeadingImageComposer

`lib/vivlio_starter/cli/build/heading_image_composer.rb`

### §5.1 削除

- `FRONTISPIECE_SPLIT` 定数
- `frontispiece_tail_svg` メソッドと `compose` の `:frontispiece_tail` 分岐
- `RENDER_WIDTH` の `frontispiece_tail` キー
- `svg_wrapper` の `view_y` パラメータ（tail 専用だった。呼び出しも合わせて簡素化）
- ファイル冒頭 L59-63 ほか「上下分割」の説明コメント（ファクシミリ方式の説明へ更新）

### §5.2 追加定数

```ruby
# 合成レイアウトの版数。座標・方式を変えたら +1 する（EpubBuilder が生成キャッシュのキーに混ぜる）。
# v2: 上下分割（62% 帯＋裾飾り）を廃止し、リード文まで焼き込む縦長ファクシミリ 1 枚へ。
LAYOUT_VERSION = 2

# リード焼き込みの規格（画像 width / height 比・モック実証値）。
LEAD_FONT_RATIO   = 0.024  # 基準フォント（A5 判型でおよそ 10pt 相当）
LEAD_FONT_FLOOR   = 0.018  # 縮小の下限
LEAD_LINE_HEIGHT  = 1.75   # 行送り（フォントサイズ比）
LEAD_TOP_RATIO    = 0.615  # リード 1 行目のベースライン（height 比）
LEAD_BOTTOM_RATIO = 0.80   # リード最終行ベースラインの上限（height 比）。右下飾りとの干渉回避
```

### §5.3 `compose` / `render` のシグネチャ拡張

```ruby
def render(image_path:, number:, title:, kind:, font_family:,
           lead: '', lead_font_family: nil, lead_ratio: 0.60, number_color: '#333333')
def compose(image_path:, number:, title:, kind:, font_family:,
            lead: '', lead_font_family: nil, lead_ratio: 0.60, number_color: '#333333')
```

`:frontispiece` のときだけ `lead` 系を使い、`:ornament` は無視（現行挙動不変）。
`lead_font_family` が nil なら `font_family` で代用する。

### §5.4 `frontispiece_svg` — 全高＋リード焼き込み

番号・タイトルは現行座標を**変更しない**（number y=0.30H・size 0.052W、下線、
title 中心 0.50H・size 0.072W・行送り 1.4・折返し幅 0.80W・白ハロー）。
変更は「viewBox を全高にする」「リードブロックを追加する」の 2 点のみ:

```ruby
def frontispiece_svg(width, height, data_uri, number, title, lead,
                     font_family, lead_font_family, lead_ratio)
  # …（number_size / title_size / halo / lines / line_step / number_y / underline_y /
  #     title_mid / first_y の算出は現行 L110-124 のまま）…

  parts = [image_element(width, height, data_uri)]
  parts << frontispiece_number(number, width, number_y, underline_y, number_size, font_family) unless number.empty?
  parts << frontispiece_title(lines, width, first_y, line_step, title_size, halo, font_family) unless lines.empty?
  parts << frontispiece_lead(lead, width, height, lead_font_family || font_family, lead_ratio) unless lead.empty?

  svg_wrapper(width, height, [number, title, lead], parts)   # 全高。帯切り出しなし
end

# リード段落の焼き込み。段落は "\n" 区切りで受け、各段落の先頭を全角 1 字下げする。
# 基準フォントで LEAD_BOTTOM_RATIO に収まらない長文だけ 8% ずつ縮小する（下限 LEAD_FONT_FLOOR）。
def frontispiece_lead(lead, width, height, font_family, lead_ratio)
  font_size, lines = lead_layout(width, height, lead, lead_ratio)
  halo      = [(font_size * 0.14).round, 1].max
  step      = (font_size * LEAD_LINE_HEIGHT).round
  first_y   = (height * LEAD_TOP_RATIO).round
  left_x    = ((width * (1.0 - lead_ratio)) / 2.0).round

  tspans = lines.each_with_index.map { |line, i|
    %(<tspan x="#{left_x}" y="#{first_y + (i * step)}">#{escape_text(line)}</tspan>)
  }.join
  %(<text text-anchor="start" font-family="#{font_family}" font-size="#{font_size}" ) +
    %(font-weight="400" fill="#1a1a1a" paint-order="stroke" stroke="#ffffff" ) +
    %(stroke-width="#{halo}" stroke-linejoin="round">#{tspans}</text>)
end

# リードのフォントサイズと行分割。折返しは既存 wrap_text_by_width（半角 0.55 換算・
# Latin 語は空白で折る——"--add-missing" 等の語中折れを防ぐ）を必ず使う。
def lead_layout(width, height, lead, lead_ratio)
  paragraphs = lead.split("\n")
  font_size = (width * LEAD_FONT_RATIO).round
  floor     = (width * LEAD_FONT_FLOOR).round
  loop do
    capacity = (width * lead_ratio) / font_size
    lines = paragraphs.flat_map { |p| wrap_text_by_width("　#{p}", capacity) }
    bottom = (height * LEAD_TOP_RATIO) + ((lines.size - 1) * font_size * LEAD_LINE_HEIGHT)
    return [font_size, lines] if bottom <= height * LEAD_BOTTOM_RATIO || font_size <= floor

    font_size = [(font_size * 0.92).round, floor].max
  end
end
```

下限フォントでも `LEAD_BOTTOM_RATIO` を超える異常長リードは、そのまま描画した上で
`Common.log_warn("[EPUB] 章扉リードが長すぎます（第N章）…")` を 1 回出す
（警告は具体的に: 章番号・実行数・「リードを短くするか lead_width を広げてください」を添える）。

検証済みモックの実測値（sakura_portrait 2880×4153・リード 6 行・lead_ratio 0.60）:
リード最終行ベースライン 0.761H で右下装飾（y≥0.672H だが x≥0.47W の右側のみ）と重ならない。
`epub_chapter_facsimile_mock.png` が受け入れ基準の見た目。

### §5.5 ラスタライズ幅

```ruby
RENDER_WIDTH = { frontispiece: 1400, ornament: 1400 }.freeze
```

リード文字を焼き込むため frontispiece を 1000→1400 へ（Kindle 端末幅 1072px 以上での可読性）。
クリーン EPUB は SVG（ベクタ文字）のため影響なし。

## 6. 実装仕様 — CSS と scaffold

1. `stylesheets/components.css` の `img.vs-frontispiece-tail { ... }` ルールと直前コメントを削除。
   h1 側 `.vs-image-heading-epub` 系は無変更（`width:100%; height:auto` は縦長画像でも正しい。
   Kindle が 1 画面へ自動縮小する）。
2. **scaffold 同期**: `ruby copy_to_scaffold.rb` を実行（`lib/project_scaffold/` の直接編集は禁止）。

ImageGenerator / ThemeImageResolver は**無変更**（本方式は PDF と同じ portrait をそのまま使う）。

## 7. テスト仕様

既存テストの修正:

| ファイル | 変更 |
| :--- | :--- |
| `test/vivlio_starter/cli/build/heading_image_composer_test.rb` | ① `FRONTISPIECE_SPLIT` 参照テスト（L37 付近）と `test_should_compose_frontispiece_tail_as_textless_band`（L49）を削除。② frontispiece 合成テストを「viewBox が `0 0 W H`（全高）」へ更新 |
| `test/vivlio_starter/cli/epub_builder_test.rb` | 裾帯（`vs-frontispiece-tail`）を期待する箇所を削除し、§7 新規テストへ置換 |

新規テスト（composer — 実画像・外部コマンド非依存の SVG 文字列検証で書けるものはそれで）:

1. `compose(kind: :frontispiece, lead: "...")` の SVG にリードの `<tspan>` が含まれ、
   各段落先頭が全角空白で始まる。
2. リード空文字ならリード `<text>` 要素が無い（従来相当の SVG）。
3. 極端に長いリードでフォントが縮小される（`lead_layout` の返すサイズが基準より小さい）
   ＋下限で止まる。
4. `wrap_text_by_width` 経由の折返しで Latin 語（例 `--add-missing`）が語中で折れない。
5. `LAYOUT_VERSION >= 2` の定数テスト。
6. `svg_wrapper` に `view_y` が存在しない（`frontispiece_tail_svg` 削除の回帰防止は
   `respond_to?` 検証で十分）。

新規テスト（epub_builder — 既存の注入テストのフィクスチャ流儀に従う）:

7. 注入後 HTML: h1 が `vs-image-heading-epub`＋`<img>` になり、`div.chapter-lead` が**除去**され、
   `<img alt>` にリード本文の断片が含まれる。
8. 同一 doc への **2 回目の注入で変化がない**（冪等ガード。リード無し合成への差し替えが起きない）。
9. 合成不能時（`HeadingImageComposer.render`/`compose` を nil にスタブ）: h1 はテキストのまま、
   `div.chapter-lead` が**残る**（simple 縮退）。
10. 注入後 HTML 全体に `vs-frontispiece-tail` が存在しない。
11. リードが無い章（h1 直後が chapter-lead でない）でも注入が成功する。
12. `frontispiece_lead_ratio`: 設定 88mm／判型 148mm で ≒0.595、設定欠落時 0.60。
13. リード内に `img.vs-math-inline`（alt=`$E=mc^2$`）がある場合: 抽出結果に `E=mc^2` が
    含まれ（デリミタ除去）、警告が 1 回出る。元の lead_el 自体は破壊されない（dup 処理）。

## 8. 検証手順（実装後に必ず実施）

1. `bundle exec rubocop` — クリーン。
2. `rake test` — 全件成功。
3. 実ビルド（本リポジトリのルート原稿・output.targets に epub / kindle を含む設定）:
   ```bash
   vs build --log
   ```
   - クリーン EPUB を unzip し本文章 xhtml を確認:
     - h1 内 `<img class="vs-image-heading-img">` の SVG viewBox が全高（例 `0 0 2880 4153`）
     - `div.chapter-lead` と `vs-frontispiece-tail` が**どの章にも存在しない**
     - `<img alt>` にリード全文が入っている
   - Kindle 用 `images/headings/frontispiece-*.jpg` が縦長（例 1400×2019 前後）であること
     （`magick identify`）
   - epubcheck エラー 0（既存の検証フローどおり）
4. ビューア確認（`epub_chapter.png` / `kindle_chapter.png` と同条件で再スクリーンショット）:
   - 章扉 1 ページに「左上の桜＋第N章＋タイトル＋リード＋右下の桜」が**全て**収まる
     （`epub_chapter_facsimile_mock.png` と同じ構図）
   - 次ページ先頭に桜が単独出現**しない**
   - 読者フォントサイズ最小/最大の両端でも同様（画像なので変化しないことの確認）
   - リードの長い章・無い章・タイトル 2 行の章をそれぞれ確認
   - Kindle Previewer: KFX 変換 Error 0・章扉が 1 画面に収まる
5. 縮退経路: `rsvg-convert` を PATH から外して EPUB ビルド → テキスト見出し＋テキストリードで
   出力され、ビルドが失敗しない（リードが消えていないこと）。
6. 完了後、`STATUS.md` へ結果を追記し、CHANGELOG にエントリを追加。

## 9. 非対象（変更してはならないもの）

- **PDF 経路**: `image-header.css` の @page 背景・`book_settings_css.rb`・portrait/landscape
  バリアント生成。PDF の章扉は従来どおり（実テキストのリードを CSS で重ねる）。
- **節絵（ornament）**: `ornament_svg` / `inject_ornament_headings!`。
- **前付(00)・付録(90-98)・後付(99)**: `main_chapter_file?` の対象範囲は不変（simple のまま）。
- **目次（nav）**: 各章 `<title>` 由来のため h1 置換の影響なし（現行と同じ）。
- **ImageGenerator / ThemeImageResolver**: 無変更（第 3 ラウンドの square 案は棄却済み。
  `square` バリアント等を追加しないこと）。

## 10. 完了条件チェックリスト

- [ ] `grep -rn "frontispiece_tail\|FRONTISPIECE_SPLIT\|vs-frontispiece-tail" lib stylesheets` が 0 件
      （scaffold 側も `ruby copy_to_scaffold.rb` で同期済み）
- [ ] リードが合成画像に焼き込まれ、HTML から `div.chapter-lead` が除去されている
      （合成失敗時は除去されず simple 縮退）
- [ ] `LAYOUT_VERSION`・リード本文がキャッシュキーに入っている
- [ ] 冪等ガード（`vs-image-heading-epub` スキップ）がある
- [ ] rake test / rubocop クリーン、§8-4 の見た目（モック同等）を実機確認済み

---

## 11. 状態（アーカイブ時点・2026-07-20 追記）

実装完了・実機確認待ち（2026-07-19 実装）。rake test 全 1796 件・rubocop クリーン。実 `compose` 経路の出力がモックと一致することと、実 CONFIG を通した注入経路（chapter-lead 除去・裾帯なし・全高 viewBox・alt へリード）を確認済み。

**次のアクション**: 実機確認（`vs build` で EPUB/Kindle を実出力し、章扉が 1 ページに収まること・次ページに桜が単独出現しないことを Kindle Previewer 3 と実機で確認。※本環境は Node 26 で vivliostyle が展開ハングするためフルビルド未実施）。
