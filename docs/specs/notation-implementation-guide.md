# 実装ガイドライン：新しい記法の追加（Notation Implementation Guide）

> 作成日: 2026-07-19
> ステータス: **恒常ガイドライン**（一過性の機能仕様書ではなく、記法を新設・拡張するたびに参照する実装規範。基盤 API が変わったらこの文書も更新する）
> 対象: `:::{.showcase}`・`$数式$`・` ```mermaid `・`:::{.terminal}`・fancy list のような**著者向け記法**を追加・拡張するときの、設計判断・実装手順・触るべき拡張点の一覧。
> 出自: showcase（explanatory-diagram-spec）・math（math-frontispiece-svg-spec）・mermaid（mermaid-diagram-spec）の 3 実装と、その後の基盤統一（Masking 公開 API・GeneratedAssetCache）で確立したパターンの成文化。

## 0. 大原則

1. **既知記法の踏襲**。独自記法を発明する前に、世の中の標準（mermaid・Pandoc fancy_lists・Markdown Extra 定義リスト等）をそのまま受ける道を探す。学習コストが最小になる。
2. **ビルドは止めない（縮退）**。外部ツール不在・生成失敗では、本文を壊さない形（原文温存・素の画像・コードブロックのまま等）へ縮退し、警告で知らせる。原稿がビルド不能になる記法は作らない。
3. **ターゲット横断の一貫性**。PDF・EPUB・Kindle で同じ見た目になる設計を最初から選ぶ（PDF=ベクタ / EPUB・Kindle=ラスターの対、または Kindle 劣化対策 3 点セット）。
4. **既存基盤に載せる**。§2 の再実装禁止リストを最初に読む。フェンス解釈・キャッシュ・コンテナ変換・警告の流儀は、新しい機構を作らず正典を使う。
5. **順序の理由をコメントに書く**。パイプラインのどこに挿すかは「なぜ前でなければならないか／後でなければならないか」をコード中に残す（後から動かした人が壊さないため）。

## 1. まず分類する（設計判断フロー)

```
その記法は…
├─ 見た目だけの問題か？（既存の HTML 構造に CSS を当てれば済む）
│    → 【A: CSS 型】 §3   例: .memo .tip .note .diagram .align-*
├─ Markdown/HTML の変換が要るか？（構造を組み替える・生 HTML を出す）
│    → 【B: 前処理変換型】 §4   例: fancy list, 定義リスト, book-card, terminal, text-*
└─ 外部ツールで画像等の資産を焼くか？
     → 【C: 生成資産型】 §5   例: math(SVG), showcase(合成SVG+ラスター), mermaid(SVG+PNG)
```

複合型もある（terminal = B の変換 + A の CSS）。その場合は各節を重ねて適用する。

## 2. 共通基盤（再実装禁止リスト）

| 基盤 | 責務 | 正典 |
|---|---|---|
| `Masking` | **コード領域解釈の唯一の実装**（P1）。フェンス（可変長・入れ子・`~~~`・`include:` 除外）とインラインコードの解釈は必ずここ | `cli/masking.rb` |
| `Masking.replace_top_level_fences` | コード保護より**前段**で特定言語のフェンスを横取りする公開 API（行番号付き・nil=原文維持） | 同上 |
| `MarkdownUtils.extract_code_spans` / `restore_code_spans` | コード退避→処理→復元。**コード内の作例を壊さない**ための標準手順 | `cli/pre_process/markdown_utils.rb` |
| `GeneratedAssetCache` | 生成資産の永続キャッシュ（`.cache/vs/<種別>/`・final clean を生き延びる・`vs clean --cache` が掃除） | `cli/pre_process/generated_asset_cache.rb` |
| `MarkdownTransformer.convert_container_blocks` | `:::{.class}` → `<div class="class">` のコンテナ変換 | `cli/pre_process/markdown_transformer.rb` |
| `Common.log_warn(msg, detail:)` | 著者向け警告の流儀（出現位置＋修正案。[[warning-messages-actionable]]） | `cli/common.rb` |
| `ToolUpgrader::TOOLS` | 外部ツール（brew/npm/gem）の**正典**。doctor の `--fix` と `vs upgrade` が共用 | `cli/doctor/tool_upgrader.rb` |
| `EpubBuilder` の `img[data-vs-raster]` localize | SVG→ラスター差し替えの共通経路。属性を付ければ**自動で**適用される | `cli/build/epub_builder.rb` |

これらと同じ責務のコードを transformer 内に書き始めたら、それは基盤側に API を足すサイン（mermaid が独自フェンス解析を持っていた反省から `replace_top_level_fences` が生まれた）。

## 3.【A】CSS 型の手順

1. **root の CSS を編集**する（`stylesheets/chapter-common.css` 等）。`lib/project_scaffold/` は直接編集しない（同期で消える）。編集後 `ruby copy_to_scaffold.rb`。
2. **クラスの許可は自動**: `ContainerClassCheck` は `stylesheets/**/*.css` のクラスセレクタを自動抽出して許可リストにする。**CSS にクラスを書けば警告は出ない**。前処理がブロックごと消費して CSS に痕跡が残らないクラス（showcase 型）だけ `PREPROCESSED_CLASSES` へ明示登録する（`cli/guards/container_class_check.rb`）。
3. **Kindle 劣化対策 3 点セット**（枠＋ラベル付きの囲みボックスを作るとき。正典は CLAUDE.md）:
   - `EpubBuilder::ADMONITION_LABELS` に `'class' => '【LABEL】'` を追加（Kindle のみ実ラベル `<p class="vs-adm-label">` 注入）
   - `chapter-common.css` に `body.vs-kindle .class { … }` を**リテラル色**で追加（KFX は `::before` と `var()` を無視する）
   - `epub_kindle_layout_test` にラベルのアサーションを追加
4. **CSS の落とし穴**は先に `docs/specs/vivliostyle-css-pitfalls-notes.md` を確認（`calc()+var()` 破棄・特異度・SVG intrinsic size 等）。

## 4.【B】前処理変換型の手順

### 4.1 transformer モジュールの型

`ShowcaseTransformer` / `MermaidTransformer` と同型にする:

```ruby
module VivlioStarter::CLI::PreProcessCommands
  module FooTransformer
    module_function

    def transform(content, chapter_slug:, source_filename:, tools: default_tools)
      # 変換不要なら content をそのまま返す（早期 return の安価な前置きフィルタを持つ）
    end
  end
end
```

- `module_function` の関数モジュール。状態は持たない（メモ化 ivar は可）。
- 外部依存（コマンド実行・レンダラ）は**キーワード引数で DI** し、テストはスタブで差し替える。
- 警告用に `source_filename:`（可能なら行番号も）を受け取る。

### 4.2 コード保護との関係（3 パターン）

| 記法の形 | 手順 | 実例 |
|---|---|---|
| `:::{.class}` コンテナ / インライン記法 | `extract_code_spans` で退避 → gsub → `restore_code_spans`。**コードフェンス内の作例（記法解説）を変換しない**ため必須 | showcase, text-*, 索引記法 |
| 言語付きフェンス自体が記法 | `Masking.replace_top_level_fences` で**コード保護より前に**横取り（放置すると Prism 化されて行番号付きソースが載る）。入れ子（````markdown 内の作例）は自動で素通りする | mermaid |
| 記法がコード的な中身を持つ | 先にチルダフェンス等へリテラル化し、以降のステップに触らせない | terminal（`transform_terminal_blocks!`） |

### 4.3 パイプラインへの組み込み

`MarkdownPreprocessor#run` に `transform_foo!` を追加する。位置は前後の依存で決め、**理由をメソッドコメントに書く**。典型的な制約:

- 画像を扱う → `normalize_image_paths!` の**後**（実ファイル解決は正規化後でないと不可能）
- フェンス横取り → `process_code_includes!`／コード保護の**前**
- `$` を含みうる → `transform_math!` との前後関係を確認（terminal が数式より前なのは `$ echo $A$B` の誤変換防止）
- ブロック内部に `{…}` `[…]` を含む → それらを壊す後続変換（text-*・spacing 等）より**前**

組み込んだら**順序テスト**（他記法と共存する原稿での通し変換）を書く。

### 4.4 lint への登録（必要な場合のみ）

ブロックの中身が日本語の文ではなく**機械データ**（座標・パラメータ）なら、`NotationGuard::MACHINE_DATA_CONTAINERS` へクラス名を追加する（`cli/lint/notation_guard.rb`）。放置すると textlint がブロックを 1 文として読み誤検出する。中身が普通の文章なら登録不要。

## 5.【C】生成資産型の手順（showcase / math / mermaid 同型）

### 5.1 構成要素

```
FooTransformer（記法抽出・置換・キャッシュキー）
  └─ FooRenderer（外部ツールのラッパ・available?・DI 差し替え点）
       └─ GeneratedAssetCache（.cache/vs/foo/ 永続キャッシュ → ワークスペースへ materialize）
```

- **レンダラは別クラス/モジュールに分離**し、`available?` と `render` を持たせる。重い外部実行はテストで必ずスタブする。
- 外部ツールの解決はローカル（`node_modules/.bin` 等）優先 → PATH の順（`MathTransformer.mathjax_root` / `MermaidRenderer` の流儀）。

### 5.2 キャッシュキー（内容アドレス）

```ruby
payload = ['v1', <入力内容のハッシュ>, <描画に効く設定…>, <ツール版>].join('|')
Digest::SHA256.hexdigest(payload)[0, 16]
```

- **描画結果に影響する入力をすべて**キーに含める（ソース・フォント・テーマ・ツール版）。含め忘れると設定変更後も古い図が出続ける。
- 先頭の **スキーマ版**（`'v1'`）は、コード側の描画設定を変えたとき（例: mermaid の htmlLabels 変更）に上げて旧キャッシュを一括無効化するためにある。
- 逆に「同キーなら必ず同じになる派生値」はキーに含めない（showcase の png/jpg 判定はキャッシュの拡張子から引いて再判定を省く）。

### 5.3 生成とキャッシュ

- 1 件ずつ生成する変換 → `GeneratedAssetCache.fetch(kind, files, out_dir:) { |cache_dir| 生成して true }`
- バッチ生成が有利な変換（プロセス起動を束ねたい）→ 自前でキャッシュ dir へバッチ書き込み後、`materialize` で配る（math の型）
- 生成物は必ず**対で**扱う（SVG だけ在って PNG が無い中間状態を作らない。fetch は揃わなければ縮退する）。

### 5.4 出力 HTML と EPUB/Kindle 差し替え

```html
<figure class="vs-foo">
<img class="vs-foo" src="images/foo/<章>/<key>.svg" data-vs-raster="images/foo/<章>/<key>.png" alt="…">
</figure>
```

- `data-vs-raster` を付ければ、`EpubBuilder` の localize（`img[data-vs-raster]` 一般化済み）が**自動で** EPUB/Kindle の src をラスターへ差し替える。個別の localize 実装は不要。
- ただし `EpubBuilder::localized_image?` に **`foo/` サブディレクトリの SVG 除外**を追加する（未参照 SVG をパッケージへ同梱しない）。`MERMAID_REL_SUBDIR` の並びに定数を足す。
- **参照パスは消費者 dir 相対（`asset_prefix` なし）**。ビルド生成物はワークスペース内実体のため（P4b §2.1）。著者画像（`asset_prefix` 付き）と参照形が違うのは正しい。
- alt に意味のあるテキスト（元ソースの要約）を入れる。属性値は必ずエスケープ。

### 5.5 SVG の落とし穴（必読）

- **`<foreignObject>` は `<img>` 経由で描画されない**。HTML ラベルを SVG に埋めるツール（mermaid の既定）は native `<text>` へ切り替えさせる。放置すると PDF で文字だけ消える。
- **`<img>` の SVG は親文書の `@font-face` を継承しない**。font-family にはシステム和文フォント（Hiragino 系等）のフォールバックを必ず併記する。
- **intrinsic size** を持たせ、CSS は `max-width: 100%; height: auto` を基本に（`vivliostyle-css-pitfalls-notes.md`）。

### 5.6 doctor / upgrade 連携

外部ツールを増やしたら 4 箇所（すべて既存の並びに 1 エントリ足すだけ）:

1. `doctor.rb` の `checks` ハッシュ＋判定 case（初回診断と再診断の 2 箇所）
2. `doctor.rb` の `--fix` インストール処理と `describe_missing` のラベル、DESC の一覧
3. `ToolUpgrader::TOOLS`（パッケージ名の正典。`vs upgrade` の更新対象になる）
4. 縮退時の警告文に `vs doctor --fix` への導線を入れる

## 6. 縮退と警告の流儀

- **ツール不在**: `available?` ガードで本文を変えず返す。警告は**章ごとに 1 回**（ブロックごとに出さない）。導入コマンドを detail に添える。
- **個別の生成失敗**: 当該ブロックだけ縮退し、他は処理を続ける。警告は `ファイル名:行番号` ＋具体的な修正案（before→after）。
- **縮退先**は「著者の意図が最も残る形」: 画像記法なら素の画像、フェンスならコードブロックのまま、注釈なら注釈なし画像。空文字への置換（ブロック消滅）は「そもそも出力しようがない」場合のみ。

## 7. テストの流儀

Minitest・DI スタブ（外部ツールは実行しない）。定番の検証項目:

1. **変換**: 記法 → 期待 HTML（クラス名・参照パス・alt・エスケープ）
2. **温存**: 記法解説フェンス内の作例・インラインコード内は変換しない
3. **キャッシュ**: キーの決定性（同一入力→同一 16 hex）・入力が変われば別キー・生成物が揃っていれば再生成しない・**クリーンビルド跨ぎ**（`FileUtils.rm_rf(Common::BUILD_DIR)` 後もレンダラを呼ばない）
4. **縮退**: ツール不在で本文不変・生成失敗で当該ブロックのみ原文
5. **EPUB**: localize（`data-vs-raster` 差し替え）・`localized_image?` の同梱除外
6. **順序**: 他記法（terminal・数式・コードインクルード）と共存する原稿で壊れない

仕上げは `rake test`（全体）＋ `bundle exec rubocop`。レイアウトに効く変更は実 `vs build` で紙面を目視する（/verify の流儀）。

## 8. ドキュメントと原稿の更新

| 対象 | 内容 |
|---|---|
| `contents/21-markdown-tutorial.md` | 標準 Markdown に由来する基本記法ならここ |
| `contents/22-extentions.md` | 拡張記法のリファレンス節（記法・実レンダリング例・制限・縮退の memo） |
| `contents/90-cheatsheet.md` | 記法早見表へ 1 行追加 |
| `docs/specs/<name>-spec.md` | 新規実装は仕様書を書いてから。完了後は `docs/archives/` へ |

原稿更新後は `ruby copy_to_scaffold.rb` で雛形へ同期する。

## 9. チェックリスト（コピペ用）

```
【共通】
[ ] §1 の分類を決め、既存 3 実装（showcase/math/mermaid）のどれを下敷きにするか特定した
[ ] パイプライン挿入位置の理由をコメントに書いた／順序テストを書いた
[ ] 縮退経路（ツール不在・生成失敗）でビルドが止まらない
[ ] 警告に 出現位置＋修正案＋doctor 導線 がある
[ ] rake test 全緑・rubocop クリーン・実ビルドで紙面確認
【A: CSS 型】
[ ] root の CSS を編集し copy_to_scaffold.rb で同期した
[ ] （囲みボックスなら）Kindle 劣化 3 点セット
[ ] （前処理が消費するクラスなら）ContainerClassCheck::PREPROCESSED_CLASSES
【B: 変換型】
[ ] コード保護との関係（§4.2 の 3 パターン）を選んだ
[ ] （機械データブロックなら）NotationGuard::MACHINE_DATA_CONTAINERS
【C: 生成資産型】
[ ] レンダラ分離＋DI＋available?
[ ] キャッシュキー＝内容アドレス（スキーマ版プレフィックス付き）
[ ] GeneratedAssetCache.fetch / materialize（自前のファイル存在チェックを書かない）
[ ] figure.vs-X + img[data-vs-raster]（localize は自動）
[ ] EpubBuilder::localized_image? に SVG 除外 subdir を追加
[ ] doctor 4 箇所（checks×2・--fix/ラベル/DESC・ToolUpgrader::TOOLS）
[ ] SVG 落とし穴（foreignObject / @font-face / intrinsic size）を確認
【原稿】
[ ] 22 章リファレンス節・90 章早見表・（基本記法なら）21 章
```
