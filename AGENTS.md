## Skills / 開発標準（Ruby 4.0+）

- **Cursor**: プロジェクトルール `.cursor/rules/ruby-modern-development-standard.mdc` に Ruby 開発標準を記載している。`alwaysApply: false` + `globs: "**/*.rb"` とし、**Ruby ソースが主な文脈のとき**にルールが載るようにしている（Git やマニュアルだけの会話では載りにくく、コンテキストを節約する）。明示的に効かせたいときは、Cursor の **@** で当該ルール（またはファイルパス）を会話に添付してよい。

### 補足（`.mdc` について）

Cursor のルールファイル `.mdc` は、YAML フロントマター（`description` / `globs` / `alwaysApply` 等）と Markdown 本文からなる。**拡張子は `.mdc`** であり、単に `.md` をリネームしただけでは Cursor がルールとして認識しない。
