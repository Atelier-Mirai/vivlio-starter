# 索引ライブラリの持ち運び（export/import）＋ 章指定スキャン 仕様

対象: `vs index:auto` / `vs index:export`（新）/ `vs index:import`（新）

## 背景 / 目的

- 長い本では全章を一度に見るのが大変なため、**章を指定して**索引・用語集の候補を探せると便利。
- `index:apply` 後に生成される `config/index_glossary_terms.yml` / `index_glossary_rejected.yml` は
  書籍固有データと作者の知的資産が混在している。**作者が書いた用語集の定義[g]・reject 判断・
  読みの補正**は他の書籍でも再利用したい（＝持ち運びたい）。

作者の資産（再利用可）と、この本から生成された派生物（使い捨て）を分離するのが核心。

| 種別 | 例 | 持ち運び |
|---|---|---|
| 用語集の定義[g] | term / yomi / definition | ○ |
| reject 一覧 | 「実装」「設定」等は載せない | ○ |
| 読みの個人辞書 | 重力→じゅうりょく | ○ |
| contexts（章・行） | 32-metrics: … | × 本固有 |
| backlink_sources | この本の HTML アンカー | × 本固有 |
| source: auto_extracted の[i] | 機械抽出語 | × 本固有 |

## 1. 章指定スキャン（既存機能の明示化）

`vs index:auto [CHAPTERS...]` は既に `TokenResolver` で章を解決する（実装済み）。

- `vs index:auto 21` / `21-23`（範囲）/ `21,25`（複数）
- 用語登録はすべて追記マージ（`merge_terms!`）のため**非破壊**。部分実行で他章の登録語は消えない。
- catalog 未登録の章でも `contents/` にファイルがあれば対象にできる。

対応は**ヘルプ用例とマニュアル（33章）への追記のみ**（新規実装不要）。既知の軽微な副作用として、
部分指定時はレビュー §1「登録済み用語」の**文脈プレビュー**が指定章内でしか再検索されず空欄に
なり得る（辞書本体は無傷）ことを注記する。

## 2. 索引ライブラリ（持ち運び可能ファイル）

### 2.1 ファイル

- 既定名 `index_library.yml`（CWD）。ただし利用者がパスに悩まないよう、**`book.yml` に
  既定パスを設定でき**、`export` / `import` を引数なしで実行できる（下記 2.6）。
- 書籍固有情報（contexts / backlink_sources / link / approved_at / source / pattern）は**含めない**。

### 2.2 スキーマ（version: 1）

```yaml
version: 1
exported_at: 'YYYY-MM-DD HH:MM:SS'
glossary:                # 作者が書いた用語集の定義（[g]）
  - term: EPUB
    yomi: いーぱぶ
    definition: '電子書籍の標準フォーマット…'
reject:                  # 索引に載せない語（誤検出・汎用語）
  - term: 実装
    reason: '汎用語'      # 任意
yomi:                    # 読みの個人辞書（term => yomi）
  重力: じゅうりょく
```

### 2.3 `vs index:export [PATH]`

- glossary: `index_glossary_terms.yml` の flags に `g` を含む語 → `term` / `yomi` / `definition`。
- reject: `index_glossary_rejected.yml` の全語 → `term`（+ `reason` 等のメタがあれば保持）。
- yomi: **作者が触れた語**（flags に `g` を含む or `source: manual_markup`）のうち、
  yomi が実読み（`yomi` が非空かつ `yomi != term`）の `term => yomi`。
- 出力は決定的（term 昇順）で冪等。空でも警告のうえ雛形は書かない。

### 2.4 `vs index:import PATH [--prefer-import]`

- 既定は**追記マージ・既存優先**（冪等）。`--prefer-import` で取り込み側を優先。
- glossary → `merge_terms!(flags: 'g', source: 'imported')`（定義付き）。既存語は既定で温存。
- reject → `index_glossary_rejected.yml` へ追加（重複排除）。
  既に採用済み（[g]/[i]）の語は reject しない（衝突時は警告してスキップ）。
- yomi → `config/index_yomi_overrides.yml` へ統合し、読み解決で MeCab より優先させる。
- レポート: 追加 / 更新 / スキップ件数を集計表示。

### 2.6 既定パス設定（`book.yml`）

利用者がファイル名・パスに悩まずに済むよう、`index_glossary` 配下に `library` を追加する。
ライブラリは用語集[g]・reject・yomi を横断するため共通設定の `index_glossary` 配下に置く。

```yaml
index_glossary:
  # …既存設定…
  library:
    path: "index_library.yml"        # export/import 共通の既定パス
    # 上級者向け（省略可・path を上書き）:
    # export_to:   "index_library.yml"          # 書き出し先だけ変える
    # import_from: "~/vivlio/index_library.yml" # 共有ライブラリから取り込む
```

パス解決順序（先勝ち）:

- `export`: コマンド引数 `PATH` > `library.export_to` > `library.path` > 組み込み既定 `index_library.yml`
- `import`: コマンド引数 `PATH` > `library.import_from` > `library.path` > 組み込み既定 `index_library.yml`

`~`（ホーム）を展開する。`import` で解決したパスが存在しなければエラー終了し、設定値も表示する。

### 2.5 読み解決の優先順位（更新後）

1. 記法 `[用語|読み]`
2. `index_glossary_terms.yml` の yomi
3. **`index_yomi_overrides.yml`（import で蓄積）** ← 新規
4. MeCab 推定（`YomiInferrer`）

`YomiInferrer` に override 辞書のロードを追加し、`infer` が override を最優先で返すことで
スキャナ・抽出・候補生成の全経路に一様に効かせる（挿入点を 1 箇所に集約）。

## 3. コマンド / ガード

- `vs index:export [PATH]` … PATH 省略時は 2.6 の解決順で既定パスへ書き出す。
- `vs index:import [PATH] [--prefer-import]` … PATH 省略時は 2.6 の解決順で既定パスから取り込む。
- ガード: `ProjectRootCheck`。import は解決したファイルが不在ならエラー終了。
- どちらも実行時に「使用するパス」をログ表示し、既定パス使用時も利用者が対象を把握できるようにする。

## 4. テスト

- export: [g]のみ抽出・固有情報除外・yomi は作者由来のみ・冪等。
- import: 追記マージ・既存優先 / `--prefer-import`・reject 衝突スキップ・yomi override 反映。
- round-trip: export→（別プロジェクト相当で）import で用語集・reject・yomi が復元される。
- パス解決: 引数 > `library.export_to`/`import_from` > `library.path` > 組み込み既定、`~` 展開。
- `YomiInferrer`: override 最優先・override 不在時は従来どおり。

## 5. 段階

- Phase 1（実装済み）: `export` / `import`（glossary[g] + reject）。
- Phase 2（実装済み）: yomi 個人辞書。`IndexCommands::YomiOverrides`（`config/index_yomi_overrides.yml`
  の読み書き）を新設し、`YomiInferrer#infer` 冒頭で override を最優先で返す（MeCab の手前）。
  `export` は用語集[g]・手動マークアップ由来の実読み＋蓄積済み overrides を `yomi:` に書き出し、
  `import` は `YomiOverrides.merge!`（追記・既定は既存優先）で取り込む。
