# 不具合の報告と修正の依頼：コードブロックのファイル名（`ruby:…`）が、空白のところで切れる

> 作成日: 2026-11-19
> 報告元: 『遙香と未來のRPGプログラミング入門』（`~/projects/haruka_mirai`）の第10回を組んだときに気づいた
> 宛先: Vivlio Starter（`~/projects/vivlio-starter`）。`docs/specs/改善案.md` の #137 の詳しい報告（再現の手順・回避策の確かめ・直したあとの確かめ方）

## 137. コードブロックのファイル名（`ruby:…`）が、空白のところで切れる

- **対象**: コードブロックのファイル名の記法（`` ```ruby:hello.rb ``）・前処理（`markdown_transformer.rb`）・21 章「ファイル名（キャプション）の表示」
- **種別**: 不具合・実装・原稿
- **状態**: 対応済み（2026-11-19。直し方と確かめた結果は `改善案.md` の #137）

### 現状

ファイル名のあとに、どこを抜き出したかを添える書き方をすると、紙面ではファイル名が最初の空白で切れる。知らせは何も出ない。

````markdown
```ruby:field.rb（arrive に足したところ）
  elsif tile == "👸"
    to_battle(:demon_king)
```
````

| 原稿に書いた見出し | 紙面の見出し |
| :--- | :--- |
| `field.rb（arrive に足したところ）` | `field.rb（arrive` |
| `characters.rb（Hero に書いたところ）` | `characters.rb（Hero` |
| `light.html（body の中）` | `light.html（body` |

`vs lint`・`vs preflight` は、どちらも何も知らせない。ビルドの PDF を目で見るまで気づけない。

### 環境

| 項目 | 版 |
| :--- | :--- |
| vivlio-starter | 1.0.1（`vs --version`） |
| @vivliostyle/vfm | 2.7.2（`/opt/homebrew/bin/vfm`） |
| Ruby | 4.0.9 |
| OS | macOS（Darwin 27.0.0） |

### 再現の手順

VFM だけで再現する。次の Markdown を `t.md` に保存する。

````markdown
```ruby:field.rb（arrive に足したところ）
puts 1
```

```ruby:field.rb（arriveに足したところ）
puts 2
```

```ruby:"field.rb（arrive に足したところ）"
puts 3
```

```ruby title="field.rb（arrive に足したところ）"
puts 4
```
````

`vfm --partial t.md` の出力から、見出しを抜き出したもの。

```html
<figcaption>field.rb（arrive</figcaption>
<figcaption>field.rb（arriveに足したところ）</figcaption>
<figcaption>"field.rb（arrive</figcaption>
<figcaption>field.rb（arrive に足したところ）</figcaption>
```

1. 空白を含むと、切れる。
2. 空白がなければ、全部出る。
3. 引用符で囲んでも、切れる（引用符も見出しに残る）。
4. `title="…"` なら、空白を含んだまま全部出る。

### 原因

Vivlio Starter は、フェンスの情報文字列（`` ``` `` のあとの部分）を書き換えずに VFM へ渡している。VFM 2.7.2 は、情報文字列の最初の語（空白まで）だけを「言語名:ファイル名」として読み、空白より後ろを捨てる。CommonMark の情報文字列は、最初の語が言語名で、残りは処理系に任されている。このため、VFM の振る舞いとしては仕様の範囲内である。

Vivlio Starter の側の問題は、次の二つである。

- 21 章は「言語名に続けてコロンとファイル名を書く」とだけ説明している。空白を書けないことに触れていない。
- 空白を含む書き方を、lint も preflight も知らせない。

`` ```ruby:hello.rb `` のようなファイル名だけの見出しなら困らない。ところが入門書では、同じファイルの一部を何度も見せる。そのたびに「（arrive に足したところ）」のような説明を添えたくなり、そこに空白が入る。

### 影響の範囲

haruka_mirai の原稿で、`` ```言語名:… `` の見出しは 174 か所ある。そのうち空白を含んで切れているものが 30 か所あった（2026-11-19、`contents/*.md` を `grep -E '^ *(```|~~~)[A-Za-z0-9_+-]+:[^ ]+ +[^ ]'` で数えた）。

| 章 | 切れている見出し |
| :--- | ---: |
| 16-hero-and-monsters | 1 |
| 17-walk-the-world | 4 |
| 18-adventure-book | 6 |
| 19-one-world | 6 |
| 20-battle-of-light | 13 |

ほかの本（`~/projects` の下の各書籍）は数えていない。

### 今すぐ使える回避策（確かめたもの）

haruka_mirai の 20 章の写しで、2 か所を `title="…"` に書き換え、`vs build 20` で組んだ。

````markdown
```ruby title="characters.rb（Hero に書いたところ）"
  # id の技に使う MP。叡智の冠があれば、半分ですむ
  def mp_cost(id)
```
````

- 見出しは「characters.rb（Hero に書いたところ）」と、最後まで組まれた（PDF の文字と紙面で確かめた）。
- 行番号と色付けは、`ruby:…` のときと変わらない。
- `vs lint 20` と `vs preflight` に、新しい指摘は出なかった。

ほかに、次の二つの方法もある。どちらもおすすめしない。

- 空白の代わりに、改行しない空白（U+00A0）を入れる。VFM の出力では最後まで出る。ただし、目で見て区別できず、原稿の検索や置き換えで間違えやすい。
- 空白を書かない（「arriveに足したところ」）。この本の決まり（英字とひらがなのあいだに空白。`vs lint` の hiragana-spacing）に反する。

### 提案

- **A. 前処理で、空白を含む `言語名:見出し` を `言語名 title="見出し"` に書き換えてから VFM へ渡す。**
  - 対象は、開きフェンスの情報文字列が `言語名:` で始まり、行の残りに空白を含むものだけ。`` ```ruby:hello.rb `` のような空白のない見出しは今までどおりにし、組み上がりを変えない。
  - 見出しの中の `"` は `&quot;` にするか、`\"` で逃がす（VFM がどちらを受けるかは確かめていない）。
  - 開始行のマーカー（`prime.rb#L22-L25`。`PrismLines::START_LINE_MARKER_PATTERN`）は、書き換えたあとも figcaption の文字の末尾に届けばよい。`title="prime.rb（抜粋）#L22-L25"` で、今と同じように消費されるかを確かめる。
  - `include:` が作るフェンス（`markdown_transformer.rb` の `` "```#{language}:#{original_path}#{line_marker}" ``）は、パスに空白がなければ影響しない。パスに空白があるときの扱いも、同じ規則で決める。
  - 記法の見本（```` ```markdown ```` の中のフェンス）は書き換えない。最上位のフェンスだけを対象にする（`:::{.terminal}` の変換と同じ考え方）。
- **B. 書き換えないなら、lint で知らせる。** 情報文字列が `言語名:` で始まり、空白を含むものを 🟡 にし、`言語名 title="…"` に直す方法を添える。A を入れたあとも、`--fix` で `title="…"` に直す規則としてなら使える。
- **C. 21 章「ファイル名（キャプション）の表示」に書き足す。** 説明を添えたいときの書き方（A を入れたなら「空白も書ける」、入れないなら `title="…"`）を、表示例と並べる。

A を入れれば、既存の本（haruka_mirai の 30 か所）は原稿を書き換えずに直る。A ができるまでは、B だけでも、組む前に気づける。

### 問い

- ユーザーの意向（2026-11-19）: haruka_mirai の原稿は `title="…"` に書き換えず、そのままにする。Vivlio Starter の修正（A）で、原稿を直さずに見出しが最後まで出ることを期待している。

- A・B・C のどれにするか（組み合わせるか）。
- VFM の `title="…"` は、2.7.2 で振る舞いを確かめただけである。文書に載った仕様かどうかを確かめるか。VFM に、`言語名:見出し` で空白を受けるよう要望を出すか。
- 2.0（`vivlio-starter-v2`）でも同じ前処理を通すか。

### 確かめ方（直したあと）

- 上の「再現の手順」の 4 つに、次の 2 つを足して、`vs build` で組んだ PDF の見出しを比べる。
  - `` ```ruby:prime.rb（抜粋）#L22-L25 `` … 行番号が 22 から始まり、見出しに `#L22-L25` が残らない。
  - `` ```ruby:a "b" c `` … 引用符が見出しに残る。
- haruka_mirai の 16〜20 章を、原稿を書き換えずに組み、30 か所の見出しが最後まで出ることを確かめる。
- 空白のない見出し（`` ```ruby:hello.rb ``）と、`include:` で取り込んだコードの組み上がりが変わらないことを確かめる。
