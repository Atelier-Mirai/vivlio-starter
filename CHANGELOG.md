# 変更履歴（Changelog）

このファイルには、1.0.1 からの主な変更を記録します。1.0.0 までの変更は [docs/changelog/v1.0.0-and-earlier.md](docs/changelog/v1.0.0-and-earlier.md) にあります。

記法は「Keep a Changelog」に基づき、Semantic Versioning（セマンティックバージョニング）に準拠します。

## 書き方

- 1 項目は 1〜2 行で、利用者から見て何が変わったかを書く。
- 背景・実装の事情・実測の数字は書かず、仕様書があればファイル名だけを添える（例: `text-table-spec.md`）。
- 見出しは `### Added`・`### Changed`・`### Removed`・`### Fixed` を使う。

```markdown
### Fixed
- 表紙のテーマ名にハイフンを使えるようにした（`cover: my-floral`）。
```

## unreleased

### Fixed
- コードブロックの見出しに空白を書くと（`ruby:field.rb（arrive に足したところ）`）、空白のところで切れていたのを直した。
- 頒布用の PDF を Adobe Acrobat Reader で開くと、キーの書体（Keyboard-JP）を抽出できないと表示され、技術書典の審査で差し戻されていたのを直した。
- 図（数式の日本語・showcase・mermaid）の字の一部が、Adobe Acrobat Reader で抜けていたのを直した。

## [1.0.1] - 2026-11-15

### Added
- キーの記法で、Mac の Option（`〘⌥〙`）と Control（`〘⌃〙`）もキーの形で組むようにした。
- `vs lint` に `accidental-index-term` を足した。`[arm64-darwin27]` のように、索引の印と読まれる角かっこを指摘する。

### Fixed
- 付録のページで、強調・強意の下線・囲み・コラムの地も付録の色（`theme.appendix_color`）で塗るようにした。PDF と Kindle で同じ色になる。
- 角かっこのキー（`〘[〙`・`〘]〙`）を一行に並べると、キーが消えていたのを直した。
- `add_log("log", "文字")` のように、名前に `_log(` を含むインラインコードが数式として組まれていたのを直した。
- `:::{.align-center}`・`:::{.align-right}` の中の段落が、中央・右にそろわなかったのを直した。
- 新しい本の最初のビルドで、EPUB・Kindle の画像の大きさがビルドごとに変わることがあったのを直した。
- 画像の代替テキストに `"` があると、EPUB が XHTML として読めなくなっていたのを直した。
- 書名に空白があると、奥付の見出しの id が不正な値になり、EPUB が EPUBCheck のエラーになっていたのを直した。
- `:::{.output}`・`:::{.terminal}` の中の `[arm64-darwin27]` が索引の印と読まれ、角かっこが消えていたのを直した。
