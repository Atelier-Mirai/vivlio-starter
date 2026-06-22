# 改変告知（Apache License 2.0 §4(b)）

このディレクトリのキーボードフォントは Apache License 2.0（`LICENSE.txt` / `LICENSE-ja.md`）で配布されています。Vivlio Starter では本フォントに以下の改変を加えた派生ファイルを同梱しています。

## 変更点

- **`Keyboard-JP-Regular.ttf`**: 原本 `Keyboard-JP-Regular.otf`（CFF アウトライン）を、**OTF→TTF（glyf アウトライン）へフォーマット変換**した派生物です。
  - 変換日: 2026-06-22
  - 同梱 TTF の初回生成: [fontTools](https://github.com/fonttools/fonttools) の `cu2qu`（3次ベジェ→2次ベジェ近似、許容誤差 1.0 units）で CFF を除去し `glyf`/`loca` を生成、sfnt version を TrueType（`0x00010000`）に設定。
  - グリフの字形・メトリクス・cmap・文字集合は原本を維持（アウトライン表現のみ変換）。
- **変換の理由**: Chromium 149（Vivliostyle 11.x が利用）が CFF(OTF) アウトラインのサブセットを **Type 3 フォント**として PDF 埋め込みするため。技術書典等の入稿で Type 3 は不可。TTF(glyf) 化により CID TrueType として埋め込まれる。

## 原本

- **`Keyboard-JP-Regular.otf`**: 改変前の原本をそのまま同梱しています（提供元の著作権表示・ライセンスは `LICENSE.txt` / `LICENSE-ja.md` を参照）。
