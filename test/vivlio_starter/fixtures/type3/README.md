# Type 3 フォント検証 fixture

`vs build`（techbook: true）の PDF に **Type 3 フォント**が混入しないことを検査するための
資材。背景・原因の全容は `docs/specs/type3-regression-investigation.md` を参照。

## なぜ Type 3 を避けるのか

技術書典等の入稿で Type 3 フォントは不可。Chromium（Vivliostyle が利用）は、同梱フォントに
無い文字を OS フォントへフォールバックしたり、CFF(OTF) アウトラインや faux-bold 合成を
行うと、PDF へ Type 3 で埋め込む。CID TrueType で埋め込まれるよう各要因を潰す。

## 検査対象の文字と対策

| 文字 | 対策 |
|---|---|
| 〜 波ダッシュ U+301C | techbook 前処理で 全角チルダ U+FF5E → U+301C へ正規化（Zen は U+301C 収録） |
| † ダガー U+2020 | `.glossary-link sup` を明朝固定 + `font-weight: normal`（faux-bold 回避） |
| ▶ ⁵ → 等（Zen 非収録記号） | 同梱 `hackgen35`(HackGen35ConsoleNF) をフォントスタック末尾に（Regular/Bold 両字面） |
| キーキャップ Ctrl/S（keyfont） | keyfont を OTF→TTF 変換（`otf2ttf.py`） |

## ファイル

- `type3-check.html` — フォント埋め込み層の**高速**検証用 HTML。実バンドルフォントと本番相当の
  フォントスタックを参照する。techbook の文字正規化は経由しないため、正規化後の `〜` を直書き。
- `verify.sh` — `type3-check.html` を vivliostyle で直接ビルド→`pdffonts`→Type 3 を数える（~10秒）。
- `type3-check.md` — フル `vs build` 用の検証チャプター。`contents/` に置いて `targets: pdf` で
  ビルドし、生成 PDF を `pdffonts` で検査する（techbook の文字正規化も含めた最終確認用）。
- `otf2ttf.rb` — keyfont 等の OTF→TTF 変換スクリプト（再現用・Ruby）。輪郭変換は fontforge に委譲する
  （`brew install fontforge`）。`ruby otf2ttf.rb in.otf out.ttf`。

## 使い方

### 高速ループ（フォント/CSS の試行錯誤）
```bash
test/vivlio_starter/fixtures/type3/verify.sh
# >>> Type 3 フォント数: 0  なら OK
```

### 最終確認（本番ビルド）
```bash
rake test:manual   # FT-01 が Type 3 ゼロを検査する
```
