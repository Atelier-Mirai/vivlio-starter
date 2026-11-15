# 改変告知（Apache License 2.0 §4(b)）

このディレクトリのキーボードフォントは Apache License 2.0（`LICENSE.txt` / `LICENSE-ja.md`）で配布されています。Vivlio Starter では本フォントに以下の改変を加えた派生ファイルを同梱しています。

## 変更点

- **`Keyboard-JP-Regular.ttf`**: 原本 `Keyboard-JP-Regular.otf`（CFF アウトライン）を、**OTF→TTF（glyf アウトライン）へフォーマット変換**した派生物です。
  - 変換日: 2026-06-22
  - 同梱 TTF の初回生成: [fontTools](https://github.com/fonttools/fonttools) の `cu2qu`（3次ベジェ→2次ベジェ近似、許容誤差 1.0 units）で CFF を除去し `glyf`/`loca` を生成、sfnt version を TrueType（`0x00010000`）に設定。
  - グリフの字形・メトリクス・cmap・文字集合は原本を維持（アウトライン表現のみ変換）。
- **変換の理由**: Chromium 149（Vivliostyle 11.x が利用）が CFF(OTF) アウトラインのサブセットを **Type 3 フォント**として PDF 埋め込みするため。技術書典等の入稿で Type 3 は不可。TTF(glyf) 化により CID TrueType として埋め込まれる。
- **`Keyboard-JP-Regular.ttf` へのグリフの追加**（2026-11-15）: 原本に無い **⌃（U+2303・コントロール）** と **⌥（U+2325・オプション）** のキーの字を足しました。
  - 枠は ⌘（U+2318）の字の枠の 2 輪郭（外・内）を写し、記号は ⌘ と同じ太さ（60 units）の線から作った多角形です。送り幅・左の余白も ⌘ と同じ（2000 / 45）。
  - ⌃ は (720, 230)→(1000, 600)→(1280, 230) の山形、⌥ は (670, 610)→(875, 610)→(1125, 130)→(1330, 130) の折れ線と (1080, 610)→(1330, 610) の横線（座標は units・角はマイター）。fontTools の `TTGlyphPen` で作り、Unicode の cmap（(0, 3)・(3, 1)）に足しました。
  - ほかの字の字形・メトリクス・cmap は変えていません。

## 原本

- **`Keyboard-JP-Regular.otf`**: 改変前の原本をそのまま同梱しています（提供元の著作権表示・ライセンスは `LICENSE.txt` / `LICENSE-ja.md` を参照）。
