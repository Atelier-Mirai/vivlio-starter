# 不具合修正の検証

この章は、CHANGELOG「既知の不具合」3件の修正を確認するための検証用ページです。
確認が済んだら、`contents/89-bugfix-check.md` と `images/89-bugfix-check/` を削除し、`config/catalog.yml` から `89-bugfix-check` の行を取り除いてください。

## 検証1: sideimage 内リンクの脚注

**期待される結果**: 次の2つの sideimage 内のリンクから生成される脚注URLが、このページの下部に**各1回ずつ**・**番号順**に表示されること（以前はセクション末尾にブロック表示され、さらに同じURLが複数回表示されることがありました）。

:::{.sideimage-right}
![](Einstein.png){width=20%}

Vivlio Starter のコアエンジンは [Vivliostyle](https://vivliostyle.org/) です。CSS 組版という優れた技術により、Markdown から美しい PDF を生成できます。この文章は画像の左側に回り込みます。
:::

:::{.sideimage}
![](Einstein.png){width=20%}

開発のきっかけとなったのは [Re:VIEW Starter](https://kauplan.org/reviewstarter/) です。執筆者が執筆に集中できる環境づくりという思想を受け継いでいます。
:::

比較用に、通常の段落内のリンクも置いておきます。[アトリヱ未來](https://atelier-mirai.net/) のサイトでは各種講座を開催しています。この脚注も同様にページ下部に1回だけ表示されるはずです。

## 検証2: テーブル内リンクの脚注

**期待される結果**: テーブルのセル内のリンクから生成される脚注URLが、参照1つにつきページ下部に**1回だけ**表示されること（以前は同じ脚注が3回など複数回表示されていました）。また、各脚注の内容が**直前のリンクのURLと一致**していること（VFM にはテーブル内脚注の定義内容が入れ替わる不具合があり、ビルド時に自動修復されます）。

| 症状 | 解決策 |
|------|--------|
| `brew` が見つからない | [brew.sh](https://brew.sh) を参照 |
| Homebrew を再インストールしたい | 同じく [brew.sh](https://brew.sh) を参照 |
| Node.js が見つからない | [nodejs.org](https://nodejs.org/) を参照 |

## 検証3: 画像の配置（align=left / center / right）

**期待される結果**: 3枚の画像が上から順に「左寄せ」「中央」「右寄せ」で**縦に並ぶ**こと。以前は `align=left` の float に後続の画像が巻き込まれ、中央の画像が中央に来ない・右寄せの画像が本文を巻き込むなど、レイアウトが連鎖的に崩れていました。

![](Einstein.png){width=30% align=left}

![](Einstein.png){width=40% align=center}

![](Einstein.png){width=30% align=right}

この段落は3枚目（右寄せ）の画像の左側に回り込みます。左右配置のテキスト回り込みは従来どおりの意図された動作です。

### テキストの回り込み

![](Einstein.png){width=30% align=left}

この段落は `align=left` の画像の右側に回り込むことが期待されます。回り込みは意図された動作ですが、次の見出しや次の画像には影響を与えません（見出しには `clear: both` が効いています）。

### キャプション付き図版の混在

**左寄せの図 @fig-left**

![](Einstein.png){width=30% align=left}

**中央の図 @fig-center**

![](Einstein.png){width=40% align=center}

**右寄せの図 @fig-right**

![](Einstein.png){width=30% align=right}

すべての図版のあとに続く本文です。@fig-left と @fig-center と @fig-right の3つを参照しても、相互参照リンクは正しく機能します。
