# 既知の不具合（Known Issues）
> 2026-06-14: `docs/specs/build-output-bugfix-spec.md` に基づき、印刷PDF本文欠落・付録採番・付録図表番号・EPUB奥付/索引併合・中間生成物残存・テーブル内数式を修正（下記 Fixed 参照）。
> 2026-06-21: EPUB/Kindle ターゲット分離（`epub-kindle-target-split-spec.md`）の一連で、**扉絵/節絵の表示**（合成画像化 ③-a）と**段落・ブロック数式の生 LaTeX 露出**（数式 SVG 化 ④）を**解消**。あわせて用語集 RSC-005・Kindle の techbook WebP 参照切れ RSC-007 を解消し、クリーン EPUB・Kindle 中間 EPUB の双方で **epubcheck ERROR 0 / WARNING 0** を達成。表紙埋め込みも解消（cover-image メタ＋cover.xhtml）。

- **EPUB の本文 † マーク数が同時ビルドする target に依存する**（保留・ターゲット整合性テストで検出）: 用語集オートリンクの脚注記号「†」は、`pdf` を併せてビルドすると Step 8（backlink dedup）が「同一 PDF ページ内の 2 回目以降の †」を削除し、その結果が共有 HTML 経由で EPUB にも反映される。一方 `epub` 単体ビルドは Step 8 を実行しないため † が全て残る。よって `targets: epub` 単体と `targets: pdf, epub` とで EPUB の † 数が変わる。リフロー型 EPUB にページ概念はなく本来この差は生じるべきでない。**EPUB/Kindle ターゲット分離後も未解消**（クリーン EPUB は PDF ビルド後の共有 HTML を使うため dedup の影響を受ける）。dedup は PDF ページ依存処理のため、EPUB を共有 HTML の dedup 影響から切り離す修正（HTML スナップショット／EPUB 用再生成等）が必要だが規模があり、`build-output-bugfix-spec.md` ⑦ として別途検討。本文の実体テキスト自体は同一。
- **EPUB(Kindle) の表内インライン数式のサイズが不安定**（既知の制限）: 外部 SVG を `<img>` 参照する数式は、Kindle のリフロー（特に表内）で本文フォントに追従せず、極大・極小に振れることがある。`em`→巨大、`px`→拡大非追従の本質的限界で、px 固定で安定化しつつ既知の制限とする（`epub-kindle-target-split-spec.md` §3）。表内に数式を置かない運用回避を推奨（ディスプレイ `$$` は正常）。
- **EPUB(Kindle) のコード行番号と行の対応がずれる/見栄えが悪い**（将来対応）: リフロー型 EPUB ではクリーン EPUB の Prism 行番号が折返し行とずれ、Kindle のテーブル方式では 2 桁行番号が縦に折り返り行間も不均一になる。方式の選択肢（テーブル化／番号非表示等）と現状不具合を `docs/specs/epub-code-line-numbers-spec.md` に整理（将来対応）。
- **EPUB の表紙画像が一回り小さく見える**（軽微・要実機確認）: 表紙埋め込み自体は解消済み。EPUB カバー（1600×2560, 比 1:1.6）と本文 A4（比 1:1.414）のアスペクト比差による見え方で、カバー画像の設計上の比率。実害が無ければクローズ可。
