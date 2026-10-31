# `vs config` 系のコマンド — 設定ファイルの書き方を引く

## 1. 目的

`vs --help` と `vs <コマンド> --help` でコマンドの使い方は引けるが、設定ファイルの書き方を引くコマンドは無かった。キーの説明は雛形の設定ファイルのコメントにあるのに、著者の手元のファイルからコメントを消していたり、キーの名前が分からなかったりすると、マニュアルを読むしかない。

設定の説明を引き、著者の今の値を添える。**読むだけで、どのファイルも書き換えない。**

## 2. コマンド

`vs index` と同じ形にする。`vs config` は下位のコマンドの案内だけを出し、仕事は `vs config:名前` が行う。今の形のまま `vs config catalog` と足すと、`vs config book` が `book.yml` の `book` 区分かファイルかを見分けられない。

| 書き方 | 出すもの |
| :--- | :--- |
| `vs config` | 下の 3 つの案内 |
| `vs config:book` | `book.yml` の 15 の区分の一覧と、引き方 |
| `vs config:book index` | そのキーの説明（子のキーも含む） |
| `vs config:book index.target_terms` | そのキーの説明・今の値・既定値 |
| `vs config:book 目次` | 言葉を含むキーの一覧。1 件だけならそのキーの説明 |
| `vs config:catalog` | `catalog.yml` の書き方と、この本の章立て |
| `vs config:talk` | `talk.yml` の書き方と記入例、この本の話者 |
| `vs config:talk display.style` | `display:` のキーの説明・今の値・既定値 |

3 つのファイルは形が違う。`book.yml` はキーと説明の表で、158 キーを引ける。`catalog.yml` はキーが 4 つしかなく、値はその本の章立てなので、雛形の値（本書の章立て）を見せても参考にならない。`talk.yml` も大半がその本の話者で、話者の項目（`name`・`color` など）はキーではなくコメントに書かれている。そのため、キーで引くのは `book.yml` と `talk.yml` の `display:` だけにし、ほかは**雛形の説明を見せ、値はその本のものを添える**。

区分と子を持つキーは区別しない。**値を 1 つ持つキーにだけ、今の値を添える。**

## 3. 説明の出どころ

gem に同梱した雛形の設定ファイル（`lib/project_scaffold/config/`）のコメントだけを読む。説明を別に持たないので、雛形とずれない。キーの一覧は YAML を読んだ結果（`ScaffoldLock.book_keys`）を正とし、行の解析はその行を見つけるためだけに使う。

1 つのキーの説明は、次の 3 か所のコメントを集める。

| 場所 | 例 |
| :--- | :--- |
| キーの行の末尾 | `target_terms: light # 索引語数の目安` |
| キーのすぐ下の、キーより深い字下げのコメント | `#   light … 少なめ` |
| キーのすぐ上の、キーと同じ字下げのコメント | `# ======= 索引設定 =======`（飾りは外す） |

一覧の 1 行の要約は、末尾のコメント → 上のコメント → 下のコメントの順で最初に見つかったものを使う。どれも無い子のキーは、親の要約を使う。

## 4. `vs config:book`

### 4.1 区分の一覧

上のコメントの見出しを区分の名前として並べる。

```
book.yml の設定

  book            書籍情報
  index           索引設定
  ...

区分やキーを指定すると、説明を表示します。言葉で探すこともできます。

  vs config:book index
  vs config:book index.target_terms
  vs config:book 目次
```

### 4.2 キー

雛形の行をそのまま、親のキーと見出しをつけて出す。`book.yml` へ写せる形にするため（`scaffold-update-notice-spec.md` §1.2 と同じ）。見出しも出すのは、`typography.body.font` のように、親の見出し（`# ------- 本文 -------`）でしか意味が分からないキーがあるため。`{{MAIN_TITLE}}` のような `vs new` の置き換え印は空にする。

```
index.target_terms

  # ======= 索引設定 =======
  index:
    target_terms: light # 索引語数の目安
                        #   light    … 少なめ（主要な語だけを拾う。既定）

今の値: standard（config/book.yml）
```

| 状態 | 今の値の行 |
| :--- | :--- |
| 書いてある | `今の値: standard（config/book.yml）` |
| 書いていない | `今の値: 書いていません（既定値: light）` |
| 書いていない・既定値が無い | `今の値: 書いていません` |
| 本の外・ファイルが読めない | 出さない |

`{ min: 1, max: 9 }` のように 1 行にまとめた子のキーは、自分の行が無いので親の行を出し、値はそのキーのものを出す。

### 4.3 言葉で探す

キーの名前と説明を、英字の大小を区別せずに探す。キーの名前の一部（`target_terms`）でも見つかる。

```
「目次」を含む設定（2 件）

  page.chapter_pagebreak  章・目次・部扉・付録・用語集・後書き・索引を、どちら側の面から始めるか
  page.toc_depth          目次にどの深さの見出しまで載せるか

キーを指定すると、説明と今の値を表示します。
```

### 4.4 廃止キー

雛形に無いキーは、`ConfigKeys` の廃止キーの案内を出す。廃止した区分の子（`vivliostyle.image`）も同じ。

```
index.max_sub_references は廃止されました
  副次参照の最大値は 8 で固定になりました
```

移したキーは移した先へ案内する。

```
output.cover は book.cover へ移りました
  巻ごとに表紙を変えられるよう、書名と同じ book: の下に置きます
  → vs config:book book.cover
```

### 4.5 見つからないとき

🔴 で止めて終了コード 1 を返す。綴りの近いキーがあれば、打ち直すコマンドを示す。無ければ `vs config:book` へ案内する。

```
🔴 「index.targt_terms」に当てはまる設定が見つかりませんでした
        → vs config:book index.target_terms
```

## 5. `vs config:catalog`・`vs config:talk`

`vs config:catalog` は、雛形の値の前後のコメントをそのまま出し、続けて著者の `catalog.yml` のコメントを除いた行を「この本の章立て」として出す。部も巻も書いたとおりに見える。雛形の値のすぐ上の `# 前書き` は値の見出しなので出さない。本の外では章立てを出さない。

`vs config:talk` は、雛形の頭から記入例の 2 人までを出し、続けて著者の `talk.yml` の話者を「この本の話者」としてキーと表示名で並べる。雛形の記入例の後の話者（95 章のアインシュタインなど）は本書のものなので出さない。キーで引くのは `display:` の下だけで、言葉で探すのも同じ範囲とする。話者は本ごとのものなので引かない。

| 状態 | 話者の行 |
| :--- | :--- |
| 話者がある | `この本の話者（config/talk.yml）` と一覧 |
| `talk.yml` に話者が無い | `config/talk.yml に話者が書かれていません` |
| `talk.yml` が無い | `この本には config/talk.yml がありません（会話文を使うときに作ります）` |
| 本の外 | 出さない |

YAML は `avatar: on` を真偽値に読むので、今の値は `on`・`off` の綴りへ戻す。既定値は `TalkRegistry::DEFAULT_DISPLAY` を読む。

## 6. 動く場所

本の外でも動く。`vs doctor` と同じくプロジェクトを要求しない（`RootCommand::PROJECTLESS_COMMANDS`）。`Common.ensure_configured!` を呼ばないので、廃止キーの 🟡 も出さない（`vs config:book` は廃止キーを調べるためにも使う）。

## 7. 検証

- 雛形の全区分に名前が付くこと、全キーを引けること（実物の雛形で確かめる）
- 今の値の 3 状態、1 行にまとめた子のキー、本の外
- 言葉で探す（複数件・1 件・0 件）、綴りの近いキーの提案
- 廃止キー・移したキー・廃止した区分の子
- 話者の 4 状態、`avatar` の綴り、記入例の後の話者を出さないこと
- 章立ての表示、雛形の値を出さないこと
- どのファイルも書き換えないこと
- 実際の 4 冊で、各コマンドを確かめる

## 8. 実装の記録（2026-10-31）

- 本体は `lib/vivlio_starter/cli/config_guide.rb`（`KeyGuide` を `Book`・`Talk` が継承し、`Catalog` は別）、コマンドは `samovar/config_command.rb`。
- 打ち間違いでも、キーの名前の一部なら言葉の検索で見つかる。`index.target_term` は 🔴 にならず、`index.target_terms` の説明が出る。
- 説明の無かった 4 キー（`book.subtitle`・`page.use`・`theme.ornament.image`・`metrics.labels.too_complex`）に、原本の `config/book.yml` でコメントを足した。`subtitle:` は行末にコメントを書くと `copy_to_scaffold.rb` の正規表現に合わず本書の副題が雛形へ漏れるので、上の行に書いた。
- 本の外の動きは、起動の入口の確かめ（`ensure_project_context!`）を通るので、コマンドを直接呼ぶテストでは確かめられない。`bin/vs` を子プロセスで走らせて確かめる。
- `one` を `options` より先に宣言すると、`--help` が引数として読まれる。`options` を先に書く。
