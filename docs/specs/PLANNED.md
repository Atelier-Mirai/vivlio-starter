# Planned（将来計画）

本システムの将来対応・改善アイデアを目的別に整理する。

- 見出しは目的別の `##`／`###` に統一し、各項目は `-` の箇条書きで記す。
- 優先度は行頭に `[High]` / `[Medium]` / `[Low]` で付す（未判定のものは付けない）。
- 既存仕様書がある項目は末尾にリンクを添える。

---

## Version 2.0 構想（メジャーアップデート）

後方互換を破る大きな方向転換を伴うため、v2.0 でまとめて取り組む。

- [High] **ビルドパイプライン全般の見直し**: `targets`（pdf / print_pdf / epub / kindle の単独・複合）×（単章 / フルビルド）の組み合わせが多く、`register_*_steps` が継ぎ接ぎになっている。ステップ登録ロジック・メソッド責務・テストカバレッジを再設計して共通化する（pdf と print_pdf の差は本来カバー・トンボの有無のみ）。
  - [High] **print_pdf を pdf から導出して高速化**: 現状は本文を pdf と print_pdf で 2 回レンダリングしている。pdf を生成後、カバー除去＋トンボ付与＋メディアボックス拡張で print_pdf を導出すれば、最重量レンダリングを 1 回省ける。ただし **塗り足し（bleed）** はクリップ済みの閲覧用 PDF からは復元できない（フチなし画像・背景で白フチ裁ち落とし事故になる）。フチなし要素の有無を検出するか `book.yml` のフラグで「無ければ導出（高速）／有れば個別レンダリング」のハイブリッドとする。
- [High] **設定ファイルを経由しない直接ビルドコマンド**: `vs build myawesome.md --pdf --theme:blue` のように、`book.yml` / `catalog.yml` を介さず単一 Markdown を直接ビルドできる軽量経路を提供する。
- [High] **小説（挿絵入り）への対応**: 現在は技術書専用。小説向けレイアウト（縦書き・挿絵配置・章扉など）に対応できるようテーマ／組版を拡張する。この段階でビルドパイプライン全般の見直しを併せて行うのが良い。
- [High] **テーマシステムの実装**: vivliostyle 公式の `bunko.css` などの既存テーマ CSS を活用。`book.yml` からのテーマ選択、CSS の動的切り替え、小説用縦書き・技術書用横書きのプリセット提供。
- [Medium] **VFM 設定のエントリーレベル適用**: `vivliostyle.config.js` 生成時に、ルートではなく各エントリー個別に VFM 設定を適用する（Vivliostyle CLI 公式推奨方式）。現状はフロントマターの `vfm: hardLineBreaks: true` で動作している。
- [Low] **CLI 終了コードの体系化**: 現状「正常 0 / 問題あり 1」の 2 値を、UNIX 慣例（例: grep の 0=見つかった / 1=見つからない / 2=エラー）に倣いエラー種別ごとに分ける。影響範囲が広く後方互換を破るため v2.0 で対応。

---

## ビルド / 出力

- [High] **Step 8（backlink dedup）の抜本的高速化**: 現状は「vivliostyle preview で全ページをブラウザレンダリング（〜150 秒）→ Playwright でページ番号取得 → vivliostyle build で PDF 再生成（〜196 秒）」の 2 段階構成で計 〜350 秒。vivliostyle CLI がページ番号情報を JSON 等で出力できれば Playwright フェーズを丸ごと省略できる。
- [High] **単章ビルドシステムのリファクタリング**: 機能的には完備しているが、ステップ登録ロジックの最適化・メソッド責務の明確化・テストカバレッジ拡充のため整理する（v2.0 のパイプライン見直しと連動）。
- [Medium] **リスト体裁改善（アルファベットリスト）**: 技術書で頻出する `a. b. c.` に対応。Markdown では `a.` がリストとして解釈されないため、CSS ユーティリティ（`ol.lower-alpha { list-style-type: lower-alpha; }`）を追加し、`<ol class="lower-alpha">` の生 HTML 記法で簡潔に実現する。
- [Low] **画像の width 属性自動補完**: `![](foo.png)` のように幅指定なしでも、実寸やクラス指定に応じて `width=100%` 等を自動補う（大判図をページ送りにせず収めるため）。
- [Low] **Data オブジェクト拡張**: Ruby 4.0 の Data に `empty?` を拡張し、`book.yml` の各種設定値をより直感的に扱えるようにする（現状は `vfm_config&.hardLineBreaks` のような安全呼び出しで対応）。

---

## 記法・置換ルール

- [Medium] **編集者コメント `@comment:...@` の一括除去オプション**: 現状は `post_replace_list.yml` で `<span class="hen-comment">...</span>` へ変換し CSS（`stylesheets/replace-list.css` の `.hen-comment`）で色付けするだけで、本文から除外する手段がない。本番ビルド向けに `vs build --strip-comments`（仮）や `book.yml` の `build.strip_editor_comments: true` で、PDF 出力時に `.hen-comment` をまとめて除去（または `display: none` 注入）する仕組みを検討。`contents/23-replace-list.md` の「ビルド時にまとめて消せる」は先取り表現のため、実装時に整合を取る。
- [Medium] **リスト項目の絶対配置＋SVG ガイド線記法**: `@lu/@ld/@ru/@rd/@ur/@ls/@rs/@us/@ds` で `<li>` を絶対配置しつつ L 字・水平・垂直の SVG ガイド線を自動生成する上級記法。ルール自体は実装済みだが、次の点が未完了のため正式サポートは次期リリース以降とする。
  - 親要素を自動で `position: relative` 化する標準クラスの提供
  - 座標系・単位（mm / %）の整理
  - 図解ページ向けプリセット（例: `.figure-guides` コンテナ）の正式化
  - 印刷プレビューでの視覚検証
  - サンプル（`81-replace-list-sample.md` §9）と `stylesheets/replace-list.css` のコンテナ定義あり。

### リスト項目の絶対配置とガイド線（記法詳細）

図解ページで、リスト項目を紙面上の好きな位置へ引き出す記法。項目末尾にガイド線の向きと寸法を付記すると、`<li>` が絶対配置に変換され、SVG の L 字ガイド線が自動で添えられる。

記法例: `- 項目テキスト@lu30,20@15,40`

| 記法 | 向き | 意味 |
| :--- | :--- | :--- |
| `@luW,H@X,Y` | 左上 (left-up) | ガイドを左上方向に伸ばす |
| `@ldW,H@X,Y` | 左下 (left-down) | ガイドを左下方向に伸ばす |
| `@ruW,H@X,Y` | 右上 (right-up) | ガイドを右上方向に伸ばす |
| `@rdW,H@X,Y` | 右下 (right-down) | ガイドを右下方向に伸ばす |
| `@urW,H@X,Y` | 上右 (up-right) | ガイドを上→右へ曲げる |
| `@lsW@X,Y` | 左水平 | 左方向の水平線のみ |
| `@rsW@X,Y` | 右水平 | 右方向の水平線のみ |
| `@usH@X,Y` | 上垂直 | 上方向の垂直線のみ |
| `@dsH@X,Y` | 下垂直 | 下方向の垂直線のみ |

- W, H — ガイド線の幅・高さ（mm）
- X, Y — 項目を配置する左上座標（mm。親要素基準）

図版の上に番号付きの注釈を並べる「図解ページ」で真価を発揮する。図と同じ座標系で注釈を置けるため、図を差し替えても Markdown 側の修正だけで済む。

---

## 参照・索引・書誌

- [Low] **脚注・参考文献サポート**: 簡易 BibTeX / CSL 相当の仕組みを検討する。

---

## コンテンツ / テンプレート

- [High] **`11-install.md` 等を著者の使い方・書き方の例として書き直す**。
- [High] **`templates/chapter.md` 等を書き方の例として書き直す**。
- [Medium] **用語集テンプレートの標準添付**: よく用いる用語をまとめた用語集テンプレートを標準添付し、プロジェクト作成時または後から選択適用できるようにする。
- [Low] **テンプレ断片スニペット**: 注意 / 補足 / Tip などのコンポーネントを断片化して提供する。
- [Low] **Web アプリ連携**: `codes/` に置いた HTML/JS/CSS のサンプルを、書籍内で QR コードや URL として紹介する仕組み。PDF 生成という主用途からは外れるため優先度は低い。

---

## EPUB / Kindle

- [Medium] **コードブロックの行番号と折り返し**: リフロー型 EPUB での行番号ずれ・テーブル化時の体裁崩れの是正。方式の選択肢を整理済み。→ [epub-code-line-numbers-spec.md](epub-code-line-numbers-spec.md)
- [Medium] **Kindle 向け simple ヘッダーの SVG 画像化**。→ [kindle-simple-header-svg-spec.md](kindle-simple-header-svg-spec.md)
- **`kindlepreviewer` を `vs doctor` でインストール可能にする**。

---

## 品質 / テスト

- [Medium] **Post-processing 単体テスト整備**: `_postReplaceList.json` の主要ルール（段落クラス付与、見出し・body クラス、各種クレンジング）のスナップショットテストを追加。想定外パターン（複数ブレース、引用符・バックスラッシュ混入等）の回帰防止。
- [Low] **自動検証パイプライン（CI）**: 最小サンプルでのビルド、Lint、HTML ポスト処理テストの自動実行。

### 堅牢性テスト（追加候補）

- [Medium] **11-3 巨大 YAML anchor の Billion Laughs 評価**: `aliases: true` 下でも Psych 5.x の制限で実害なしだが、上限値・挙動の明示的な検証余地あり。
- [Medium] **11-4 PDF 結合時の例外で中間 PDF を残す**: 結合例外時に中間 PDF を事後調査用に保持（`pdf_merger.rb` の例外ハンドリング強化）。
- [Medium] **12-2 / 12-3 冪等性・キャッシュ回帰**: 同一入力で複数回ビルドしても成果物が変化しないことの検証。
- [Medium] **`vivlio-starter-pdf` の堅牢性テスト整備**: 本体と同等の堅牢性テストをプラグインにも適用する。

---

## 開発者体験 / CLI UX

- [High] **日本語表記・組版 Lint（スタイルガイド）**。
- [High] **`vs doctor` にツールのバージョンアップ機能**: 各種ツールを最新版へ更新する機能を付与する。
- [Medium] **ビルドログ整備**: 各ステップに要約出力とエラーヒントを追加し、失敗時の原因特定とリカバリーを容易にする。
- [Medium] **`vs preflight` の章別エラー・警告サマリー**: 現状はファイル処理中にリアルタイム出力され章をまたいで混在する。章ごとに「21 章: 警告 N 件、エラー N 件」とまとめて表示するには、`LinkImageValidator` にコードインクルード・クロスリファレンス・QueryStream のエラーも蓄積する汎用メカニズムが必要（影響 4〜5 ファイル）。
- [Low] **スタイルガイド整備**: 章タイプ別（preface / chapter / appendix / postface）の設計指針、ユーティリティクラス（`.aki`, `.aki2` ほか）一覧と使用例をドキュメント化する。
- **コマンド実行時の応答メッセージ**: `vs clean` などで処理結果の応答があると親切。
- **CLI スピナー（ビルド進捗表示）**: ビルドは時間がかかるため、止まって見えないよう進捗アニメーションを表示したい。定番ライブラリ（`ora` / `cli-spinners`）か、以下のような簡易自作で実装できる。

  ```javascript
  const readline = require('readline');

  // アニメーションのコマ（本が印刷されていくイメージ）
  const bookSpinner = {
    frames: [
      "📄 [     ] 空白のページ...",
      "📄 [✍    ] 文字を書き込み中...",
      "📝 [✍🔤  ] CSS組版を適用中...",
      "📖 [✨📖 ] ページを製本中...",
      "📦 [✨📕✨] 電子書籍が完成！"
    ],
    interval: 300 // 切り替え速度（ミリ秒）
  };

  let i = 0;
  const timer = setInterval(() => {
    readline.cursorTo(process.stdout, 0);
    process.stdout.write(`\r${bookSpinner.frames[i % bookSpinner.frames.length]}`);
    i++;
  }, bookSpinner.interval);
  // ビルドが終わったら clearInterval(timer);
  ```

---

## 後日調査

- **Kindle 表紙（KDP 渡し）** の扱い。
- **`kindlepreviewer` の `-locale`** が現在 `en` 固定（必要に応じて切り替え可能にするか検討）。
