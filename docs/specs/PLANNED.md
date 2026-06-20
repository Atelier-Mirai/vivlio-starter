# Planned
**最新版へのアップデート機能** `vs doctor` に各種ツールのバージョンアップ機能を付与する。
**記法・置換ルール（次期リリース候補）**
- [Medium] 編集者コメント `@comment:...@commend` の一括除去オプション: 現状は `post_replace_list.yml` により `<span class="hen-comment">...</span>` へ変換され、CSS（`stylesheets/replace-list.css` の `.hen-comment`）で色付け表示されるだけで、本文から除外する手段がない。本番ビルド向けに `vs build --strip-comments`（仮）や `book.yml` の `build.strip_editor_comments: true` 設定などで、PDF 出力時に `.hen-comment` 要素をまとめて除去（または `display: none` 注入）する仕組みを検討する。`contents/23-replace-list.md` §編集者コメントの記述（「ビルド時にまとめて消したりできます」）は現状では先取りの表現なので、実装時に本節の表現と整合を取ること。
- [Medium] リスト項目の絶対配置＋SVG ガイド線記法（`post_replace_list.yml`）: `@lu/@ld/@ru/@rd/@ur/@ls/@rs/@us/@ds` で `<li>` を絶対配置しつつ L 字・水平・垂直の SVG ガイド線を自動生成する機能。ルール自体は実装済みだが、(1) 親要素を自動で `position: relative` 化する標準クラスの提供、(2) 座標系・単位（mm/%）の整理、(3) 図解ページ向けプリセット（例: `.figure-guides` コンテナ）の正式化、(4) 印刷プレビューでの視覚検証、が未完了のため今回は対応外とする。サンプル（`81-replace-list-sample.md` §9）と `stylesheets/replace-list.css` のコンテナ定義は次期リリースで正式サポート予定。

**ビルド高速化**
- [High] Step 8（backlink dedup）の抜本的な高速化: 現状は「vivliostyle preview で全416ページをブラウザレンダリング（~150秒）→ Playwright でページ番号取得 → vivliostyle build で PDF 再生成（~196秒）」という2段階構成で、合計 ~350秒を要する。vivliostyle CLI がページ番号情報を JSON 等で出力する機能を持てば Playwright フェーズを丸ごと省略できる。

**将来のメジャーバージョンアップ時の検討事項**
- [Low] CLI 終了コードの体系的な整理: 現状は「問題なし → 0、問題あり → 1」の2値だが、UNIX ツールの慣例（例: `grep` は「見つかった → 0 / 見つからなかった → 1 / エラー → 2」）に倣い、エラー種別ごとに終了コードを分けることを検討する。影響範囲が広いため、後方互換性を破るメジャーバージョンアップのタイミングで対応する。
- [Medium] `vs preflight` の章別エラー・警告サマリー表示: 現状は各ファイルの処理中にリアルタイム出力されるため、章をまたいで混在する。章ごとに「21章: 警告 N 件、エラー N 件」とまとめて表示するには、`LinkImageValidator` にコードインクルード・クロスリファレンス・QueryStream のエラーも蓄積する汎用メカニズムが必要で、影響ファイルが4〜5件に及ぶ。

**あると良いが、リリース後でも可**
用語集テンプレートの標準添付 [Medium] — 便利ですがリリースブロッカーではありません
VFM 設定のエントリーレベル適用 [Medium] — 現状でも動作しているため、後方互換で後から対応可能
テーマシステムの実装 [High] — 小説用縦書きなどは大きな機能追加。v1.0 後のメジャーアップデートとして取り組むのが現実的
Post-processing 単体テスト整備 [Medium] — リリース品質の信頼性向上に有効ですが、現在のテスト（740件）で基本的なカバーはできています

**リリース後で十分**
単章ビルドのリファクタリング、リスト体裁改善、Data オブジェクト拡張、画像 width 自動補完、脚注サポート、Web アプリ連携、CI パイプラインなど

#### ビルド/出力
- [High] 単章ビルドシステムのリファクタリング: 現在実装済みの単章ビルドtargets対応は機能的に完備しているが、コード構造の整理と保守性向上のためのリファクタリングを実施。ステップ登録ロジックの最適化、メソッド責務の明確化、テストカバレッジの拡充を含む。
- [High] 日本語表記・組版Lint（スタイルガイド）
- [Medium] リスト体裁改善の実装: 技術書で頻出するアルファベットリスト（a., b., c.）に対応。Markdownでは`a.`がリストとして解釈されないため、CSSユーティリティ（`ol.lower-alpha { list-style-type: lower-alpha; }`）を追加し、`<ol class="lower-alpha">`の生HTML記法で簡潔に実現可能にする。
- [Medium] 基本的に良く用いる用語をまとめた用語集テンプレートを標準添付し、プロジェクト作成時または後から選択適用できるようにする。
- [Medium] VFM設定のエントリーレベル適用: vivliostyle.config.js生成時に、ルートレベルではなく各エントリー個別にVFM設定を適用するよう改善。現在のフロントマターにvfm: hardLineBreaks: true設定でも動作するが、エントリーレベル設定によりきめ細やかな制御とVivliostyle CLI公式推奨方式への準拠が可能になる。
- [Low] Dataオブジェクト拡張の検討: Ruby 4.0のDataオブジェクトにempty?メソッドを拡張し、book.ymlの各種設定値をより直感的に扱えるようにする。現在はvfm_config&.hardLineBreaksのような安全呼び出しで対応しているが、Data.empty?メソッドがあればより自然なコード記述が可能になる。
- [Low] 画像の width 属性自動補完: Markdown が `![](foo.png)` のように幅指定なしの場合でも、実寸やクラス指定に応じて `width=100%` 等を自動補う仕組みを検討する（大判図をページ送りにせず収めるため）。

#### 参照・索引・書誌
- [Low] 脚注・参考文献サポート（簡易BibTeX/CSL）

#### テーマ/スタイル
- [High] テーマシステムの実装: vivliostyle 公式が提供する bunko.css などの既存テーマ CSS を活用できるようにする。config/book.yml からのテーマ選択、CSS ファイルの動的切り替え、小説用縦書き・技術書用横書きなどのプリセットテーマを提供。

#### コンテンツ/テンプレート
- [Low] テンプレ断片スニペット（注意/補足/Tipのコンポーネント化）。
- [Low] Web アプリ連携機能: `codes/` ディレクトリに配置した HTML/JS/CSS のサンプルコードを、書籍内で QR コードや URL として紹介する仕組みの検討。PDF 生成がメインの用途から外れるため優先度は低いが、インタラクティブなサンプルを書籍と連携させる将来的な拡張として記録しておく。
- [High] 11-install.mdなどを、著者の使い方や、書き方の例として、書き直す。
- [High] tamplates/chapter.mdなどを、書き方の例として書き直す

#### 品質・テスト
- [Medium] Post-processing単体テスト整備: `_postReplaceList.json`の主要ルール（段落クラス付与、見出し・bodyクラス、各種クレンジング）のスナップショットテストを追加。想定外パターン（複数ブレース、引用符・バックスラッシュ混入等）の回帰防止。
- [Low] 自動検証パイプライン（CI）: 最小サンプルでのビルド、Lint、HTMLポスト処理テストの自動実行。

**堅牢性テスト（追加候補）**
- [Medium] 11-3: 巨大 YAML anchor の Billion Laughs 評価（`aliases: true` 下でも Psych 5.x の制限で実害なしだが、上限値・挙動の明示的な検証余地あり）
- [Medium] 11-4: PDF 結合時 hexapdf 例外で中間 PDF を事後調査用に残す（`pdf_merger.rb` の例外ハンドリング強化）
- [Medium] 12-2 / 12-3: 冪等性・キャッシュ回帰（同一入力で複数回ビルドしても成果物が変化しないことの検証）
- [Medium] vivlio-starter-pdf の堅牢性調査・テスト整備（vivlio-starter と同等の堅牢性テストを vivlio-starter-pdf にも適用）


- ![EPUB/Kindle コードブロックの行番号と折返し](epub-code-line-numbers-spec.md)
- ![Kindle 向け simple ヘッダーの SVG 画像化](kindle-simple-header-svg-spec.md)


- kindle preview を vs doctorでインストール可能にする


- vs clean など、コマンド実行したときに応答が有ると良いかも。

### CLIスピナー
ビルドは時間がかかるので、利用者が止まってしまっているかもと思う。
そこで、スピナーを実装したい。
CLIスピナーの定番ライブラリである「ora」や「cli-spinners」を使うか、以下のようなシンプルな自作コード（Claude Code などの仕組みと同じもの）を組み込むことで実装できます。javascriptconst readline = require('readline');

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
  // コマを順番に表示
  process.stdout.write(`\r${bookSpinner.frames[i % bookSpinner.frames.length]}`);
  i++;
}, bookSpinner.interval);

// ビルドが終わったらタイマーを止める
// clearInterval(timer);


# リスト項目の絶対配置とガイド線記法（@lu / @ld / @ru / @rd / @ur / @ls / @rs / @us / @ds）は、親要素の自動 position: relative 化、座標系の整理、図解ページ向けプリセットの正式化が未完了のため、次期リリース以降で正式サポート予定。

## リスト項目の絶対配置とガイド線

図解ページなどで、リスト項目を紙面上の好きな位置に引き出したい場合に使う上級記法です。項目末尾にガイド線の向きと寸法を付記すると、`<li>` が絶対配置に変換され、SVG の L 字ガイド線が自動で添えられます。

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

この記法は、図版の上に番号付きの注釈を並べる「図解ページ」で真価を発揮します。図と同じ座標系で注釈を置けるので、あとから図を差し替えても Markdown 側を修正するだけで済みます。

## 後日調査
Kindle 表紙（KDP 渡し）
-locale 現在はen固定
