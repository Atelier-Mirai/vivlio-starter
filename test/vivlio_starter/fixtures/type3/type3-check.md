---
title: Type 3 検証用チャプター
---

# Type 3 検証

本章は Type 3 フォント混入の回帰検査用。フル `vs build`（techbook: true）を通して
`pdffonts` で Type 3 が 0 になることを確認する。fixture を `contents/` に置いて
`targets: pdf` でビルドし、生成 PDF を検査する。

## 波ダッシュ・全角チルダ

範囲は 1〜50 です（波ダッシュ U+301C）。
全角チルダ 1～50 も書く（U+FF5E。techbook 前処理で U+301C へ正規化される）。

## Zen 非収録の記号

再生 ▶（U+25B6）、上付き ⁵（U+2075）、矢印 →（U+2192）。
これらは同梱 hackgen35（HackGen35ConsoleNF）フォールバックで CID 埋め込みされる。

## キーボード入力

保存は [Ctrl]+[S]（キーキャップ表現）で行います。

## 用語集記号（ダガー）

見出しや本文に現れる用語集記号 † は明朝（Zen Old Mincho）で描画する。
