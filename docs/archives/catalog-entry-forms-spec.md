# catalog.yml の章の書き方を、名前と番号に絞る

> 状態: 実装済み（2026-10-21）
> 発端: 分冊対応（`multivolume-spec.md`）の作業中、雛形の `catalog.yml` の Tips を見直したときに、`CHAPTERS: 11, 21-23, 31` の形と `vs create` の食い違いが見つかった。
> 関連: `catalog-parser-unification-spec.md`（範囲を展開するよう直した経緯。本書でその書き方を廃止する）

## 1. 見つかったこと

`catalog.yml` の章は、次の 4 通りに書けた。試しの本で `vs create`・`delete`・`rename`・`renumber` を走らせて比べた。

| 書き方 | 例 | 組めるか | 章の管理コマンド |
| :--- | :--- | :--- | :--- |
| 名前 | `- 22-extensions` | 組める | すべて追随する |
| 番号 | `- 22` | 組める | `delete`・`rename`・`renumber` が追随しない |
| 範囲 | `- 21-23` | 組める | 追随しない |
| 一行の形 | `CHAPTERS: 11, 21-23, 31` | 組める | `create` が二つ目の `CHAPTERS:` を書き足す |

追随しないと、どれも ✅ で終わったまま、次のことが起きた。

- `vs delete 22` の後も `- 22` が残る。後で別の 22 番の原稿を作ると、黙って組まれる。
- `vs rename 22 28` の後、`catalog.yml` は `- 22` のままで、`28-extensions` が組まれなくなる。
- `vs renumber` の後、`catalog.yml` の番号は元のままで、原稿の番号だけが変わる。組まれる章がまったく別のものになる。
- 一行の形に `vs create` で章を足すと、ファイルの末尾に二つ目の `CHAPTERS:` ができ、YAML は後の値を採るので、前に書いた章が消える。

`catalog.yml` の行を書き換える `CatalogUpdater` は、項目を原稿の名前（`- 22-extensions`・`- 22-extensions.md`）でしか探していなかった。

## 2. 決めたこと

### 2.1 番号の項目は追随させる

`contents/24.md` のように番号だけの原稿を許しているので（すぐに書き始めたい著者のため）、番号の項目（`- 24`）も章の名前の一つとして扱う。

- `vs delete 22`: `- 22` の行を消す。
- `vs rename 22 28`: `- 28` に書き換える（番号の形のまま）。スラッグだけの改名（`22-extensions` → `22-plugins`）では、番号が同じなので変えない。
- `vs renumber`: 新しい番号に書き換える。1 章ずつ置き換えると、`--step 2` の 12→13・13→15 で `- 12` が 13 を経て 15 まで動くので、書き換える前の行を対応表と一度に照らす（`CatalogUpdater.rename_chapters`。`ChapterRename::FOLLOWERS` の `catalog.yml` を `batch: true` にした）。
- `vs create`: 今までどおり名前の形で、番号の順の位置に足す（番号と名前が混ざるが、どちらも正しい書き方）。
- 行末の注釈（`- 22   # 番号で指定`）は、項目の一部とみなさず、書き換えても残す。

### 2.2 範囲と一行の形は書けなくする

範囲は、消した章の番号が範囲に残り、改番すると中身がばらばらになるので、追随させられない。一行の形も同じで、`vs create` が書き足す場所もない。

- `catalog.yml` に書いてあれば、読み込み（`CatalogLoader.load_raw_catalog`）で 🔴 にして止める。分冊の巻の中・部の中も探す。
- 案内には、行番号と、そのまま写せる形を添える。範囲は、原稿のある番号を一つずつに開く（一つも無ければ範囲の番号すべて）。一行の形は、リストの形に直す。
- 一部の章だけを組む使い方は、`catalog.yml` を変えずに、`vs build 11 21-23` のようにコマンドの引数で範囲を指定する（コマンドの引数の範囲は今までどおり使える）。

```
🔴 config/catalog.yml に、番号の範囲か一行の形で書いた章があります。章の追加・削除・改番で書き換えられないので、書けなくなりました
  config/catalog.yml:3
    CHAPTERS: 11, 15, 21-23, 31
  → リストの形で、章を一つずつ書いてください:
    CHAPTERS:
      - 11
      - 15
      - 21
      - 22
      - 23
      - 31
一部の章だけを組むなら、catalog.yml は変えずに vs build 21-23 のように範囲を打てます
```

### 2.3 区分の無い目次の案内

区分（`PREFACE`・`CHAPTERS` など）を書かずに原稿を並べた `catalog.yml`（`- 00-preface`、`00-02`）は、もともと読めない。🔴 の文言が「形式が不正です（Hash ではありません）」だけだったので、著者の並びを番号で区分に分けた例を添える（`CatalogLoader.unsectioned_catalog_message`）。範囲は原稿の名前に開いてから分ける。前書きと本文の章をまたぐ範囲を一つの区分に置くと、区分で種類が決まるため本文の章まで前書きになるからである。`00-02` とだけ書いた目次は、必須ファイルの検査（`Common.ensure_required_yaml_files!`）で止まっていて `vs doctor --fix`（ファイルの作り直し）を勧めていたので、同じ案内に変えた。

## 3. 確かめたこと

- 試しの本で、番号だけの `catalog.yml` と名前で書いた `catalog.yml` に、`vs delete 22`・`vs rename 22 28`・`vs rename 22-extensions 22-plugins`・`vs create 16-appendix-notes`・`vs renumber`・`vs renumber --step 2` を走らせ、組まれる章が両者で一致した。
- 範囲・一行の形・部の中の範囲・巻の中の一行の形で、`vs build`・`vs create`・`vs preflight` が 🔴 で止まった（`vs create` は原稿を作る前に止まる）。
- 雛形の `catalog.yml` の Tips の例は、行頭の `# ` を外せばそのまま YAML として読める。
