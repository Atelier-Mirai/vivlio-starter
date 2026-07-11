# 表紙 CMYK カラーマネジメント改善 仕様メモ（別タスク・未着手）

作成日: 2026-07-06 / 位置づけ: 表紙ジオメトリ改修（Q1/Q3）から切り出した独立タスク。
関連: [print-pdf-full-bleed-notes.md](print-pdf-full-bleed-notes.md)（表紙ジオメトリ議論の発端）

---

## 背景（問題）

`vs build`（print_pdf ターゲット）が生成する CMYK 表紙 PDF の色がくすむ。

現状の変換（`lib/vivlio_starter/cli/cover.rb` / `create.rb`）は **ImageMagick `-colorspace CMYK` 一発のみ**で:

- **ICC プロファイルを一切使っていない**（リポジトリに `.icc` 無し・`-profile` 指定無し）。
  → ガマット圧縮が数式ベースで雑になり彩度が落ちる。
- **出力 PDF に ICC / 出力インテントが埋め込まれない**。
  → Preview/Acrobat が既定 CMYK 解釈で表示 → 画面上さらにくすむ。
- ドキュメント（`contents/43-cover.md` / `44-build.md`）は「**PDF/X-1a・Japan Color 2001 Coated 推奨**」と
  謳うが、**実装はそこまでやっていない**（gs での PDF/X 化も profile 埋め込みも無し）。docs と実装が乖離。

「変換ロジックの誤り」ではなく「**カラーマネジメントの省略**」が原因。印刷所では破綻はしないが色管理の保証は無い。

---

## 改善方針（案）

1. **ICC ベース変換に置換**: 素朴な `-colorspace CMYK` をやめ、ソース sRGB → 目的 CMYK プロファイルで
   知覚的レンダリング。例:
   ```
   magick in.png -intent Perceptual -black-point-compensation \
     -profile sRGB.icc -profile JapanColor2001Coated.icc out.pdf
   ```
2. **出力インテント埋め込み**: 生成 PDF に出力インテント（Japan Color 2001 Coated 等）を付与し、
   ビューア・RIP の解釈を一致させる。
3. **PDF/X-1a 化の検討**: docs の謳い文句に実装を合わせるか、docs を実態に合わせて後退させるかを決める。
4. **プロファイルの入手経路**: gem 同梱（ライセンス確認要）／ユーザー用意＋`vs doctor` 検出／設定キーで
   パス指定、のいずれか。Japan Color 2001 Coated の再配布可否を要確認。

## 対象範囲

- `cover.rb`: `generate_rgb_pdf_single` / `generate_pdfx_single`（CMYK 変換部）
- `create.rb`: `convert_svg_to_raster` 系（SVG→ラスタ CMYK 経路がある場合）
- `doctor.rb`: プロファイル存在チェック（採用する場合）
- docs: `43-cover.md` / `44-build.md` の CMYK 記述を実装に一致させる

## 留意点

- RGB→CMYK は物理的に鮮烈色（青・緑）がガマット外になるため、ICC 変換でも“完全一致”はしない。
  目標は「くすみの最小化」と「印刷所・ビューアでの解釈一致」。
- 本タスクは表紙ジオメトリ修正（`cover_bleed` 設定・bundle SVG の 1:1 化）とは独立。混ぜない。
