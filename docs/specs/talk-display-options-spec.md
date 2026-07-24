# 会話文の表示オプション（表示モード・話者名・アバター）仕様書

> 作成日: 2026-07-24（改訂 2: レビュー指摘を反映——`display:` セクション名・Kindle は inline 形式へ劣化）
> ステータス: **実装済み（2026-07-25）** — `talk.yml` 化・`display:` セクション・`avatar:` 改称・3 軸オプション・尻尾・Kindle の inline 組み替えまで実装し、PDF / EPUB / Kindle で確認済み
> 対象: 実装済みの会話文記法 `:::{.talk}`（`characters-dialogue-spec.md`）に「表示の切替」を追加する
> 決定事項（本仕様の提案）:
> - 制御軸は **`style`（chat / inline）・`name`（on / off）・`avatar`（on / off）** の 3 つ＋ `separator`
> - 設定ファイルを **`config/characters.yml` → `config/talk.yml` へ改称**し、**表示設定（`display:`）と話者定義（`characters:`）の 2 セクション構成**にする。`book.yml` には置かない
> - 話者のアイコン指定キーを **`icon:` → `avatar:` へ改称**し、表示軸の名前と揃える
> - `chat` で **アバターと話者名を同じ列に積む**（名前は吹き出し上部ではなくアバターの下）
> - 吹き出しに **尻尾（tail）** を付ける
> - **Kindle は `style=inline` / `name=on` 相当へ組み替えて劣化**させる（吹き出しを近似しない）
> - **`style=inline` かつ `name=off` は話者が判別不能**になるため 🟡 で警告する
> 関連: `lib/vivlio_starter/cli/pre_process/character_registry.rb`（→ `talk_registry.rb` へ改称）, `markdown_transformer.rb`（`convert_talk_blocks`）, `book_settings_css.rb`（生成 CSS）, `epub_builder.rb`（`decorate_talk_for_kindle!`）, `stylesheets/components.css`, `chapter-common.css`, `contents/22-extentions.md`

## 0. 背景 — 現状できること・できないこと

実装済みの会話文記法は「チャットアプリ風の吹き出し 1 種類」に固定されている。実際の原稿執筆で次の要求が出た（2026-07-24 の利用者フィードバック）。

| 要求 | 現状 | 判定 |
|---|---|---|
| アバターの on/off | 話者単位で `icon:` の有無により切替できる | **部分的に可能**。「本全体で消す」「このブロックだけ消す」手段が無い |
| 話者名を消して発話だけ見せたい | `<span class="talk-name">` を常に出力する | **不可**（`custom.css` の `display:none` は回避策としてのみ機能） |
| 「未來：発話」のインライン形式にしたい | 吹き出し固定 | **不可**（HTML 構造が異なるため CSS では実現できない） |

あわせて、現状の `TALK_BLOCK_PATTERN` は `{.talk}` の**完全一致**でしか会話文と認識しない。そのため `:::{.talk style=inline}` と書いても会話文として処理されず、汎用コンテナ変換へ素通りして「`未來: …` が地の文のまま並んだ素の `<div class="talk">`」に落ちる。**オプションを受け取れる形へパターンを広げることが本仕様の前提**となる。

## 1. 著者向け仕様

### 1.1 設定ファイル `config/talk.yml`（`characters.yml` から改称）

表示設定と話者定義を 1 つのファイルにまとめる。従来は話者定義しか持たなかったため `characters.yml` だったが、表示設定も担うようになるため **`talk.yml`** へ改称する。

```yaml
# 会話文の表示設定（本文の :::{.talk ...} 指定が優先される）
display:
  style: chat         # chat / inline
  name: true          # 話者名を表示する（true / on / yes / 1 が真）
  avatar: on          # アバターを表示する
  separator: "："     # inline のとき、名前と発話のあいだに置く区切り

# 話者定義
characters:
  haruka:
    name: 遙香          # 表示名（省略時はキーをそのまま表示）
    color: purple       # テーマ色名 / HEX（省略時はテーマのアクセント色）
    avatar: haruka.webp # images/characters/ 内のファイル名（省略時はアバターなし）
    side: left          # left / right（省略時は出現順に自動割当）

  mirai: blue           # 簡易形（値が色）は従来どおり
```

- `display:` を書かなければ上表の既定値で動く。**両セクションとも任意**
- 真偽値は `Common.truthy?` の語彙（`true` / `yes` / `on` / `1` を真、それ以外を偽）に従う。**キー自体を書かなければ「未指定」**として既定を引き継ぐ（明示的な `false` とは区別する）
- 2 セクション構成にするのは、`display.name`（話者名を出すか＝真偽値）と `characters.<key>.name`（表示名＝文字列）が**同じ `name` という語で意味が異なる**ため。同一階層に混ぜると読み手が誤解し、`style` という名前の話者も定義できなくなる

### 1.2 制御する 3 つの軸

直交する 3 つの値で表示を決める。モードを増やすのではなく軸を組み合わせる（「名前なし吹き出し」は `style=chat name=off` で表現でき、専用モードを作らない）。

| 軸 | 値 | 既定 | 意味 |
|---|---|---|---|
| `style` | `chat` / `inline` | `chat` | チャット風の吹き出しか、1 段落のインラインか |
| `name` | on / off | on | 話者名を表示するか |
| `avatar` | on / off | on | アバター画像を表示するか（`avatar:` 未指定の話者は元から出ない） |

区切り記号 `separator` は `inline` のときだけ使う（既定 `：`）。

### 1.3 `style` の表示

**`chat`（既定・現行相当）** — `side` に応じて左右へ振り分け、吹き出しに尻尾を付ける。アバターと話者名は**吹き出しの外側に縦に積む**（アバターの下に名前）。

```
┌─────┐
│ 🖼  │   ◀ アバター
│ 遙香 │   ◀ 名前（アバターの下）
└─────┘  ╱▔▔▔▔▔▔▔▔▔▔▔▔▔╲
         │ あら、どうしたの急に。 │  ◀ 尻尾つきの吹き出し
         ╲▁▁▁▁▁▁▁▁▁▁▁▁▁╱
```

**`inline`** — 「**名前**：発話」を 1 段落で組む。名前は話者色の太字。左右振り分けとアバターは行わない（行内に収める形式のため）。小説・脚本風の対話や、ページ効率を優先したいときに使う。

```
未來：遙香お姉さま、プログラミングを教えてください！
遙香：あら、どうしたの急に。
```

### 1.4 ブロック単位で上書きする

既存のコンテナ引数記法（`:::{.rotate-table scale=80%}`）に倣い、`key=value` を空白区切りで並べる。

```markdown
:::{.talk style=inline}
haruka: 今日はここまで。
mirai: ありがとうございました！
:::

:::{.talk name=off}
haruka: アバターだけで誰の発話か分かるときは、名前を省ける。
:::

:::{.talk avatar=off}
haruka: アバターを出さず、名前ラベルだけで見せる。
:::
```

`on` / `off` は `true` / `false` でも受け付ける。指定しなかった軸は `talk.yml` の `display:` を引き継ぐ。

### 1.5 解決順序

```
ブロック指定  >  talk.yml の display:  >  組み込み既定
```

`avatar` はこれに加えて「その話者に `avatar:` があり、実ファイルが存在すること」が常に前提となる（`avatar=on` でも `avatar:` が無ければ出ない）。

なお **Kindle は style / avatar の指定によらず inline 形式へ劣化**する（§2.5）。上の解決順序が効くのは PDF とクリーン EPUB。

### 1.6 エラー・警告

- 未知のキー（`:::{.talk styl=inline}`）→ 🟡＋受理できるキー一覧と修正例を提示し、既定で続行
- 未知の値（`style=balloon`）→ 🟡＋受理できる値（`chat` / `inline`）を提示し、既定で続行
- `style=inline` に `avatar=on` を明示指定 → 🟡「inline ではアバターを表示しません」（無指定なら黙って無視）
- **`style=inline` かつ `name=off`** → 🟡。この組み合わせは**アバター・左右振り分け・話者色のいずれも出ない**ため、発話が地の文と区別できず、誰の台詞かを読者が判別できなくなる。修正例として `name=on` に戻すか `style=chat` にする案を提示し、指定どおり出力して続行する
  - `style=chat` かつ `name=off` は警告しない（アバター・左右・吹き出しの色枠で話者が判別できるため）

### 1.7 旧 `config/characters.yml` からの移行

RC 前のため互換分岐は設けない（プロジェクト方針「後方互換性の完全排除」）。移行は次の 2 手順。

1. `config/characters.yml` を `config/talk.yml` へリネームし、既存の話者定義を `characters:` の下へ 1 段字下げして移す
2. 話者の `icon:` を `avatar:` へ書き換える

`config/characters.yml` が残っているプロジェクトは `vs doctor` が検出して 🔴 で上記手順を案内する。

## 2. 実装設計

### 2.1 `talk.yml` の読み込み（`CharacterRegistry` → `TalkRegistry`）

`character_registry.rb` を `talk_registry.rb` へ改称し、話者一覧に加えて表示設定も保持する。

```ruby
TalkDisplay = Data.define(:style, :name, :avatar, :separator)
Character   = Data.define(:key, :name, :color, :avatar, :side)  # icon → avatar へ改称
```

- `display:` セクションを `TalkDisplay` へ正規化する。未指定キーは組み込み既定（`style: :chat, name: true, avatar: true, separator: '：'`）で埋める
- 真偽値の解釈は `Common.truthy?` を使う。**キーの有無**で「未指定」と「明示 false」を区別する
- `characters:` セクションの正規化（簡易形/詳細形の吸収・`side` 自動割当・色検証）は現行ロジックをそのまま移す
- 旧形式（トップレベルに話者キーが並ぶ `characters.yml`）は読まない。§1.7 の doctor 案内に委ねる

### 2.2 記法パースの拡張

`TALK_BLOCK_PATTERN` を、`.talk` に続く任意の引数列を捕捉する形へ広げる。

```ruby
# 例: :::{.talk style=inline name=off}
TALK_BLOCK_PATTERN = /^:{3,}[ \t]*\{\s*\.talk((?:[ \t][^}]*)?)\}[ \t]*\n(.*?)^:{3,}[ \t]*$\n?/m
```

- キャプチャ 1 = 引数文字列（`{.talk}` なら空文字）、キャプチャ 2 = ブロック本文
- 引数は `key=value` を空白区切りで解析する。追加クラス（`.foo`）が混ざっていた場合は出力 `<div>` の class へ素通しする（他コンテナの流儀に合わせる）
- 解析結果を `display` とマージして `TalkOptions` に確定させ、描画へ渡す
- **後方互換**: `:::{.talk}` は引数空で従来と同じ骨格になること（`name`/`avatar` の既定が on のため）

### 2.3 HTML 構造

**`chat`（アバターと名前を同じ列に積む）**

```html
<div class="talk talk-style-chat" data-talk-sep="：">
  <div class="talk-item talk-left talk-c-haruka">
    <div class="talk-speaker">                       <!-- avatar か name のどちらかが出るとき -->
      <img class="talk-icon" src="…" alt="" />       <!-- avatar=on かつ avatar: あり -->
      <span class="talk-name">遙香</span>            <!-- 常に出力。name=off なら下記クラスで隠す -->
    </div>
    <div class="talk-body">
      <p>…</p>
    </div>
  </div>
</div>
```

- **名前はアバターの下**に置く（`.talk-speaker` を縦積みの列にする）。従来の「吹き出し上部のラベル」は廃止する
- **アバターが出ないときは話者列を作らず、名前を吹き出し上部のラベル（`.talk-body` 直下）に置く**。名前だけの細い列は幅を持て余し、小さな文字が吹き出しの脇へ取り残されて読みにくいため（PDF 実測で確認）
- **`name=off` でも `.talk-name` は出力し、`talk-name-off` クラスを付けて CSS で隠す**。Kindle は劣化時にこのクラスを外して名前を見せるため（§2.5-5）、DOM から消してはならない
- 区切り文字は容器の `data-talk-sep` 属性に持たせる。EpubBuilder が `talk.yml` を読み直さずに済む（showcase の `data-vs-raster` と同じ流儀）

**`inline`（名前が段落の内側に入る）**

```html
<div class="talk talk-style-inline" data-talk-sep="：">
  <div class="talk-item talk-c-mirai">
    <p><span class="talk-name">未來</span><span class="talk-sep">：</span>遙香お姉さま、…</p>
  </div>
</div>
```

- 発話は Kramdown で `<p>…</p>` へレンダリング済みのため、**先頭の `<p …>` の直後へ名前と区切りを差し込む**（`sub(/\A<p([^>]*)>/)`）。`<p` で始まらない出力（リスト等）になった場合は、名前だけの段落を前置するフォールバックを持つ（描画を落とさない）
- 区切り記号は **`::after` ではなく実体テキスト**として出す。Kindle は生成内容を解さないため、擬似要素にすると区切りが消える
- `talk-left` / `talk-right` は付けない（左右振り分けをしないことを構造で示す）

### 2.4 CSS（`stylesheets/components.css`）

**話者列（アバター＋名前）**

```css
.talk-speaker {
  flex: 0 0 auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1mm;
  inline-size: 14mm;          /* アバター 12mm ＋ 名前の折返し余地 */
}
.talk-speaker .talk-name {
  font-size: 0.7em;
  line-height: 1.2;
  text-align: center;
  color: var(--talk-accent);
}
.talk-name-off { display: none; }   /* name=off。Kindle 劣化時にクラスごと外す */
```

**吹き出しの尻尾** — 枠線付きの吹き出しなので、**枠色の三角（`::before`）と地色の三角（`::after`）を重ねる**古典的手法を使う。地色は変数化して両者がずれないようにする。

```css
.talk { --talk-bg: #fff; }
.talk-body { position: relative; background: var(--talk-bg); }

/* 左話者: 吹き出しの左端から話者列へ向けて尻尾を出す */
.talk-left .talk-body::before,
.talk-left .talk-body::after {
  content: "";
  position: absolute;
  top: 4mm;
  width: 0;
  height: 0;
  border-top: 1.6mm solid transparent;
  border-bottom: 1.6mm solid transparent;
}
.talk-left .talk-body::before {           /* 外側＝枠色 */
  left: -2.6mm;
  border-right: 2.6mm solid var(--talk-accent);
}
.talk-left .talk-body::after {            /* 内側＝地色（枠線ぶん内側へ寄せる） */
  left: -2.0mm;
  border-right: 2.6mm solid var(--talk-bg);
}
/* 右話者は左右反転（border-left を使い right: で位置決め） */
```

寸法（`top` の位置・三角の大きさ・内側三角のずらし量）は **PDF 実測で詰める**。Vivliostyle が flex 項目内の `position: absolute` と border 三角をどう組むかは実測が必要で、破綻する場合は尻尾なし（現行の見た目）へ落とす。

**inline**

```css
.talk-style-inline .talk-item { display: block; margin-block: 0.4em; }
.talk-style-inline .talk-name {
  display: inline;            /* chat 側の縦積み指定を打ち消す */
  font-weight: bold;
  color: var(--talk-accent);
}
.talk-style-inline .talk-sep { color: var(--talk-accent); }
.talk-style-inline p { text-indent: 0; }
```

### 2.5 Kindle 劣化 — inline 形式へ組み替える

KFX は flex・`::before`/`::after`・`var()`・丸抜き画像を解さない。吹き出しを近似しようとするより、**`style=inline` と同じ形へ DOM を組み替える**のが最も確実で、Kindle 専用 CSS もほぼ不要になる（inline 用 CSS がそのまま効くため）。劣化後の姿は次のとおり。

```html
<p><span class="talk-name">未來</span><span class="talk-sep">：</span>遙香お姉さま、…</p>
```

`decorate_talk_for_kindle!` の手順:

1. アバター `<img class="talk-icon">` を除去する
2. `.talk-name` を `.talk-body` 内の**先頭 `<p>` の先頭へ移し**、直後に区切り `<span class="talk-sep">` を挿す。区切り文字は容器の `data-talk-sep` 属性から取る
3. 空になった `.talk-speaker` を除去する
4. 容器の `talk-style-chat` を `talk-style-inline` へ差し替え、`.talk-item` から `talk-left` / `talk-right` を除去する → **既存の inline 用 CSS がそのまま効く**
5. `.talk-name` から `talk-name-off` クラスを外す。**`name=off` が指定されていても Kindle では話者名を出す**——アバターも左右も吹き出しも無い Kindle では、名前を落とすと話者を判別する手がかりが皆無になるため
6. 原稿が最初から `style=inline` の場合は組み替え不要（1〜3 は対象なし、4〜5 のみ適用）

**廃止するもの**: 話者名の `<p class="vs-talk-label">` へのタグ昇格（名前は段落内 span のまま扱う）。現行実装の `body.vs-kindle .talk-item`（左罫線）・`.vs-talk-label` 用 CSS も撤去する。

**リテラル色** — `var()` が効かないため、生成 CSS（`book-settings.css`）へ話者ごとに出す。既に枠線色・`strong` で同じ手当てをしており、同じ生成器に足すだけで済む。

```css
body.vs-kindle .talk-c-mirai .talk-name { color: #0ea5e9; }
body.vs-kindle .talk-c-mirai .talk-sep  { color: #0ea5e9; }
```

## 3. テスト

1. **`talk.yml` 読み込み**: `display:` の正規化・未指定時の組み込み既定・`Common.truthy?` 語彙（`on`/`true`/`yes`/`1`）・`characters:` の正規化（`avatar:` キー）・両セクション省略時
2. **オプション解析**: 既定（`{.talk}`）・単一指定・複数指定・未知キー 🟡・未知値 🟡・追加クラスの素通し
3. **`chat` の増減**: `avatar=off` で `.talk-icon` が出ない／`name=off` で `.talk-name` に `talk-name-off` が付く（DOM からは消えない）／既定では両方が `.talk-speaker` 内に縦に並ぶ
4. **`inline` の構造**: 名前と区切りが `<p>` の内側にある・`talk-left`/`talk-right` が付かない・区切りが実体テキスト・アバターが出ない
5. **優先順位**: `display:` をブロック指定が上書きすること／未指定の軸は `display:` を引き継ぐこと
6. **警告**: `style=inline name=off` で 🟡 が出ること／`style=chat name=off` では出ないこと
7. **生成 CSS**: 話者ごとの Kindle リテラル（`.talk-name`・`.talk-sep`）が出ること
8. **Kindle 劣化**: `chat` が inline 構造へ組み替わること（名前が `<p>` 内へ移る・区切りが入る・アイコンと `.talk-speaker` が消える・`talk-style-inline` になる・`talk-left`/`talk-right` が消える）／`name=off` でも名前が見えること／元から `inline` の原稿が壊れないこと
9. **後方互換**: 既存の `:::{.talk}` が（名前位置の変更を除き）従来と同じ骨格になること

## 4. 手順（実装順序）

1. 本仕様のレビュー・確定（記法・YAML スキーマは後方互換の縛りが生まれるため着手前に確定させる）
2. `talk.yml` 化（`talk_registry.rb` へ改称・`display:` / `characters:` の 2 セクション・`icon:` → `avatar:`）＋ doctor の移行案内＋テスト
3. オプション解析（`TALK_BLOCK_PATTERN` 拡張・`TalkOptions` の確定）＋テスト
4. `chat` の `name` / `avatar` 制御と話者列（アバターの下に名前）＋テスト
5. `inline` モード（HTML 生成＋CSS）＋テスト
6. Kindle 対応（`decorate_talk_for_kindle!` を inline 組み替えへ全面差し替え・旧 Kindle CSS 撤去・生成 CSS）＋`epub_kindle_layout_test`
7. 吹き出しの尻尾（CSS）＋ PDF 実測で寸法調整
8. `style=inline name=off` の 🟡 ＋テスト
9. 原稿 22 章「会話文（対話）」へ表示オプションの解説を追記 → `ruby copy_to_scaffold.rb`
10. `rake test` ＋ PDF / EPUB / Kindle の実機確認

## 5. スコープ外・未決事項

- **話者ごとの `style` 指定**（この人だけ inline 等）: 1 ブロック内で形式が混ざると版面が破綻するため不採用
- **`inline` でのアバター表示**（行頭に小さな丸を置く）: 行の高さが不揃いになり本文の行送りを乱すため対象外
- **`separator` の話者単位指定**: 話者ごとに区切りを変える用途が想定できないため、`talk.yml` の `display:` のみで指定する（2026-07-24 決定）
- **Kindle での吹き出し再現**: 不採用。inline 形式への組み替えで代替する（2026-07-24 決定）
- **未決**: 尻尾の意匠詳細（位置・大きさ・角丸との取り合い）は PDF 実測で決める。Vivliostyle が flex 項目内の絶対配置＋border 三角を組めない場合は尻尾を落とす
