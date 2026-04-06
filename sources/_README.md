# sources/ — 執筆資料ディレクトリ

執筆の参考資料や素材となるファイルを自由に配置するディレクトリです。

## 用途

- 参考にする PDF ファイル（仕様書、既刊書籍など）
- 執筆メモや構成案
- 外部から入手した素材ファイル

このディレクトリのファイルはビルド対象外です。サブディレクトリを作成して管理することも可能です。著者が自由に使える作業スペースとして活用してください。

## vs open との連携

`vs open` コマンドでファイル名を指定した場合、プロジェクトルート直下に見つからなければ `sources/` 配下を自動で探索します。

```bash
vs open quickstart        # sources/quickstart.pdf を開く
```

## vs pdf:read との連携

`vs pdf:read` で PDF から Markdown を抽出する際の入力ファイルとして活用できます。章トークンで指定した場合は `sources/` を自動で探索するため、ファイル名のみで指定できます。

```bash
vs pdf:read reference        # sources/reference.pdf を自動探索
vs pdf:read sources/reference.pdf  # パスを直接指定する場合
```
