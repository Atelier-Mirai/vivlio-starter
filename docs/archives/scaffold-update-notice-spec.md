# 雛形の更新を著者へ知らせる（改善案 #117・#118）

`vs upgrade` を実行しない著者は、雛形の CSS が新しくなったことも、`book.yml` に書ける設定が増えたことも知る手段が無い。`gem update` だけで済ませると、直ったはずの崩れが残り、新しい設定にも気づけない。

全章の `vs build` で「新しくなっている」と短く知らせ、`vs upgrade` で中身を見せる。

## 1. 著者から見た動き

### 1.1 全章のビルドの終わり（2 行）

```text
💡 雛形が新しくなっています（CSS: colophon.css ほか 3 件・book.yml の設定: 2 件）
        vs upgrade で確かめられます
```

- 片方だけなら、その片方だけを書く（`CSS: glossary.css`、`book.yml の設定: 2 件`）。
- ファイル名は並びの先頭の 1 件だけを書き、残りは「ほか N 件」にする。
- 🟡 にしない。原稿の場所を指す指摘ではなく、ビルドの結果も変えない（終了コードも変わらない）。

### 1.2 `vs upgrade` のいちばん最後

```text
💡 book.yml に書ける設定が 3 つ増えました（書かなくても既定値で動きます）
        使うときは、次の行を config/book.yml へ写してください

        theme:
          lead_size: 1.2 # 章リード文の文字の大きさ（本文に対する倍率・1.0〜2.0）
                         # simple の章・付録にも効く。image の章扉は frontispiece の lead_size で変えられる
        page:
          toc_depth: 3 # 目次にどの深さの見出しまで載せるか
                       # 1 … 章だけ
                       # 2 … 節（## 見出し）まで（ページ数を抑えたい本向け）
                       # 3 … 項（### 見出し）まで（既定）
                       # 付録は 3 でも節までです
```

- `book.yml` には書き足さない（`project-upgrade-command-spec.md` §1.3 は変えない）。
- 雛形の行をそのまま、親のキーをつけて並べる。そのまま写せる形にする。ドット区切りの `theme.lead_size` は YAML に写せない。
- キーの下の続きのコメントも一緒に並べる。選べる値の説明が多く、1 行目だけでは使えない。rc.3 から増えた 10 キーで 39 行になるが、知らせるのは 1 回だけなので長さは問題にしない。
- 親ごと増えたときは、親の下の行を丸ごと並べる。
- `section: { min: 400, max: 4000 }` のように 1 行にまとめたキーの一部が増えたときは、その行を並べる。
- 外部ツールの更新で流れないよう、`vs upgrade` の最後に出す。`--dry-run` でも出す。

## 2. いつ知らせるか

| 場面 | 知らせるか |
| :--- | :--- |
| `vs build`（全章）・`vs build upper`（巻） | 知らせる |
| `vs build all` | 全巻を組み終えた最後に 1 回 |
| `vs preflight`（全章）・`vs preflight upper`・`vs preflight all` | 知らせる |
| `vs build 11`・`vs preflight 11`（章の指定） | 知らせない |
| `vs build sample.md`（直接ビルド） | 知らせない |
| `config/scaffold.lock` が無い本 | 知らせない（判定できない） |
| lock の版が動いている gem より新しい本 | 知らせない（§4） |

章の指定で知らせないのは、執筆中に何度も打つコマンドで毎回 2 行出ると、読み飛ばす癖がつくため。全章を組むときに必ず出るので入稿前には届き、崩れやすい索引・用語集も全章のビルドでしか見えない。

ビルドが失敗したときは知らせない。原稿の問題を先に直してもらう。

## 3. 判定

判定は `ScaffoldUpdates` の 1 か所に置き、`vs build`・`vs preflight`・`vs upgrade` が同じものを見る。

### 3.1 CSS

`stylesheets/**/*.css` を、`vs upgrade` と同じ三者比較（`ScaffoldLock.classify`）で分類し、`:latest` 以外を「新しくなっている」とする。

見るのは CSS だけにする。雛形全体（7,755 件）のハッシュは約 4 秒かかるが、CSS の 27 件なら 2.5 ms で済む。`README.md` や `Gemfile` の変更は紙面に関係なく、知らせると本当に大事な知らせが埋もれる。

### 3.2 `vs upgrade` で断った競合

`vs upgrade` で断ったファイルは lock のハッシュが進まない（次回もう一度尋ねるため）。そのままだと、CSS に手を入れた著者には毎回のビルドで同じ 💡 が出続ける。

断ったときの雛形のハッシュを lock の `declined` に残し、雛形がそのハッシュのままなら知らせない。次に雛形が変われば、また知らせる。`vs upgrade` では今までどおり尋ねる。

### 3.3 `book.yml` の新しいキー

次の 3 つの条件をすべて満たすキーを「増えた」とする。

1. 今の雛形の `book.yml` にある
2. lock の `book_keys`（前回の雛形のキーの一覧）に無い
3. 著者の `book.yml` に無い

親ごと増えたときは親だけを数える。著者がまだ廃止キーを書いていて、`vs upgrade` が値を移す先のキー（`output.cover` → `book.cover`）は数えない。

#### 祖先の雛形を使わない理由

起票時は、共通祖先の雛形（`ScaffoldBase`）の `book.yml` と比べる案だった。ただ、`book.yml` は著者データなので `.cache/vs/scaffold-base/` に保存されず、手元の 2 冊にも無かった。古い gem の雛形は `gem cleanup` や Ruby の入れ替えで消える。

lock にキーの一覧を持てば、どちらにも頼らずに済む。

#### `book_keys` の無い古い lock

著者の `book.yml` に無いキーを、1 回だけすべて並べる。雛形のままの `book.yml` なら、並ぶのはちょうど新しいキーだけになる。`book.yml` を削って短くした本では長い一覧になるが、次の `vs upgrade` から出ない。

### 3.4 知らせが消えるとき

`vs upgrade` が lock を進めると消える（`--dry-run` と、確認で中止したときは進まない）。キーの一覧は 1 回だけ出す。書かないと決めたキーを毎回並べないためである。

## 4. lock の版が gem より新しい本

共著者が先に gem と雛形を更新した本を、古い gem で組むと、「雛形が新しい」の向きが逆になる。lock の版が動いている gem より新しければ知らせない。

## 5. `config/scaffold.lock`

```yaml
scaffold_version: 1.0.0
book_keys:
- book.author
- book.cover
- theme.lead_size
declined:
  stylesheets/glossary.css: sha256:…
files:
  stylesheets/glossary.css: sha256:…
```

- `book_keys`: 雛形の `book.yml` のキー（親も含む）。`vs new` と `vs upgrade` が書く。
- `declined`: `vs upgrade` で断ったファイルと、そのときの雛形のハッシュ。無ければ書かない。

## 6. 失敗しても止めない

知らせはビルドの後の案内なので、読み取りに失敗してもビルドの結果を変えない。`ScaffoldUpdates.report` の中で例外を受けて黙る（`--log=debug` で見られるようにする）。

## 7. 変えないこと

- `vs upgrade` が `book.yml` へキーを書き足すこと（§1.3 のまま）
- CSS 以外の雛形の知らせ
- gem 自体の新しい版の知らせ（ネットワークが要るので `vs upgrade` の担当のまま）

## 8. 確かめること

- テスト: CSS の分類（更新・競合・断った競合・次の更新で再び知らせる）、新しいキー（著者が書いた・わざと消した・親ごと増えた・移すキー・古い lock）、lock の読み書き、知らせの文面、`vs build all` で 1 回、章の指定で出ないこと。
- 実物: 試しの本で `vs build`・`vs preflight`・`vs upgrade --dry-run`・`vs upgrade` を通し、`vs upgrade` の後に知らせが消えること、`vs build 11` で出ないことを見る。

## 9. 実装記録（2026-10-31）

- `ScaffoldUpdates`（判定と知らせ）を足し、三者比較を `UpgradeCommands#classify_managed` から `ScaffoldLock.classify` へ移した。`vs upgrade` とビルドの知らせが同じ判定を見る。
- 雛形の `book.yml` の `metrics.compact.section.min` のように、`{ min: 400, ... }` と 1 行で書いたキーには自分の行が無い。実際の雛形の全キーを写すテストで見つかり、親の行を並べるようにした（同じ行は 2 度並べない）。
- `vs build all` は子のプロセスへ `VS_SKIP_SCAFFOLD_NOTICE` を渡し、親が全巻の後に 1 回だけ知らせる。
- `RetiredKeyRemover.block_range` を公開し、行の範囲の判定を共用した。
- 3 巻の試しの本で確かめた。章の指定（`vs build 11`・`vs build 11 21`・`vs preflight 11`）は 0 回、`vs build upper`・`vs build all`・`vs preflight` は 1 回。`vs upgrade --yes` で知らせが消え、`book.yml` は書き換わらない。`--dry-run` は一覧を出すが lock を進めない。競合を断ると、断った後のビルドでは知らせない。
- 4 冊（book_ai_web_starter・spiral-ruby・lives-computing・lives-mathematics）の写しで、CSS を rc.3 の雛形へ戻して確かめた。章の指定は 0 回、全章の `vs preflight`・`vs build` と巻の `vs preflight` は 1 回で、件数は `vs upgrade` と一致した（設定は 9・0・3・0 件、CSS は各 15 件）。取り込み後は 0 回。`book.yml` の変更は廃止キー `index.max_sub_references` の整理だけだった。外部ツールの更新は止めて実行した。
- 残り: 実際の本（spiral-ruby）では、雛形の同期の後に 4 件の CSS（`colophon.css`・`glossary.css`・`index.css`・`table.css`）が知らされるはずなので、次の `vs upgrade` の前に確かめる。
