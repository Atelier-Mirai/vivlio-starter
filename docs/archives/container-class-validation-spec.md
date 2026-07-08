# `:::` コンテナ検証 仕様書（`vs preflight` ガード）

## 目的

`:::{.class}` 記法の二つの構造的欠陥を、`vs preflight` のガードで検出する。

1. **開閉バランス** — `:::` の開始と終了の数が合わないと、`<div>` が閉じずに以降の本文が枠の中へ飲み込まれる。`CodeFenceCheck`（``` の数を数えるガード）と同じ問題であり、同じ解法で防げる。
2. **未知クラス名** — `:::{.notice}` を `:::{.notion}` と打ち間違えても、無言で `<div class="notion">` が生成され、CSS が当たらないまま素の段落として組まれる。著者は完成 PDF を目視するまで気づけない。

`terminal-literal-spec.md` の実装より前にこれを片付ける。`.terminal` の経路変更を入れる前に、コンテナの検証点を確立しておくため。

## なぜ黙殺されるのか — `:::{.class}` の二経路構造

`:::{.class}` の div 化には二つの経路がある。この非対称が黙殺の原因である。

### 経路 A — Ruby 前処理（`MarkdownTransformer.convert_container_blocks`）

対象は **6 クラスのみ**: `book-card` / `table-rotate` / `long-table` / `text-right` / `text-center` / `text-left`。

Markdown 段階で `<div>` を作る。CommonMark では生の `<div>` の中身は HTML ブロックとして素通しされ Markdown 解釈されないため、`render_markdown_to_html`（kramdown）で**中身を自前で HTML 化**している。`scale=` / `shift-y=` のような**属性トークンを解釈できるのはこの経路だけ**。

### 経路 B — 汎用正規表現（`config/post_replace_list.yml:33`）

```yaml
- f: ":{3,}\\s*\\{\\.?([a-z0-9.\\-_\\s]+)\\}"
  r: <div class="$1">
# …
- f: ":{3,}"
  r: "</div>"
```

上記以外の**すべて**。原稿での使用実績は `section-lead` 89 / `column` 36 / `chapter-lead` 29 / `note` 25 / `tip` 11 / `output` 9 / `notice` 7 / `memo` 6 / `terminal` 2 … と、こちらが圧倒的多数。

`:::` を生テキストのまま VFM に通して**中身を通常の Markdown として組ませ**、HTML 生成後に残った `:::{.class}` を `<div>` へ置換する。`normalize_container_fences!`（`:::` 前後への空行補完）と `post_replace_list.yml:146-154` の `<p><div …>` 剥がし群は、この経路の後始末。

**経路 B はクラス名も開閉の対応も一切知らない。** 開始行は正規表現の文字クラス `[a-z0-9.\-_\s]+` に合致すれば何でも `<div>` になり、残った `:::` は一律 `</div>` になる。ゆえに検証は原稿の Markdown 段階で行うほかない。

## 設計 — 二つのガードとして実装する

`CodeFenceCheck` の前例に倣い、`lib/vivlio_starter/cli/guards/` に置く。`vs preflight` の `Guard.run!` に登録する（`preflight_command.rb:69-78`）。`vs build` では走らない。`CodeFenceCheck` も preflight 専用であり、構造チェックの置き場としてこれが本リポジトリの慣行である。

| ガード | 重大度 | 内容 |
|---|---|---|
| `ContainerFenceCheck` | `:error`（停止） | `:::` の開閉バランス。閉じ忘れ・過剰な閉じ |
| `ContainerClassCheck` | `:warn`（警告のみ） | 未知のクラス名。修正候補を提示 |

### 前処理ではなくガードに置く理由

当初は `MarkdownPreprocessor` のステップとして設計したが、ガードの方が明確に優れる。

- **行番号がそのまま正確**。ガードは `contents/*.md` を生で読む。前処理段階では `apply_frontmatter!` が行を挿入済みで、`LinkImageValidator.correct_line_number` 相当の補正機構が必要になる。それが丸ごと不要になる。
- **`Masking.protect_code` を使わずに済む**。同メソッドはフェンスをプレースホルダ 1 個へ畳むため**行番号がずれる**。さらに `Masking::INLINE_CODE_SPAN` は `/m` 付き（`.` が改行にマッチ）なので、孤立したバッククォート対が複数行を丸ごと飲み込むことがある。**行番号を要する検査には使えない**（本仕様の検討中に実測で確認。`protect_code` 経由で数えると `contents/41-book-yml.md` が「閉じ忘れ 1 個」と誤検出されたが、実際は 3 開 3 閉で均衡していた）。
- **早期に止まる**。パイプラインを回す前に構造の破綻を報告できる。

### 共有スキャナ

両ガードは同一の走査を必要とするため、`Guards::ContainerScanner`（モジュール関数）に切り出す。

走査の中核には **`Masking.each_prose_line`（`masking.rb:43`、公開済み）** をそのまま使う。同メソッドは「コード（フェンス区切り行・フェンス内容行）を除いた地の文の行だけを、テキスト全体に対する通し行番号つきで yield する」もので、本ガードの要件と完全に一致する。`Masking` は「Markdown のコード領域解釈の**唯一の実装**」を掲げており、フェンス判定を自前で持たないこと。

（`Masking` の内部状態機械 `scan_lines` は `private_class_method` で閉じられているが、用途別の公開 API が (a) `each_prose_line` / (b) `strip_code` / (c) `protect_code` の 3 つ用意されており、本ガードの用途 (a) は既に公開済み。**`Masking` 側への変更は不要**。）

`each_prose_line` に加えて、スキャナ側で **HTML コメント内**（`<!-- … -->`）をスキップする。`contents/22-extentions.md` の会話文 TODO に `:::{.talk}` が眠っているため。

yield する情報: `行番号` / `種別（:open / :close）` / `クラス名の配列` / `属性トークンの配列`。

判定の詳細:

- 行頭判定は `lstrip` 後に行う（`CodeFenceCheck` と同様。インデントされた `:::` も経路 B では div になる）。
- `/\A:{3,}\s*\{(.*)\}/` にマッチすれば `:open`、`/\A:{3,}\s*\z/` なら `:close`。
- `{…}` の中身は空白区切り。先頭の `.` は任意（`{.a .b}` / `{a}` の両方が経路 B で通る）。
- `key=value` 形（`scale=60%` / `shift-y=20%`）は**属性**として分離し、クラス名として扱わない。

### `ContainerFenceCheck`

深さ（depth）を追う。

- `:open` で +1、`:close` で −1。
- depth が**負**になった時点で「過剰な閉じ」。その行番号を報告する。
- 走査終了時に depth が**正**なら「閉じ忘れ」。未閉鎖の開始行の行番号を報告する。

重大度は `:error`（`CodeFenceCheck` と同じ理由 — ビルドしても意図通りにならない）。

現行 26 ファイルは**すべて均衡**していることを実測で確認済み（open 合計と close 合計が全ファイルで一致）。導入しても既存原稿は素通りする。

### `ContainerClassCheck`

`:open` のクラス名を許可リストと照合し、未知なら警告する。

#### 許可リストの供給源

**`stylesheets/**/*.css` からクラスセレクタを自動抽出する**ことを主とする。`stylesheets/custom.css` が著者の自由記述用に用意されているため、「**クラスに CSS を書けば自動的に許可される**」という自己完結した規則が成立する。明示リストを主にすると、著者は CSS と許可リストの二箇所を編集することになり、`PLANNED.md` の会話文記法の項で問題視されているのと同じ二重編集を招く。

実データでの妥当性（2026-07-08 実測）:

- CSS 定義クラス **187 種** / 原稿で使用中の `:::` クラス **32 種**
- 32 種のうち CSS に無いのは **3 つだけ**で、いずれも**偽陽性**だった:

| 箇所 | 文脈 | スキャナ側の対処 |
|---|---|---|
| `contents/22-extentions.md:12` `:::{.クラス名}` | ` ```markdown ` フェンス内 | フェンス内スキップ |
| `contents/31-lint.md:212`, `contents/93-import.md:56` `` `:::{.class}` `` | インラインコード（行頭ではない） | 行頭アンカーで自然に除外 |
| `contents/22-extentions.md:583` `:::{.talk}` | `<!-- -->` コメント内（会話文 TODO） | HTML コメント内スキップ |

経路 A の 6 クラスも全て CSS に存在するため、CSS 抽出だけで拾える。補助として次を合流させる:

- 経路 A のクラス（Ruby 側にハードコード）。CSS 抽出と重複するが、CSS 削除時の安全網として明示する。
- `book.yml` の `preflight.allowed_classes: []`（CSS を書かない著者定義クラス、将来の `talk` など）。

**過剰許可は許容する。** 抽出結果には Prism のトークンクラス（`token` / `keyword` …）等、コンテナに使えないクラスも混ざる。しかし過剰許可が生むのは**偽陰性のみ**（`:::{.token}` を見逃す）で、偽陽性は生まない。目的はタイポ検出であり、`.notion` のような打ち間違いは CSS のどこにも存在しないため確実に捕まる。網を狭めるのは実害が出てからでよい。

#### 警告メッセージ

`warning-messages-actionable` の方針に従い、出現箇所と修正候補を必ず添える。

**行番号を持つ警告は `path:line - 内容` の形にする。** 既存メッセージには 2 つの流儀があり、ファイル単位のガード（`CodeFenceCheck` / `ImageFilenameCheck`）は `〜が…ています: path`、行番号を持つ前処理 validator（`LinkImageValidator`）は `path:line - 〜を検出しました` を使う。本ガードは行番号を持つため後者に倣う（端末でクリックして該当行へ飛べる）。

```
🟡 contents/22-extentions.md:134 - 未知のコンテナクラス '.colunm' を検出しました
   現状: :::{.notice .colunm}
   候補: :::{.notice .column}
   → CSS が当たらないため、枠が付かず素の段落として組まれます
   → 意図したクラスであれば stylesheets/custom.css に定義を追加するか、
     config/book.yml の preflight.allowed_classes に追加してください
```

`現状:` / `候補:` は `URL:` / `フェンス行:` と同じデータ行の流儀。候補は誤りのクラスだけを差し替えた開始行の形で示し、複数クラスでもそのまま貼り替えられるようにする。候補が得られない場合は `候補:` 行を省く。

`ContainerFenceCheck` は `CodeFenceCheck` の括弧書き（`（7 個＝奇数）`）に倣い、開始・終了の個数を添える。

```
🔴 コンテナ記法（:::）の開始と終了の数が合いません（開始 4 個 / 終了 3 個）: contents/41-book-yml.md
   → 21 行目の :::{.column} が閉じられていません。対応する ::: を追記してください
   → コード例の中で ::: 自体を示す場合は、フェンス（```）で囲めば数えられません
```

#### 修正候補の求め方

stdlib の `DidYouMean::SpellChecker#correct` の結果を**そのまま**使い、`MAX_SUGGESTIONS = 3` 件で打ち止める。独自の並べ替えは行わない。

`correct` の実装（`did_you_mean/spell_checker.rb`）は次のとおりで、**レーベンシュタイン距離は既に足切りとして組み込まれている**。

```ruby
words.sort_by! { |word| JaroWinkler.distance(word.to_s, normalized_input) }
words.reverse!                                  # ← 並び順は Jaro-Winkler 降順
threshold   = (normalized_input.length * 0.25).ceil
corrections = words.select { Levenshtein.distance(...) <= threshold }  # ← 足切り
```

編集距離の昇順で並べ替え直すと、かえって悪化する。`colunm` に対し `column` と `col-num` は**ともに編集距離 2** で同点となり、辞書順のタイブレークで `col-num` が先に出る。Jaro-Winkler は共通接頭辞を重く見るため `column` を正しく先頭に置く（実測）。

ただし `SpellChecker#sort_by!` は安定ソートではないため、辞書（`Dir.glob` 由来）の順序が環境依存だと同点時の候補順がぶれる。`known_classes` は `sort` して決定的にする。

#### 重大度

`:warn` に留める（`Guard.run!` は `:warn` では停止しない）。著者が「CSS を書く前に原稿を先に書く」順序を妨げないため。CI で落としたい要求が出たら `vs preflight --strict` を後付けする。

## 実装

| ファイル | 内容 |
|---|---|
| `lib/vivlio_starter/cli/guards/container_scanner.rb` | 新規。共有の行スキャナ |
| `lib/vivlio_starter/cli/guards/container_fence_check.rb` | 新規。開閉バランス（`:error`） |
| `lib/vivlio_starter/cli/guards/container_class_check.rb` | 新規。未知クラス（`:warn`）。CSS 抽出はメモ化 |
| `lib/vivlio_starter/cli/guards.rb` | 上記 3 つを require |
| `lib/vivlio_starter/cli/samovar/preflight_command.rb` | `Guard.run!` に 2 ガードを登録（`CodeFenceCheck` の直後） |
| `config/book.yml` | `preflight.allowed_classes: []` を追加 |

CSS 抽出の詳細:

- `stylesheets/**/*.css` を読み、コメント `/* … */` と文字列リテラルを除去してから走査する（`content: ".foo"` を誤って拾わないため）。
- 小数（`0.5em`）や `nth-child()` を誤検出しないよう `(?<![\w.\-])\.([a-zA-Z_][\w-]*)` を用いる。
- プロセス内で一度だけ構築しメモ化する。

`config/book.yml` は **root で編集し `ruby copy_to_scaffold.rb` で scaffold へ同期する。** `Common::CONFIG` は再帰的 Data ラッパーのためスキーマ変更は不要。

## テスト

`test/vivlio_starter/guards/container_scanner_test.rb`

- フェンス内（``` / `~~~`、4 連含む）の `:::` を yield しないこと。
- `<!-- … -->` 内の `:::` を yield しないこと（単一行・複数行の両方）。
- 行頭でない `` `:::{.class}` `` を yield しないこと。
- `::: {.a .b}`（`:::` と `{` の間に空白）を 2 クラスとして分解すること。
- `:::{.table-rotate scale=60%}` の `scale=60%` を属性として分離すること。
- インデントされた `:::` を拾うこと。

`test/vivlio_starter/guards/container_fence_check_test.rb`

- 均衡した原稿で違反ゼロ。
- 閉じ忘れ（末尾 depth > 0）を `:error` で検出し、未閉鎖の開始行番号を示すこと。
- 過剰な閉じ（depth < 0）を `:error` で検出し、その行番号を示すこと。
- 入れ子（`:::{.column}` の中に `:::{.note}`）が正しく均衡と判定されること。

`test/vivlio_starter/guards/container_class_check_test.rb`

- `:::{.notion}` を `:warn` で検出し、`path:line - …` の形で候補 `.notice` を提示すること。
- `:::{.notice}` / `:::{.column}` は警告しないこと。
- 複数クラス `:::{.img-text .align-center}` の各々を照合すること。
- 複数クラスのうち誤りのものだけを候補で差し替えて示すこと（`:::{.notice .colunm}` → `:::{.notice .column}`）。
- 複数候補が Jaro-Winkler 降順（`column`, `col-num` の順）で並ぶこと。
- 属性トークン `scale=60%` を照合対象にしないこと。
- `preflight.allowed_classes` に追加したクラスを警告しないこと。
- 候補が無い場合に `候補:` 行を出さないこと。

回帰確認として、現行 `contents/` 全章に `vs preflight` を実行し、**新規の警告・エラーがゼロ**であること（上記の実測に基づく）。

## 非目標

- **`vs build` での実行**。`CodeFenceCheck` に倣い preflight 専用とする。
- **CSS に存在するがコンテナとして無意味なクラスの排除**（Prism トークン等）。過剰許可は偽陰性のみを生むため許容する。
- **`ContainerClassCheck` の終了コードへの反映**。上記のとおり警告に留める。
- **閉じ `:::` に対する開始クラスの対応検証**（`:::{.a}` を `:::{.a}` で閉じる記法）。経路 B は閉じ側のクラス名を解さない。
