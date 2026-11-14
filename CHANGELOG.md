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
- 新しい本の最初のビルドで、EPUB・Kindle の画像の大きさがビルドごとに変わることがあったのを直した。
- 画像の代替テキストに `"` があると、EPUB が XHTML として読めなくなっていたのを直した。
- 書名に空白があると、奥付の見出しの id が不正な値になり、EPUB が EPUBCheck のエラーになっていたのを直した。
