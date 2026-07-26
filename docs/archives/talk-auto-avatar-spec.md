# 会話文の簡易アバター自動生成 仕様書

> 作成日: 2026-07-25
> ステータス: **実装済み（2026-07-25）** — `TalkAvatarGenerator` ／ `TalkRegistry` の `avatar` 3 値化 ／ `MarkdownTransformer#talk_avatar_tag` の解決順 ／ `ThemeColor.luminance` として実装。PDF 実測で確認済み。残: Kindle 同梱除外の要否（§5）
> 対象: 実装済みの会話文記法（`characters-dialogue-spec.md` / `talk-display-options-spec.md`）に「アバター画像を用意しなくても使える」道を足す
> 決定事項（本仕様の提案）:
> - `avatar` を **`on` / `off` / `auto` の 3 値**へ拡張し、`auto` で**話者色＋名前の頭 1 文字の簡易アバターを自動生成**する
> - 話者単位でも `avatar: auto` と書ける（画像指定があれば画像が優先）
> - 生成には **同梱フォント `Zen Kaku Gothic New Bold`** と `magick` を使う。外部依存を増やさない
> - 生成物は**ビルド生成物**として扱う（`asset_prefix` を付けず、`GeneratedAssetCache` で永続キャッシュ）
> 関連: `lib/vivlio_starter/cli/pre_process/talk_registry.rb`, `markdown_transformer.rb`（`talk_avatar_tag`）, `generated_asset_cache.rb`, `theme_color.rb`, `showcase_transformer.rb`（外部ツール隔離の前例）, `stylesheets/fonts/Zen_Kaku_Gothic_New/`

## 0. 背景

会話文のアバターは、現状「著者が画像を用意し `avatar: haruka.webp` と書く」ことでのみ表示される。しかし**アバターの絵を用意すること自体が執筆の障壁**になりやすい。

一方で、開発中の検証用に手作業で作った「話者色を地に、名前の頭 1 文字を白抜きしただけ」の簡易アバターが、実際の紙面で十分に機能することが分かった（2026-07-24 の PDF 実測）。話者の識別という目的には、凝った似顔絵は必ずしも要らない。

これをシステム側で自動生成できるようにし、**「絵は無いがアバター付きの体裁で書き始められる」**状態を作る。用意ができたら画像へ差し替えられる。

**実現性の確認（2026-07-25 実測）**: 本プロジェクトは `stylesheets/fonts/Zen_Kaku_Gothic_New/ZenKakuGothicNew-Bold.ttf` を同梱しており、`magick` でこのフォントを指定すれば **CJK（遙・未）もラテン（A）も正しく描画できる**ことを確認済み。フォントの可搬性という最大の懸念は解消している。

## 1. 著者向け仕様

### 1.1 `avatar` を 3 値へ拡張する

現在は on / off の 2 値。ここへ `auto` を加える。

| 値 | 意味 |
|---|---|
| `on`（既定） | `avatar:` に画像を指定した話者だけアバターを出す（現行の挙動） |
| `auto` | アバターを出す。**画像指定があればその画像、無ければ簡易アバターを自動生成** |
| `off` | アバターを出さない |

```yaml
# config/talk.yml
display:
  avatar: auto      # 画像を用意していない話者にも簡易アバターが付く
```

ブロック単位でも指定できる（`talk-display-options-spec.md` §1.4 と同じ流儀）。

```markdown
:::{.talk avatar=auto}
haruka: 画像がなくても、アバター付きで書き始められます。
:::
```

### 1.2 話者単位で `auto` を指定する

`avatar:` にファイル名の代わりに `auto` と書くと、その話者だけ自動生成になる。`display.avatar` が `on` のままでも効く。

```yaml
haruka:
  name: 遙香
  color: purple
  avatar: auto      # 遙香だけ簡易アバターを自動生成

mirai:
  name: 未來
  color: blue
  avatar: mirai.webp # 未來は用意した画像を使う
```

### 1.3 解決順序

```
話者の avatar: <ファイル名>   → その画像（display.avatar が auto でも画像を優先）
話者の avatar: auto           → 常に自動生成
話者の avatar: 未指定         → display.avatar が auto なら自動生成 / on なら表示しない
display.avatar: off           → 何があってもアバターなし
```

### 1.4 生成される絵柄

- 正方形。地色は**話者の `color`**（未指定ならテーマのアクセント色）
- 中央に**表示名の 1 文字目**を白抜き（`name` 未指定ならキーの 1 文字目）
- 表示側は既存の `.talk-icon`（`border-radius: 50%`）で丸く切り抜かれる

```
  ┌───────┐          ┌───────┐
  │       │          │       │
  │   遙  │          │   A   │      ← 表示名の頭 1 文字
  │       │          │       │
  └───────┘          └───────┘
   purple             blue        ← 話者色が地色になる
```

淡い話者色（`yellow` / `lime` など）では白文字が読みにくいため、**地色の明るさに応じて文字色を白／濃灰から自動で選ぶ**。

## 2. 実装設計

### 2.1 生成器 `TalkAvatarGenerator`（新規）

`lib/vivlio_starter/cli/pre_process/talk_avatar_generator.rb`。外部ツール依存は `ShowcaseTransformer::ImageTools` と同じ流儀で内部クラスへ隔離し、テストから差し替えられるようにする。

```ruby
# @param char [TalkRegistry::Character] 話者（name と color を使う）
# @return [String, nil] 生成物への参照パス（生成できなければ nil）
def generate(char, tools: default_tools)
```

- **出力先**: `#{Common::BUILD_HTML_DIR}/images/talk-avatars/<hash>.webp`
- **参照パス**: `images/talk-avatars/<hash>.webp`（**`asset_prefix` を付けない**）
  - 著者資産（`images/characters/…`）は `asset_prefix` が要るが、**ビルド生成物は pdf/ ミラーへコピーされるため prefix 不要**。数式 SVG・showcase・mermaid と同じ規約に従う
- **永続キャッシュ**: `GeneratedAssetCache.fetch('talk-avatars', …)` を使い、クリーンビルドを跨いで再生成しない
- **キャッシュキー**: `[バージョン, 文字, 地色 hex, 文字色 hex, 一辺 px, フォント識別子]` の SHA256 先頭 16 桁（内容アドレス）。名前や色を変えれば自動的に再生成される

### 2.2 描画

```
magick -size 400x400 xc:<地色> -gravity center -fill <文字色> \
  -font stylesheets/fonts/Zen_Kaku_Gothic_New/ZenKakuGothicNew-Bold.ttf \
  -pointsize 200 -annotate 0 <文字> out.webp
```

- **一辺 400px**: 表示は 12mm 程度なので、印刷解像度（≈600dpi で 284px）に対して十分
- **文字の切り出し**: `name.grapheme_clusters.first` を使う。サロゲートペア（絵文字・異体字）や結合文字を途中で割らないため、`[0]` や `chars.first` は使わない
- **文字色の自動選択**: 地色の相対輝度（WCAG 相対輝度）を求め、**明るい地色（閾値超）なら `#333333`、暗ければ `#ffffff`** を使う。判定は `ThemeColor` へ `luminance(hex6)` を足して共用する
- **フォント**: 同梱の `ZenKakuGothicNew-Bold.ttf` に固定する。本文フォント設定に追従させると、システムフォント指定時に実体パスを解決できず破綻するため（§5 未決に追従案を残す）

### 2.3 縮退（`magick` 不在時）

`magick` が無い環境では 🟡 を出し、**アバターなしの表示へフォールバック**してビルドは続行する（`ShowcaseTransformer` と同じ方針）。`vs doctor --fix` の案内文をそのまま流用する。

### 2.4 `talk_avatar_tag` の分岐

`MarkdownTransformer#talk_avatar_tag` を次の順で解決する。

1. `options.avatar == :off` → nil
2. 話者の `avatar` がファイル名 → 既存の実在解決（`resolve_talk_avatar`）。**見つからない場合**は 🟡 の後、`auto` 相当なら自動生成へ、そうでなければ nil
3. 話者の `avatar == 'auto'`、または `options.avatar == :auto` かつ話者の指定なし → `TalkAvatarGenerator.generate`
4. それ以外 → nil

### 2.5 EPUB / Kindle

- **クリーン EPUB**: 生成物は `BUILD_HTML_DIR/images/` 配下にあるため、既存の生成物コピー（`copy_asset_tree!(File.join(Common::BUILD_HTML_DIR, 'images'), …)`）でそのまま同梱される。WebP はクリーン EPUB で使える
- **Kindle**: `decorate_talk_for_kindle!` がアバター `<img>` を除去するため表示されない。生成物が同梱だけされる無駄を避けたい場合は `localized_image?` の除外に `talk-avatars/` を足す（`_epub_assets` / `headings` と同じ扱い）

### 2.6 設定の正規化（`TalkRegistry`）

- `TalkDisplay#avatar` を真偽値から **Symbol（`:on` / `:off` / `:auto`）** へ変更する。`Common.truthy?` は `auto` を偽と判定するため、`auto` を先に見てから真偽解釈する
- ブロック引数 `avatar=auto` も同じ解釈器を通す
- `Character#avatar` は文字列のまま。値が `'auto'` のときだけ特別扱いする

## 3. テスト

1. **3 値パース**: `display.avatar` の `on` / `off` / `auto` / 未指定、ブロック引数 `avatar=auto`
2. **解決順序**: 画像指定 > 話者の `auto` > `display.avatar: auto`、`off` が全てに優先すること
3. **生成器（ツールを DI で差し替え）**: 呼び出し引数に地色・文字・フォントが渡ること／同じ入力で同じキャッシュキー、色や名前を変えると別キーになること
4. **文字の切り出し**: CJK（`遙香` → `遙`）・ラテン（`Alice` → `A`）・絵文字や結合文字を壊さないこと
5. **文字色の自動選択**: 暗い地色 → 白、明るい地色（`yellow` 等）→ 濃灰
6. **縮退**: `magick` 不在時にアバターなしで続行し 🟡 を出すこと
7. **参照パス**: 生成物の `src` に `asset_prefix` が付かないこと（著者資産との規約差の回帰防止）

## 4. 手順（実装順序）

1. 本仕様のレビュー・確定
2. `ThemeColor.luminance` 追加＋テスト
3. `TalkRegistry` の `avatar` 3 値化（`TalkDisplay#avatar` を Symbol へ）＋テスト
4. `TalkAvatarGenerator`（生成・キャッシュ・縮退）＋テスト
5. `talk_avatar_tag` の分岐＋テスト
6. EPUB 同梱の確認（必要なら Kindle 除外）
7. `config/talk.yml` のコメントと原稿 22 章へ `auto` の解説を追記 → `ruby copy_to_scaffold.rb`
8. `rake test` ＋ PDF / EPUB / Kindle の実機確認

## 5. スコープ外・未決事項

- **2 文字（姓名のイニシャル）**: 1 文字に限定する。2 文字は正方形の中で小さくなり、丸抜きで端が欠けやすい
- **図形・グラデーション等の意匠バリエーション**: 単色地＋1 文字に限定する
- **話者ごとの文字色・フォント指定**: 地色から自動選択する方式に一本化する
- **決定（2026-07-25）**: 生成フォントは同梱の Zen Kaku Gothic New Bold に固定する。本文の見出しフォント設定には追従させない（システムフォント指定時に実体パスを解決できず破綻するため）
- **決定（2026-07-25）**: Kindle では同梱しない。`localized_image?` が `characters/` と `talk-avatars/` を Kindle 限定で除外する（`<img>` ごと除去されて未参照になるため、png/jpg のアバターも含めてパッケージから外す）
