# Kindle 固定レイアウト（PDF ラスタライズ流用）の検討メモ

> 作成日: 2026-07-12
> ステータス: **検討メモ（見送り・RC 後に再検討）** — 調査済み・実装せず。着想と調査結果を将来のために記録する
> 対象: `kindle.layout: fixed` — A5 でビルド済みの PDF をページ画像化し、固定レイアウト EPUB→KPF として Kindle へ届ける案
> 関連: `config/book.yml`（`output.kindle.layout` — 現状 `reflowable` のみ・`fixed` は将来対応として予約済み）, `lib/vivlio_starter/cli/build/epub_builder.rb:352`（`validate_epub_layout_setting!`）, `lib/vivlio_starter/cli/pdf.rb:62`（`vs pdf:rasterize`）, `docs/specs/kindle-inline-math-textify-spec.md`（先行する軽量対策）, `docs/specs/kindle-css-compatibility-notes.md`

## 0. 着想と動機

Kindle(KFX) の CSS 対応は極めて古く、`var()`/`::before`/grid/数式サイズなど劣化対応の積み重ねを強いられている（kindle-css-compatibility-notes 参照）。**PDF のページをそのまま画像化して固定レイアウトで届ければ、この劣化対応が丸ごと不要**になり、数式・拡張テーブル・装飾すべてが PDF と同一の見た目で表示される——という着想（2026-07-12 ユーザー提案）。

`book.yml` には `output.kindle.layout: reflowable` があり、`fixed` は「将来対応予定」の警告つきで**設定の席だけ予約済み**。思想としては既にプロジェクトに存在する。

## 1. 技術的実現性 — 足場はある（実装は可能）

- **ページ画像化**: `vs pdf:rasterize`（`pdf.rb:62`）が既に PDF→ラスタライズの道具立てを持つ。A5 PDF は通常ビルドで生成済みなので、追加は「ページ画像化 → 固定レイアウト EPUB 包装」のみ。
- **固定レイアウト EPUB→KPF**: 画像ベースの fixed-layout はマンガの標準パイプラインそのもので、e-ink Kindle 端末でも確実に動く（日本のマンガが実証済み）。EPUB 側は `rendition:layout: pre-paginated`＋`original-resolution` 等のメタデータと 1 ページ 1 画像の spine 構成。`kindlepreviewer` CLI での KPF 変換は現行機構を流用できる。
- **論理目次**: fixed でも nav（目次）はページへのリンクとして機能する。既存の目次抽出（章→ページ対応）を流用可能。

実装量は中程度（EpubBuilder に第 3 フレーバを足すイメージ）。技術リスクは低い。

## 2. しかし端末サイズが根本的に合わない（見送りの主因）

| 画面 | 実寸（概算） | 紙の判型でいうと |
|---|---|---|
| Kindle 無印 6″ | 約 91×122mm | **A6 未満**（文庫より小さい） |
| Kindle Paperwhite 7″ | 約 107×155mm | **ほぼ A6**（文庫本） |
| Kindle Scribe 10.2″ | 約 155×207mm | ほぼ A5 |
| （参考）A5 判 | 148×210mm | 一般的な技術書 |
| （参考）iPhone 6.1″ | 約 65×140mm | — |

主力端末（6〜7 インチ）は **A6 ＝文庫本サイズ**であり、A5 紙面を映すと約 72% 縮小——A5 で 9pt の本文が実効 6.5pt 相当になる。市販技術書が A5/B5 なのは紙の判型を前提にした文字組であり、**e-ink 端末はそもそも技術書の判型に届いていない**。快適に読めるのは Scribe（所有者少数）とタブレットのみ。iPhone ではページ単位のピンチズーム読書になる。

## 3. 固定レイアウトで失うもの

- **フォントサイズ変更**（電子書籍リーダーの中核機能。高齢読者はほぼ全員が拡大して読む）
- **検索・辞書引き・ハイライト・メモ・読み上げ（TTS）** — 技術書で検索できないのはコピペ不可と並ぶ痛手
- コピー＆ペースト（着想時に認識済み）
- Enhanced Typesetting の恩恵全般（X-Ray 等）

## 4. 配信コストが跳ねる（KDP の経済的制約）

KDP の 70% ロイヤリティには配信料が差し引かれる: **米国 $0.15/MB**（日本は従来 ¥1/MB）。ページ画像はグレースケール圧縮を頑張っても 1 頁 150〜300KB 程度で、300 頁の技術書なら **50〜90MB → 1 冊売るごとに ¥50〜90 が消える**（または配信料なしの 35% プランへ落とす）。マンガ出版が直面している問題と同型。テキスト主体のリフロー版（1MB 未満）とは桁が 2 つ違う。

- 出典: [KDP: Digital Book Pricing](https://kdp.amazon.com/en_US/help/topic/G200634500), [Kindlepreneur: How to Reduce KDP Download Fees](https://kindlepreneur.com/reduce-download-fees/)

## 5. Print Replica（公式の「PDF そのまま」形式）が使えない理由

Amazon には教科書向けに Kindle Textbook Creator による **Print Replica**（PDF ベース）が存在するが、**e-ink Kindle 端末では読めない**（Fire タブレットとアプリのみ対応）。「Kindle 端末で読む」用途には不適。

## 6. 見立て（2026-07-12 時点の結論）

- **リフロー版の置き換えにはならない**。§2（判型ミスマッチ）＋§3（機能全滅）＋§4（配信料）の三重苦は、一般技術書では読者体験の純減。
- ただし**第 3 のターゲット（オプトイン `kindle.layout: fixed`）としては正当な需要がある**: 数式・図版・組版が命の書籍（数学書・楽譜・作品集・図鑑）、判型の小さい本（文庫・新書サイズで組んだ本なら 7″ にほぼ等倍で載る）、Scribe/タブレット読者を想定できる本。
- **先行すべきは軽量対策**: リフローの読書体験を保ったまま数式問題を解消する `kindle-inline-math-textify-spec.md`（同日仕様化・実装待ち）をまず入れる。
- **再検討のトリガー**: RC 公開後に (1) fixed を求める実需要が出る、(2) 大画面 e-ink の普及が進む、(3) 文庫判型プリセット（v2.0 の小説対応）が入る——のいずれか。着手時は本メモを仕様書へ昇格させる。

## 7. 着手時の実装スケッチ（将来のためのメモ）

1. ラスタライズ仕様の決定: DPI（e-ink 実効解像度 300ppi 前後に対し 1236×1648px 級で十分か）、グレースケール化の可否（カラー端末増加とのトレードオフ）、JPEG 品質 vs 文字にじみ（文字主体なら PNG/高品質 JPEG の比較検証が必要）。
2. `EpubBuilder` に fixed フレーバを追加: 1 頁 1 画像の XHTML＋`rendition:layout: pre-paginated`＋`original-resolution`。`validate_epub_layout_setting!` の警告を解除。
3. 目次: 章開始ページへの nav リンク生成（既存の目次抽出を流用）。
4. 検証: Kindle Previewer 3 で 6″/7″/10.2″ の各プレビュー＋ファイルサイズ実測（配信料試算を実数で更新）。
5. ドキュメント: 「どういう本に向くか」（§6）を著者向けに明記。既定は reflowable のまま変えない。
