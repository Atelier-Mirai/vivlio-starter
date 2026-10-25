# 分冊の本に、本全体の前書き・後書きを書けるようにする

> 関連: `multivolume-spec.md`（分冊。合本の構成は §4.3、全巻目次は §9）、`catalog-section-kind-spec.md`（区分で章の種類を決める）

## 0. 背景

分冊の本では、前書き・後書きを巻の中にしか書けない（`multivolume-spec.md` §3.3。一番上の `PREFACE` と `VOLUMES` を並べると 🔴）。
合本（巻を選ばない `vs build`）は、**最初の巻の `PREFACE`** と**最後の巻の `POSTFACE`** を使う（§4.3）。

spiral-ruby（全 6 巻）で、次の二つが困った（2026-10-26・ユーザー）。

- **合本に、第 1 分冊だけの前書きが入る。** 第 1 分冊の `PREFACE` は、シリーズ全体の話（00-about-this-book「本書について」・07-spiral-staircase「序章　螺旋階段を昇るように」・08-ruby-language「Ruby という言語」）と、第 1 分冊の話（01-volume-1「第1分冊について」）が混ざっている。合本はこれをそのまま冒頭に置くので、一冊の本の中に「第1分冊について」が残る。
- **本全体の後書きを書く場所が無い。** 巻ごとの後書き（次の巻への案内）は、巻に `POSTFACE` を書けば今でも置ける。ただ、合本は最後の巻の後書きを使うので、「第6分冊を終えて」のような巻の後書きと、本全体の結びを分けられない。

## 1. 指針

**本全体に属する前書き・後書きと、巻に属する前書き・後書きを、書き分けられるようにする。**
合本は本全体のものだけを、巻は自分のものを載せる。本全体のものは、本の始まる巻（最初の巻）と終わる巻（最後の巻）に載せる。

## 2. 要件

### R1: 本全体の前書き・後書きは、`VOLUMES` と同じ高さに書く

```yaml
PREFACE:                   # 本全体の前書き
  - 00-about-this-book
  - 07-spiral-staircase
  - 08-ruby-language
POSTFACE:                  # 本全体の後書き
  - 99-postface

VOLUMES:
  - name: 第1分冊
    id: vol1
    PREFACE:
      - 01-volume-1        # 第1分冊の前書き
    CHAPTERS:
      - 11-basics
      - 12-object-oriented
    APPENDICES:
      - 90-ruby-quick-reference
    POSTFACE:
      - 19-to-volume-2     # 次の巻への案内
```

- 一番上に書いてよいのは `PREFACE` と `POSTFACE` だけ。`CHAPTERS`・`APPENDICES` を一番上に書いたら、今までどおり 🔴 で止める（どちらが目次か決められない）。直し方の案内は「巻の中へ移す」のまま。
- 章の種類は区分で決まる（`catalog-section-kind-spec.md`）。一番上の `PREFACE` の原稿は前書き、`POSTFACE` の原稿は後書きとして組む（ノンブル・目次の扱いも同じ）。

### R2: 合本は、本全体の前書き・後書きを載せる

| | 本全体の前書き・後書きを書いた本 | 書いていない本 |
| :--- | :--- | :--- |
| 合本の前書き | 本全体の `PREFACE` だけ（巻の前書きは載せない） | 最初の巻の `PREFACE`（今まで） |
| 合本の後書き | 本全体の `POSTFACE` だけ（巻の後書きは載せない） | 最後の巻の `POSTFACE`（今まで） |

- 書いていない本を今までのままにするのは、上下巻の本（book_ai_web_starter の形）では、上巻の前書きがそのまま本全体の前書きを兼ねているため。新しい決まりだけにすると、こうした本の合本から前書きが消える。
- 前書きと後書きは別々に決める。本全体の `PREFACE` だけを書いた本は、合本の後書きに最後の巻の `POSTFACE` を使う。

### R3: 巻を選んで組むとき、本全体の前書きは最初の巻に、後書きは最後の巻に載せる

| | 最初の巻 | 途中の巻 | 最後の巻 |
| :--- | :--- | :--- | :--- |
| 前書き | 本全体の `PREFACE` → 巻の `PREFACE` | 巻の `PREFACE` | 巻の `PREFACE` |
| 後書き | 巻の `POSTFACE` | 巻の `POSTFACE` | 巻の `POSTFACE` → 本全体の `POSTFACE` |

- 巻が一つだけの本では、その巻が最初の巻でも最後の巻でもある。
- **2 巻目以降にも本全体の前書きを載せたいときは、その巻の `PREFACE` に書く**（2026-10-26 ユーザーと決定）。spiral-ruby の 00-about-this-book のように、別々に買った人がどの巻からでもシリーズの説明を読めるようにする原稿が当たる。巻の前書きは合本には載らないので、合本で二重にはならない。「本全体の前書きを全巻に載せる」設定は設けない（各巻に書けば足りる）。
- 同じ原稿が本全体の `PREFACE` と最初の巻の `PREFACE` の両方にあれば、一度だけ載せる（先に現れる本全体の側に残す）。後書きも同じ。

### R4: 原稿の検査・単章ビルド・全巻目次

- **原稿の検査**（`vs preflight`・`vs lint`・`vs metrics`）と章の種類の解決は、巻を選ばないとき全巻の原稿を見る（`multivolume-spec.md` §6.1）。本全体の前書き・後書きもここに含める。
- **単章ビルド**（`vs build 00`）: 本全体の前書きの原稿は最初の巻の、後書きの原稿は最後の巻の原稿として組む（R3 と同じ所属）。巻の前書きにも書いた原稿は、今と同じく最初に載せた巻で組む。
- **全巻目次**（`multivolume-spec.md` §9）: 本全体の前書きは最初の巻の前書きの頭に、後書きは最後の巻の後書きの後ろに並べる（R3 と同じ。読者がその巻を開けば、そこにある）。

### R5: 番号は変わらない

前書き・後書きは章番号を持たない。本文の章の番号（§5.1）・付録の記号（§5.2）は、本全体の前書き・後書きがあっても変わらない。

## 3. 実装の見取り図

- `Build::Volumes`:
  - 一番上の `PREFACE`・`POSTFACE` を読む `book_matter(catalog)` を足す（`{ 'PREFACE' => [...], 'POSTFACE' => [...] }`）。
  - 巻の目次に本全体のものを重ねる `sections_of(volume, volumes, catalog)` を足す（R3）。`view` の巻の選択・`basenames_of`・`containing`・`reading_order`・全巻目次は、`Volume#sections` を直接読まずにこれを通す。`Volume#sections` は巻に書いたものだけを持ったままにする（合本で巻の前書きを外すのに要る）。
  - `combined_sections`: 本全体の `PREFACE` があればそれ、無ければ最初の巻の `PREFACE`。`POSTFACE` も同じ（R2）。
  - `merged_sections`（巻を選ばないときの全巻の目次）に本全体のものを含める（R4）。
- `Guards::VolumeDefinitionCheck#mixed_sections_error`: `PREFACE`・`POSTFACE` は止めない。`CHAPTERS`・`APPENDICES` だけを挙げる。
- `CatalogLoader`: `VOLUMES` がある目次で、一番上の `PREFACE`・`POSTFACE` を一冊の本の目次として読まないこと（今は 🔴 で止めていたので、読む経路が通っていなかった）を確かめる。
- `CatalogUpdater`（`vs create`・`vs rename` などの目次の書き換え）: 一番上の `PREFACE`・`POSTFACE` の行も書き換えの対象に含める。
- `WholeTocGenerator`: R4 の並び。
- 文書: `contents/41-book-yml.md`「分冊にする」（今の「一冊の本の `PREFACE:` などは残さず、区分はすべて巻の中に書きます」を改める）、CHANGELOG、雛形の同期（`ruby scripts/copy_to_scaffold.rb`）。

## 4. テスト

- `Volumes`:
  - 合本: 本全体の `PREFACE` があれば、巻の前書きを載せない。無ければ最初の巻の前書き（今まで）。後書きも同じ。前書きと後書きを別々に決める。
  - 巻: 最初の巻は本全体の前書き → 巻の前書き、最後の巻は巻の後書き → 本全体の後書き。途中の巻には載らない。巻が一つの本。
  - 本全体と最初の巻の両方に書いた原稿が一度だけ載る。
  - 単章ビルドの巻（`containing`）: 本全体の前書きの原稿は最初の巻、後書きの原稿は最後の巻。
  - 巻を選ばないとき（原稿の検査）に、本全体の前書き・後書きが含まれる。
- `VolumeDefinitionCheck`: 一番上の `PREFACE`・`POSTFACE` は通り、`CHAPTERS`・`APPENDICES` は止まる。
- 全巻目次: 本全体の前書きが最初の巻の頭に、後書きが最後の巻の末尾に並ぶ。
- 実際の本で確かめる: spiral-ruby の目次を R1 の形に書き換え、合本と `--volume vol1`・`vol2`・`vol6` を組んで、前書き・後書きの並びを見る。
