# ビルドパイプライン現状調査報告書（VivlioVerso 基盤整備・第 1 部）

対象: `lib/vivlio_starter/cli/` のビルド系全域 / 調査日: 2026-07-03 /
ステータス: **調査完了**

3 部作の第 1 部。第 2 部 = [vivlioverso-foundation-plan.md](vivlioverso-foundation-plan.md)（基本構想）、
第 3 部 = [vivlioverso-foundation-workplans.md](vivlioverso-foundation-workplans.md)（個別改修計画）。

## 0. 背景

開発当初（約 1,000 行）の骨格は今も保たれている:

```
pre_process → convert (VFM) → post_process → build (Vivliostyle)
```

しかし 4 ターゲット（pdf / print_pdf / epub / kindle）対応・索引/用語集・
techbook モード等の増築により、現在は以下の規模に成長した（2026-07-03 実測）:

| 領域 | 行数 | 備考 |
|---|---:|---|
| cli 直下（コマンド群） | 10,965 | post_process.rb 1,012 行を含む |
| build/ | 6,636 | epub_builder.rb 1,633（最大）・pipeline.rb 878 |
| pre_process/ | 5,428 | 14 ファイル |
| index/ | 4,189 | |
| metrics/ | 2,888 | |
| samovar/ | 2,469 | |
| pdf/ | 1,903 | |
| post_process/ | 1,342 | |
| その他（import/techbook/guards/lint/doctor） | 2,490 | |

本報告書は、V2.0（コードネーム **VivlioVerso**：小説対応・テーマシステム・
パイプライン刷新）の土台整備に向け、**構造的な課題を 4 つ**に特定する。

---

## 1. 課題 A: ステップ登録の分岐爆発（pipeline.rb）

### 1.1 現状

`UnifiedBuildPipeline#register_full_mode_steps`（`pipeline.rb:101-132`）は
ターゲットの組み合わせで **5 分岐**し、それぞれがステップ列を手で組み立てる:

| 分岐 | 経路 |
|---|---|
| pdf + print_pdf | common → pdf_build → rename → print → (epub) → clean |
| print_pdf のみ | `register_print_pdf_only_steps_with_epub`（専用メソッド） |
| epub/kindle のみ | `register_epub_only_steps`（Step 8 dedup を除外） |
| pdf + epub/kindle | pdf_build → rename → epub → clean |
| pdf のみ | pdf_build → rename+clean（一体） |

これに `:single` / `:preflight` モードが加わり、登録経路は計 7 本。

### 1.2 問題点

1. **ステップ番号が経路ごとに矛盾** — print_pdf は「Step 13」（併用時）と
   「Step 10」（単独時）の 2 つの顔を持つ。final clean も Step 12 / 14 / F と揺れる。
   ログの読解・ドキュメントとの照合が困難。
2. **条件付きステップの重複挿入** — `snapshot_pre_dedup_htmls` の登録が 2 経路に
   コピペされている（`pipeline.rb:170,190`）。新ターゲット追加時、5 分岐すべての
   見直しが必要（漏れが即バグ）。
3. **ターゲット判定の 4 重複** — `pdf_target?` / `print_pdf_target?` / `epub_target?` /
   `kindle_target?`（`pipeline.rb:449-617`）が**呼ばれるたびに** CONFIG から
   `extract_targets` で再解析。しかも pdf/print_pdf 側だけレガシー
   `output.pdf.targets` フォールバックを持ち、epub/kindle 側は持たない（非対称）。
4. **オーケストレーションと実装の混在** — EPUB の zip 手術
   （`stabilize_epub_identifier!` / `sanitize_epub_opf_ids!`、unzip→sub→zip、
   `pipeline.rb:723-792`）や print_pdf の 6 フェーズ実装が、
   ステップ進行管理クラスの中に直接書かれている（計 878 行）。

### 1.3 影響

V2.0 で予定される「直接ビルド（catalog 非依存）」「print_pdf の pdf からの導出」
「小説モード」は、いずれも**新しいステップ列の組み合わせ**を意味する。
現構造では分岐が 5 → 8 → 12… と乗算的に増える。

---

## 2. 課題 B: 「ブロック除外→処理→復元」の 12+ 重複実装

### 2.1 現状

「コードブロック（フェンス/インライン）を処理対象から外す」というニーズが
横断的に存在し、**少なくとも 12 の独立実装**がある:

| # | 実装 | 方式 | `~~~` | 可変長/入れ子 | `include:` 除外 |
|---|---|---|:-:|:-:|:-:|
| 1 | `index/code_block_stripper.rb`（専用モジュール） | 状態機械 | ✅ | ✅ | ✅ |
| 2 | `pre_process/markdown_utils.rb` `extract_code_spans` | 正規表現＋プレースホルダ | ✅ | 一部 | ❌ |
| 3 | `pre_process/markdown_transformer.rb:243` | fence_len 追跡 | ❌ | ✅ | — |
| 4 | `pre_process/cross_reference_processor.rb:159` | @fence_marker | ❌ | ✅（4 連対応） | ✅ |
| 5 | `pre_process/image_path_normalizer.rb:152` | `start_with?('```')` トグル | ❌ | ❌ | ❌ |
| 6 | `pre_process/link_image_validator.rb` | 同上を **4 箇所**にコピペ（297/353/414/457） | ❌ | ❌ | ❌ |
| 7 | `pre_process/frontmatter_generator.rb:182` | 単純トグル | ✅ | ❌ | ❌ |
| 8 | `lint/tokenizer.rb:10` | `/^```/` トグル | ❌ | ❌ | ❌ |
| 9 | `metrics/analyzer.rb:274` | closing_fence? 判定 | ✅ | ✅ | ❌ |
| 10 | `metrics/sentence_collector.rb:38` | @open_fence | ✅ | ✅ | ❌ |
| 11 | `index/index_match_scanner.rb:226` | fence_len | ❌ | ✅ | ✅ |
| 12 | `guards/code_fence_check.rb` | 偶奇カウント（検証用） | ✅ | ✅（4 連前提） | — |

HTML 段階にも独立系がある: `post_process/html_replacer.rb` は `<pre>`/`<code>`/タグを
U+0000 プレースホルダで退避→置換→復元する（これは HTML 用で目的が異なるが、
「退避→処理→復元」という同型パターン）。

### 2.2 問題点

1. **意味論がバラバラ = 同じ原稿を段階ごとに違う解釈で読む**。
   `````markdown` の入れ子（本書のマニュアル自身が使用。21 章のフェンス修正で実証済み）
   に対し、#5〜#8 の単純トグル実装は**内外が反転**する潜在バグを持つ。
   catalog パーサ乖離（catalog-parser-unification-spec §1.2）と同型の「時限バグ」。
2. **新記法追加のたびに全実装の再点検が必要**。`:::` コンテナ・`@マクロ`・
   定義リスト等を追加するたび「コード内では無効」を各実装が独自に保証している。
3. **前処理 21 ステップの構造的帰結**。`MarkdownPreprocessor#run`
   （`markdown_preprocessor.rb:70-92`）は `context.content` への直列 mutation で、
   各 `transform_*` が生テキストへ独立に正規表現をかけるため、
   **各自でコード保護を再発明せざるを得ない**。

---

## 3. 課題 C: pre_process ⇄ stylesheets/ の密結合（CSS in-place 書き換え）

### 3.1 現状の仕組み

CSS の配線: 章 HTML の frontmatter `link` に `theme.css → {種別}.css → custom.css` を
注入（`frontmatter_generator.rb:121-126`）。`{種別}.css`（chapter.css 等）が
`@import` で base / page-settings / components / chapter-common… を連鎖ロードする。

その上で `CssUpdater`（564 行）が、ビルドのたびに **stylesheets/ のソース CSS
6 ファイル＋ vivliostyle.config.js を正規表現で in-place 書き換え**する:

| 書き換え対象 | 内容 | 契約（暗黙） |
|---|---|---|
| theme.css | `--theme-accent` / `--frontispiece-image` / `--section-bg-image` / `--frontispiece-padding` ほか | `--prop: 値;` が存在し、画像は `url("…")` ダブルクォートまたは `none` であること |
| appendix.css / preface.css | 専用アクセント色 | 同上 |
| chapter.css | `@import url("simple-header.css")` ⇄ `image-header.css` の**行き来切替** | import 行が特定形式で存在 |
| chapter-common.css | `--h3-marker` / `--h4-marker` | `"…"` ダブルクォート形式 |
| page-settings.css | 変数 22 個（判型・余白・フォント・ノンブル）＋ `@page { size }` リテラル | 各変数が宣言済みであること |
| vivliostyle.config.js | `size:` / `title:` プロパティ | `'…'` シングルクォート形式 |

呼び出し元は意外にも `frontmatter_generator.rb:324-369`（`update_all_css_files`）—
**フロントマター生成という名前のモジュールが全 CSS 更新のトリガー**を兼ねている。

### 3.2 問題点

1. **ソースと生成物が同一ファイル** — stylesheets/ の CSS は「著者が編集する
   ソース」であると同時に「ビルドが書き込む生成物」。`_README.md` は theme.css を
   「自動生成されるため直接編集しても上書きされる」と説明するが、実態は
   **全文生成ではなく特定プロパティの正規表現置換**。つまり:
   - 著者が `--theme-accent` の行を消す/改名する → 正規表現が不一致 →
     **黙って設定が効かなくなる**（エラーも警告もない）。
   - `url('…')` シングルクォートで書く → 不一致 → 同上。
   - これが「自由に stylesheets/ を編集できない」の正体。壊れ方が静かで、
     どの行が「触ってはいけない契約部分」なのか CSS からは判別不能。
2. **ビルドのたびに作業ツリーが汚れる** — 書き換えの向きにより theme.css 等が
   毎ビルド変更され、著者プロジェクトの git diff にノイズが乗る。
   chapter.css の import 切替は theme.style 設定次第で**行き来**する。
3. **遺物** — `css_updater.rb:294` に `awesomebook/stylesheets/page-settings.css`
   というハードコードパスが残存（旧プロジェクト名の化石。通常存在せず無害だが、
   その名のディレクトリがあると意図せず書き込む）。
4. **V2.0 テーマシステムの直接の障害** — 「テーマ = CSS セットの差し替え」を
   実現するには、差し替わる CSS すべてがこの暗黙の正規表現契約を満たす必要があり、
   bunko.css 等の既存テーマ CSS をそのまま持ち込めない。

### 3.3 正しく機能している部分（保存すべき資産）

- **CSS カスタムプロパティを設定の受け口にする設計自体は優れている**。
  `--theme-accent` を起点に `var()` で末端まで届く体系は V2.0 でもそのまま生きる。
- `custom.css`（ビルド非干渉・著者最優先）の窓口は正しく機能している。
- `safe_css_update` の「空になったら書かない」ガードも良い防御。
  問題は「どこに書くか」であって「何を書くか」ではない。

---

## 4. 課題 D: 共有可変ワークスペースと手動スナップショット

### 4.1 現状

中間生成物（章 HTML・`_sections.pdf`・`entries.js` 等）は**プロジェクトルート直下**に
生成され、各ステップがそれらを**破壊的に書き換えながら**進む。この共有可変状態が
以下の防御コードを生んでいる:

1. **dedup からの EPUB 隔離** — Step 8（backlink dedup）は章 HTML を PDF ページ
   依存で破壊的に間引くため、EPUB 用に**事前スナップショット**を取り
   （`snapshot_pre_dedup_htmls`、`pipeline.rb:696`）、Step E で復元する。
2. **フレーバ間の相互汚染防止** — clean EPUB と Kindle の両方を作るとき、
   Kindle の rewrite が clean 用 HTML を壊すため**二重スナップショット**
   （`pipeline.rb:648`）。
3. **clean からの保護退避** — 単章ビルドの成果物 PDF がクリーン対象パターンに
   合致するため、`.keep` に退避 → clean → 復元というハック（`pipeline.rb:429-435`）。
4. **entries.js の押し合い** — Step 9 が entries.js を奥付用に上書きするため、
   Step 13 が本文用に**再生成し直す**（`pipeline.rb:493-503` のコメントが経緯を証言）。

### 4.2 問題点

- ステップの**実行順序と副作用の知識が暗黙**で、順序を変えると壊れる
  （snapshot/restore は「順序が生む問題を順序で解決」する対症療法）。
- 新フレーバ（例: 小説用縦書き EPUB）を足すたびスナップショット管理が増える。
- 中間生成物がプロジェクトルートを汚し、クリーン処理のパターンマッチが
  「著者のファイルを誤爆しないか」という別の緊張を生む（保護退避ハックが証拠）。

---

## 5. 課題の相互関係と評価

```
D 共有可変ワークスペース ──┐
A ステップ分岐爆発 ────────┼──→ 新ターゲット/モード追加コストが乗算的
B マスキング 12 実装 ──────┼──→ 新記法追加コストが乗算的・時限バグの温床
C CSS in-place 書き換え ───┴──→ テーマ差し替え不能・著者の編集自由を阻害
```

- **B と C は独立に解ける**（他の課題に依存しない）。回帰リスクも局所的。
- **A は C・D の解決を容易にする足場**（ステップが宣言化されれば、
  ワークスペース分離もステップ定義の書き換えで済む）。
- **D は最も影響が大きく、V2.0 本体（パイプライン刷新）と同時に解くのが適切**。

### 定量まとめ

| 課題 | 散在箇所 | 潜在バグ | V2.0 阻害度 |
|---|---|---|---|
| A: 分岐爆発 | 7 登録経路・判定 4 重複 | ステップ番号矛盾 | 高（新モード追加） |
| B: マスキング | 12+ 実装 | 入れ子フェンスで 4 実装が誤動作 | 中（新記法追加） |
| C: CSS 密結合 | 6 CSS + config.js・暗黙契約 22+ 変数 | 著者編集で黙って不適用 | **最高（テーマシステム）** |
| D: 可変ワークスペース | snapshot 2 系統＋退避ハック 2 件 | 順序依存の暗黙知 | 高（新フレーバ追加） |

処方は第 2 部（基本構想）へ。
