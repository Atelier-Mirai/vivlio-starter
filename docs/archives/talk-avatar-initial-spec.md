# 会話文のアバターに入れる字と大きさを指定する 仕様書

> 作成日: 2026-10-12
> ステータス: **実装済み（2026-10-12）** — §1〜§6 は `TalkRegistry#validate_initial` ／ `TalkAvatarGenerator#fit_pointsize`・`magick_text`・`AvatarTools#measure`、§7 は `TalkRegistry#parse_avatar_size` ／ `BookSettingsCss#talk_variable_declarations` ／ `components.css` の `--talk-icon-size`・`--talk-speaker-size` として実装。95 章の `initial:` と、22 章の `avatar_size: 15` を PDF で確かめた
> 対象: 実装済みの簡易アバター（`talk-auto-avatar-spec.md`）に、入れる字を著者が 1〜2 文字で指定する道を足す。あわせて、アバターの直径を話者ごと（と `display:` の既定）に指定できるようにする（§7）
> 決定事項:
> - 話者に `initial:` を足す。1〜2 文字（書記素クラスタ）を書ける。省略すれば、これまでどおり表示名の頭 1 文字
> - 字の大きさは、円の中の箱に収まる最大の大きさにする（上限は今の 200pt）。1 文字の見た目は変えない
> - ImageMagick に渡す字は、`@`・`%`・`\` を逃がしてから渡す
> - アバターの直径は話者ごとの `avatar_size:` で決める。`display.avatar_size:` は全話者の既定。単位は mm（`15` も `15mm` も受け付ける）。既定は 12mm のまま、雛形の `talk.yml` では似顔絵の 2 人に `avatar_size: 15mm` を書く（§7）
> 関連: `lib/vivlio_starter/cli/pre_process/talk_registry.rb`, `talk_avatar_generator.rb`, `config/talk.yml`, 原稿 22 章

## 0. 背景

簡易アバターは、表示名の頭 1 文字だけを描く（`talk-auto-avatar-spec.md` §5 で 2 文字を見送った）。1 文字では足りない場面が二つある。

- **頭の字が重なる**: 「佐藤」と「佐々木」、「未來」と「未央」は同じ字になる。色で見分けられるが、白黒で刷ると見分けられない
- **欧文の名前**: Albert Einstein は「AE」のほうが自然。表示名「アインシュタイン」から 2 文字を取ると「アイ」になり、意味のない切れ方をする

どの 2 文字がよいかは著者にしか決められないので、自動で 2 文字を取るのではなく、著者が指定する。

見送った理由（字が小さくなる・丸抜きで端が欠ける）は、2026-10-11 の試作で確かめた。字の大きさを固定すると、漢字 2 字は 200pt で円からはみ出し、140pt でちょうどよく、欧字 2 字は 200pt のままで収まる。字の種類で適した大きさが違うので、字の幅に合わせて大きさを決めれば両方が収まる（§2.2）。

## 1. 著者向け仕様

### 1.1 `initial:` を書く

```yaml
sato:
  name: 佐藤
  color: blue
  avatar: auto
  initial: 佐藤        # アバターに「佐藤」と入る

einstein:
  name: アインシュタイン
  color: navy
  avatar: auto
  initial: AE          # 表示名と違う字も書ける
```

- 1 文字または 2 文字。数え方は書記素クラスタ（絵文字や結合文字は 1 文字）
- 省略すれば、表示名の頭 1 文字（これまでどおり）
- 効くのは簡易アバターを作るときだけ。画像（`avatar: sato.webp`）を使う話者では使われない

### 1.2 書けない値

3 文字以上と空文字は 🟡 で知らせ、表示名の頭 1 文字で続ける。

```text
🟡 config/talk.yml: 話者 'einstein' の initial 'アインシュタイン' は 8 文字です。表示名の頭 1 文字で続行します。
        → initial: には 1〜2 文字を書いてください（例: initial: AE）
```

### 1.3 字の大きさ

円の中の箱（400px 四方の画像で幅 270 × 高さ 200px）に収まる最大の大きさで描く。上限は今の 200pt。

| 字 | 大きさ（試作の実測） |
|---|---|
| 遙（1 文字） | 200pt（今と同じ） |
| 佐藤・未央 | 136〜138pt |
| AE・Nb | 200pt |
| ゆう | 166pt |

## 2. 実装設計

### 2.1 `TalkRegistry`

- `Character` に `initial` を足す。既定は `nil`（省略時は今までどおり）
- `extract` で `initial` を読み、`validate_initial` で 1〜2 文字かを確かめる。外れたら 🟡 を出して `nil`

### 2.2 `TalkAvatarGenerator`

- `avatar_glyph(char)` は `char.initial` があればそれを、無ければ表示名の頭 1 文字を返す
- 1 文字なら、これまでどおり `POINTSIZE`（200）で描く。測らない
- 2 文字なら、200pt で一度描いた字の寸法（`-trim` 後の幅と高さ）を測り、箱に収まるよう比例で縮める: `min(200, floor(200 × min(270 / 幅, 200 / 高さ)))`。字の寸法は大きさにほぼ比例するので、測るのは 1 回で足りる
- 測る処理は `AvatarTools#measure` に置き、テストで差し替えられるようにする
- キャッシュキーは今の式のまま（字・地色・文字色・一辺・大きさ・フォント）。2 文字の大きさは字とフォントから決まるので、キーに字が入っていれば足りる。1 文字のキーは変わらないので、今あるキャッシュはそのまま使える

### 2.3 字を逃がす

`-annotate` に渡す字は、ImageMagick が次のように解釈する。

- 頭の `@`: その名前のファイルを読み、中身を描く（`@a` でファイル `a` の中身が描かれることを確かめた）
- `%`: 画像の情報の書式（`%w` は幅に置き換わる）
- `\`: 次の字を逃がす

描くときも測るときも、`\` → `\\`、`%` → `%%`、頭の `@` → `\@` と置き換えてから渡す。表示名の頭 1 文字（今の経路）にも同じ処理をかける。

## 3. テスト

1. `initial` の読み込み: 1 文字・2 文字・省略・3 文字以上（🟡＋`nil`）・空文字・絵文字（書記素クラスタで数える）
2. `avatar_glyph`: `initial` があればそれを使う
3. 字の大きさ: 1 文字は測らず 200、2 文字は測った寸法から比例で縮める、収まるなら 200 のまま
4. 字を逃がす: `@a`・`%w`・`\` を含む字
5. キャッシュキー: 1 文字のキーが今と同じ

## 4. 手順

1. 本仕様
2. `TalkRegistry` に `initial`＋テスト
3. `TalkAvatarGenerator` の字の選び方・大きさ・逃がし＋テスト
4. `config/talk.yml` のコメントと 22 章に `initial:` を書く
5. `rake test`、95 章で `initial:` を付けた話者の PDF を確かめる

## 5. スコープ外

- 3 文字以上: 箱に収めると字が小さくなりすぎる（2 文字の漢字で 136pt。3 文字なら 90pt 前後）
- 表示名から 2 文字を自動で取ること: 「アインシュタイン」→「アイ」のように、意味のない切れ方をする

## 6. 実装記録

- 大きさは試作どおりになった（実測: 佐藤 136pt・未央 138pt・ゆう 165pt・AE と Nb は 200pt）。比例で縮める 1 回の測定で、二分探索で求めた試作の値と 1pt 以内に収まる
- 測るときも `magick_text` で逃がす。逃がさずに測ると `%w` は書式に置き換わった後の幅を測り、描いた字と寸法が食い違う
- `Character` に足した `initial` は、`Data.define` の `initialize(initial: nil, **)` で既定を `nil` にした。字を指定しない組み立て（テストの `Character.new(key:, name:, …)`）はそのまま通る

## 7. アバターの大きさ（`avatar_size:`）

### 7.1 背景

アバターの直径は `components.css` で 12mm に決め打ちしている。「遙」のような 1 文字の簡易アバターには十分だが、描き込んだ似顔絵では表情が読み取りにくい。2026-10-12 に、雛形の 2 人の絵で 22 章の紙面を 12mm・15mm・18mm の 3 通りに組んで見比べた。

| 直径 | 顔の分かりやすさ | 紙面 |
|---|---|---|
| 12mm | 表情までは読み取りにくい | 1 行の吹き出しとほぼ同じ高さ |
| 15mm | 目と口がはっきり分かる | 会話 1 つあたり 3mm ほど伸びる |
| 18mm | いちばん見やすいが、1 行の吹き出しの横では絵が勝つ | 会話 1 つあたり 6mm ほど伸びる |

どの大きさが合うかは絵によって違い、著者が答えを持つ編集判断なので、設定にする（`config-key-criteria-guidelines.md` §3）。`custom.css` で `.talk-icon` を書き換えても変えられるが、名前を積む列の幅（`.talk-speaker`）も一緒に直さないと名前の折り返しが崩れる。2 か所をそろえる手間を著者に求めない。

### 7.2 著者向け仕様

```yaml
display:
  avatar_size: 12      # 全話者の既定（mm）。省略時は 12

haruka:
  name: 遙香
  avatar: haruka.webp
  avatar_size: 15mm    # この話者だけの直径。display の値より優先
```

- 単位は mm。単位を付けずに `15` と書いても、`15mm` と書いてもよい。`book.yml` と同じ読み方（`Units.length_to_mm`）なので、`1.5cm`・`42pt`・`60Q` も受け付けて mm に直す
- `em`・`%`・`px`、数でない値、0 以下は 🟡 で知らせ、既定の 12mm で続ける

```text
🟡 config/talk.yml: display.avatar_size '15em' は読めない大きさです。既定の 12mm で続行します。
        → 直径を mm で書いてください（例: avatar_size: 15 / avatar_size: 15mm）
```

- 話者ごとに書ける。似顔絵の話者と 1 文字の簡易アバターの話者が同じ本にいると、合う大きさが違う（似顔絵は 12mm では表情が読めず、1 文字は 15mm では大きすぎる）。本書でも、似顔絵の遙香・未來と簡易アバターのアインシュタイン・ボーアが同じ本にいる
- `display.avatar_size:` は全話者の既定。話者の指定が優先する。色（テーマ色が既定で、話者の `color:` が優先）と同じ構図
- ブロックごと（`:::{.talk avatar_size=…}`）には変えない。大きさは話者の絵に合わせて決めるもので、会話のまとまりごとに変える理由がない
- 話者の値が読めないときは、`display.avatar_size:`（無ければ 12mm）で続ける。警告にはどの話者かを添える
- 既定は 12mm のまま変えない。1 文字の簡易アバターには 12mm が合っているため。雛形の `config/talk.yml` では、記入例の 2 人（似顔絵）にだけ `avatar_size: 15mm` を書く
- Kindle はアバターを出さないので、影響しない

### 7.3 実装設計

- `TalkRegistry::TalkDisplay` に `avatar_size`（mm の Float。未指定は `nil`）を足し、`build_display` で `parse_avatar_size` を通す
- `TalkRegistry::Character` にも `avatar_size` を足す。読み方は `display` と同じ `parse_avatar_size`（警告に書いた場所と戻り先を添える）
- `BookSettingsCss` が、`display.avatar_size` があるときだけ `:root` に `--talk-icon-size: 15mm;` と `--talk-speaker-size: 17mm;`（直径＋2mm）を出す。話者の `avatar_size` は、その話者の発話に必ず付く `.talk-c-<key>` に同じ 2 つを置き、`:root` の値を覆う
- `components.css` の `.talk-icon` の幅と高さを `var(--talk-icon-size, 12mm)` に、`.talk-speaker` の幅を `var(--talk-speaker-size, 14mm)` にする。列の幅を `calc(var(--talk-icon-size) + 2mm)` にしないのは、Vivliostyle が `calc` と `var` の組み合わせを宣言ごと捨てることがあるため（`vivliostyle-css-pitfalls-notes.md`）。足し算は生成側で済ませる
- `.talk` の側では `--talk-icon-size` を宣言しない（宣言すると `:root` の値を覆い隠す）

### 7.4 テスト

1. `avatar_size` の読み込み: `15`・`'15mm'`・`'1.5cm'`・省略（`nil`）
2. 読めない値: `'15em'`・`0`・`'abc'` は 🟡 と `nil`
3. 生成 CSS: 指定があれば `--talk-icon-size: 15mm;` と `--talk-speaker-size: 17mm;`、無ければどちらも出さない
4. 話者ごと: 話者の `avatar_size` の読み込みと警告（どの話者か・戻り先）、`.talk-c-<key>` のルール（色を指定していない話者にも出す）

### 7.5 実装記録

- 名前を積む列の幅は、当初 `calc(var(--talk-icon-size, 12mm) + 2mm)` と書いた。Vivliostyle が `calc` と `var` の組み合わせを宣言ごと捨てる落とし穴（`vivliostyle-css-pitfalls-notes.md`）を避けるため、足し算は生成側（`--talk-speaker-size`）で済ませる形に改めた
- 22 章を `avatar_size: 15` で組むと、PDF に置かれた画像は 14.2mm 角になる。差の 0.8mm は両側の 1.5px の枠線のぶん（`.talk-icon` の直径は枠線を含む）
- 当初は `display.avatar_size:` だけ（本全体で 1 つ）にしたが、同じ本に似顔絵と 1 文字の簡易アバターがいると、どちらかに合わない大きさになることが分かり、話者ごとの `avatar_size:` を足した（2026-10-12）
- このリポジトリの `config/talk.yml`（雛形の元）では、遙香と未來に `avatar_size: 15mm` を書いた。22 章の 2 人は 15mm（画像 14.2mm）、95 章の簡易アバターは既定の 12mm（画像 11.2mm）で組まれることを PDF で確かめた
