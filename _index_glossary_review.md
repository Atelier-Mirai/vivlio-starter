# 索引・用語集レビュー
※ フラグ: [i]=索引のみ、[g]=用語集のみ、[ig]=両方、[r]=棄却、[-i]=索引から除外、[-g]=用語集から除外
※ 読みの修正は ( ) 内を編集。用語集の説明文は空行の後にインデントして記述。

## 1. 登録済み用語の確認 (Terms: 5語)

- [g] `Today` **PDF** (PDF) - スコア: 592.4
  - 00-preface: ページレイアウト、目次の生成、画像の配置、表紙の作成、入稿用 PDF の調整……。Vivlio Starter は、そうした煩雑な作業をすべて引き受
  - 11-workflow: 執筆が完了したら、`vs build` で書籍全体を組版します。閲覧用 PDF・印刷入稿用 PDF・EPUB の三形式を、一度のコマンドで生成できます。 `

  PDFはPortable Document Formatの略で、Adobe AcrobatなどのPDFビューアで閲覧できる形式です。

- [i] `Today` **Starter** (Starter) - スコア: 507.8
  - 00-preface: Vivlio Starter の世界へ！ 「自分の本を作ってみたい」——そう思ったことはありませんか。日々の仕事で培った技術的な知見、趣味で深めた
  - 11-workflow: 執筆ワークフロー概観 :::{.chapter-lead} Vivlio Starter を使った書籍制作は、「プロジェクト作成 → 執筆 → 整える → ビルド

- [i] `Today` **Vivlio** (Vivlio) - スコア: 490.0
  - 00-preface: Vivlio Starter の世界へ！ 「自分の本を作ってみたい」——そう思ったことはありませんか。日々の仕事で培った技術的な知見、趣味で深め
  - 11-workflow: 執筆ワークフロー概観 :::{.chapter-lead} Vivlio Starter を使った書籍制作は、「プロジェクト作成 → 執筆 → 整える → ビルド

- [i] `Today` **ツール** (つーる) - スコア: 482.7
  - 00-preface: — `vs new` でプロジェクトを作成し、`vs doctor` で必要なツールを自動セットアップ ## この本で学べること - **Markdown で執
  - 11-workflow: 、Vivliostyle や ImageMagick など、書籍制作に必要な外部ツールが一括でセットアップされます。 ```bash vs new mybook

- [i] `Today` **インストール** (いんすとーる) - スコア: 825.2
  - 11-workflow: cd mybook ``` **参照:** 「インストール」「新規プロジェクトの作成（vs new）」「環境診断（vs doctor）」
  - 51-doctor: 不足しているツールがあれば、`--fix` オプションで自動インストールも可能です。 ::: ## vs doctor とは :::{.sectio



## 2. 推奨候補 (High Candidates: 4語)

- [ ] `NEW!` **CSS** (CSS) - スコア: 296.2
  - 00-preface: で書いた原稿から高品質な PDF・EPUB を生成する書籍制作システムです。CSS 組版エンジン Vivliostyle をコアに据え、原稿の前処理から目次生成、
  - 95-further-inspiration: style_introduction.webp) **Web技術で「本」が作れるCSS組版Vivliostyle入門** リブロワークス (著),

- [ ] `NEW!` **コマンド** (こまんど) - スコア: 256.9
  - 00-preface: 特別なフォーマットを覚える必要はありません - **コマンド一発でビルド** — `vs build` ひとつで、原稿が美しい PDF に変
  - 11-workflow: ## 各ステップの概要 ### ① プロジェクト作成 `vs new` コマンドで書籍プロジェクトの雛形を生成します。書籍名・著者名などを対話形式で入力すると、

- [ ] `NEW!` **ビルド** (ビルド) - スコア: 241.4
  - 00-preface: 特別なフォーマットを覚える必要はありません - **コマンド一発でビルド** — `vs build` ひとつで、原稿が美しい PDF に変わります -
  - 11-workflow: 「プロジェクト作成 → 執筆 → 整える → ビルド → 入稿・配布」という5つのステップで完結します。本章では、それぞれのステップ

- [ ] `NEW!` **自動インストール** (じどういんすとーる) - スコア: 226.4
  - 51-doctor: 不足しているツールがあれば、`--fix` オプションで自動インストールも可能です。 ::: ## vs doctor とは :::{.sectio



## 3. 一般候補 (Low Candidates: 10語)

- [ ] `NEW!` **EPUB** (EPUB) - スコア: 192.3
  - 00-preface: Starter は Markdown で書いた原稿から高品質な PDF・EPUB を生成する書籍制作システムです。CSS 組版エンジン Vivliostyle
  - 11-workflow: build` で書籍全体を組版します。閲覧用 PDF・印刷入稿用 PDF・EPUB の三形式を、一度のコマンドで生成できます。 ```bash vs build

- [ ] `NEW!` **Markdown** (Markdown) - スコア: 188.2
  - 00-preface: :::{.chapter-lead} Vivlio Starter は Markdown で書いた原稿から高品質な PDF・EPUB を生成する書籍制作システムで
  - 11-workflow: ### ② 執筆 `contents/` ディレクトリ内の Markdown ファイルに原稿を書きます。章ファイルの追加・削除・番号の振り直しには専用のコマ

- [ ] `NEW!` **VivlioStarter** (VivlioStarter) - スコア: 170.0
  - 00-preface: 
  - 11-workflow: 

- [ ] `NEW!` **Vivliostyle** (Vivliostyle) - スコア: 188.2
  - 00-preface: PDF・EPUB を生成する書籍制作システムです。CSS 組版エンジン Vivliostyle をコアに据え、原稿の前処理から目次生成、表紙作成、
  - 11-workflow: さらに内部で `vs doctor --fix` が自動的に呼び出され、Vivliostyle や ImageMagick など、書籍制作に必要な外部ツールが一括

- [ ] `NEW!` **セットアップ** (せっとあっぷ) - スコア: 176.2
  - 00-preface: `vs doctor` で必要なツールを自動セットアップ ## この本で学べること - **Markdown で執筆する為の各種記法
  - 11-workflow: や ImageMagick など、書籍制作に必要な外部ツールが一括でセットアップされます。 ```bash vs new mybook # 雛形生成 +

- [ ] `NEW!` **プロジェクト** (ぷろじぇくと) - スコア: 176.2
  - 00-preface: 統一感あるデザインに - **環境構築も自動** — `vs new` でプロジェクトを作成し、`vs doctor` で必要なツールを自動セットアップ ##
  - 11-workflow: Vivlio Starter を使った書籍制作は、「プロジェクト作成 → 執筆 → 整える → ビルド → 入稿・配布」という5つのステップで完

- [ ] `NEW!` **カバー** (かばー) - スコア: 183.2
  - 11-workflow: 。 ```bash vs build # 書籍全体をビルドする ``` カバー画像がまだ生成されていない場合、`vs build` が内部で自動的に `vs
  - 51-doctor: | 画像変換・リサイズ | | inkscape | SVG 編集・変換（カバー生成用） | | vips (libvips) | 高速画像処理 | | tes

- [ ] `NEW!` **ステップ** (すてっぷ) - スコア: 153.0
  - 11-workflow: 作成 → 執筆 → 整える → ビルド → 入稿・配布」という5つのステップで完結します。本章では、それぞれのステップで何をするのかを俯瞰します。各ステップ

- [ ] `NEW!` **ファイル** (ふぁいる) - スコア: 187.7
  - 11-workflow: の雛形を生成します。書籍名・著者名などを対話形式で入力すると、必要なファイル一式が自動的に用意されます。さらに内部で `vs doctor --fix` が
  - 51-doctor: ...` | 日本語技術書向けルールセットを一括インストール。設定ファイルも `config/` に自動配置 | | playwright / chrom

- [ ] `NEW!` **Homebrew** (Homebrew) - スコア: 163.5
  - 51-doctor: 不足しているツールを自動インストールします。macOS では Homebrew 経由でインストールします。Homebrew 自体や Xcode Command



## 4. 除外済みリスト (Rejected: 0語)
※ 復帰させたいものは [i], [g], [ig] を入れると索引・用語集に直接登録されます。

除外済みの用語はありません。
