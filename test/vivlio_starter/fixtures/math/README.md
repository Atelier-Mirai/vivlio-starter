# 数式表示チェック（Kindle 実機確認用）

`math-check.md` は、数式が各ターゲットで正しく運ばれているかを**実機で**確かめるための検査ページです。
仕様 `plain-math-notation-spec.md` §3-2 の経路表の各マスを 1 つずつ踏むように並べてあります。

## 使い方

出力形式は `config/book.yml` の `output.targets` で決まります（`vs build` に形式を渡す
オプションはありません。`vs build <targets...>` の `targets` は**章の指定**です）。

```bash
cp test/vivlio_starter/fixtures/math/math-check.md contents/97-math-check.md

# config/catalog.yml に 97 を追加する（catalog に無い章は弾かれる）
# vs は導入済み gem を使うので、リポジトリの変更を反映するには必須
rake reinstall

# config/book.yml を編集して出力形式を選ぶ
#   output:
#     targets: kindle        … Kindle だけ
#     targets: pdf, kindle   … PDF も一緒に見る
vs build

# Kindle Previewer 3 で開き、文字の大きさを最小⇔最大に振る

rm contents/97-math-check.md   # book.yml の targets も元へ戻す
```

## 何を確かめるページか

| 節 | 経路 | Kindle での期待 |
| :--- | :--- | :--- |
| 1-1 | `MathTextRenderer` が通る | HTML テキスト（変数が斜体・真の上付き）。**追従する** |
| 1-2 | 通らない＋素の表記で書かれた | 著者の原文テキスト。**追従する** |
| 1-3 | 通らない＋LaTeX で書かれた | SVG 画像。追従しない（既知の制限） |
| 2 | ディスプレイ数式 | PNG 画像。組版を保つ |
| 3 | バッククォート判定 | 数式として組まれる |
| 4 | 判定の誤爆 | **すべて等幅のコードのまま**（数式になっていたら不合格） |
| 5 | 日本語を含む数式 | 本文と同じ書体で出る（PDF は Type 3 が増えないこと） |
| 6 | 表セル内の数式 | 上付きが出て行の高さが崩れない |

## PDF 側も見るとき

`output.targets` に `pdf` を入れてビルドし、Type 3 フォントが増えていないことを確かめます。

```bash
pdffonts <出力.pdf> | grep -c "Type 3"
```

日本語を含む数式（5 節）は `SvgFontEmbedder` がサブセット書体を SVG へ埋め込むので、
**Type 3 は増えないのが正解**です。増えていれば書体の解決に失敗しています
（`type3-font-embedding-notes.md` §3 の手順で `FontDescriptor.FontName` を見る）。

## 現在の内訳（2026-08-20 実測）

インライン 24 件・ディスプレイ 10 件の数式画像が生成され、内訳は
1-1 が 5 件・1-2 が 15 件・1-3 が 4 件・ディスプレイ 10 件。
日本語を含む SVG 3 件はすべてサブセット書体を抱いている（埋め込み漏れ 0）。
