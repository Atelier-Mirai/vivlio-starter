# images/characters/ — 会話文の話者アバター

会話文記法 `:::{.talk}` で表示する話者アバターをここに置きます。

- ファイル名は `config/talk.yml` の各話者の `avatar:` で指定します。
  例: `avatar: sensei.webp` → `images/characters/sensei.webp`
- 対応形式は `.webp` / `.png` / `.jpg`（`.webp` を推奨）。
- 正方形（1:1）の画像を推奨します。表示時に丸く切り抜かれます。
- アバターは PDF / クリーン EPUB でのみ表示されます。Kindle では
  自動的に「名前：発話」の 1 段落へ組み替わります（アバターは非表示）。

アバターを指定しない話者は、表示名だけの色付きラベルで表示されます。
