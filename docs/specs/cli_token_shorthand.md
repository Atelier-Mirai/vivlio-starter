# CLI Token Shorthand Specification

## 1. 背景と目的
- `vs build` / `metrics` / `delete` / `rename` / `create` などの CLI コマンドは、章番号やスラッグを含む位置引数を受け取る。
- これまでコマンドごとにバラバラだったトークン解釈（ゼロ埋め、範囲展開、slug 付き指定、catalog.yml との照合）を共通レイヤで統一し、仕様のバラつきや重複実装を解消する。
- 本仕様は `TokenShorthand::Resolver` を中核に据え、catalog との連携や新規章作成の扱いまでを含む「CLI token shorthand」のガイドラインを提供する。

## 2. 対象コマンドとユースケース
1. **既存章のみが対象のコマンド**:
   - `vs metrics`, `vs metrics --warn/--all`
   - `vs build`（単章/複数章ビルド）
   - `vs delete`
   - `vs rename`（既存章の番号/スラッグ変更時）
   - `vs pre_process`, `vs post_process`, `vs convert`, `vs entries`
   - `vs index:auto`（章単位の抽出対象を指定可能）
2. **新規章を受け付けるコマンド**:
   - `vs create`
   - `vs rename`（新番号・新スラッグへのリネーム）
   - `vs renumber`（連番付け直し）
3. **複数章・混在指定**: `vs metrics 1-3,5,8-10`, `vs build 01,21-23`, `vs delete 1-foo,3-bar`。
4. **章 slug 指定**: `vs build 03-network`, `vs delete 08-web`, `vs create 07-new-chapter`。

> 参考: `docs/specs/metrics_spec.md` のコマンド例（`vs metrics 1-3`, `vs metrics 1-3,5,8-10` 等）も本仕様で定義するショートハンド構文に基づく。その他 CLI も同じ書式での入力を前提とし、追加のオプション（旧 `--detail` など）は導入しない方針。

## 3. 用語の整理
- **Token**: CLI が受け取る文字列単位の章指定（例: `"1-3"`, `"05"`, `"07-web"`）。
- **Normalized Token**: Resolver 内部でゼロ埋め・レンジ展開済みにしたトークン（例: "01", "02", "03"）。TokenShorthand namespace の正規化ロジックがこの役割を担う。
- **Catalog Entry**: `catalog.yml` から得られる章情報。`{ number: '01', slug: 'life', path: 'contents/01-life.md', kind: :chapter }` のような構造を想定。
- **Resolver**: 正規化済みトークンと catalog entry を突き合わせ、CLI が最終的に扱う章レコードへ変換する `TokenShorthand::Resolver`。

## 4. 基本要件
1. **ゼロ埋め規則**: `0-9` の入力は `00-09` に読み替える。`1-foo` → `01-foo`, `1` → `01`。
2. **レンジ展開**: `1-3` → `01,02,03`。降順（`10-8`）や混在（`1-3,5,8-10`）も展開する。
3. **slug 付き指定**: `01-life`, `01-life.md`, `01-life/foo` などの亜種も `01-life` に正規化する。`create` など slug を新規に与える場合は `TokenShorthand::Resolver` が番号と slug を分解し、ポリシーフラグに従って許可/拒否する。
4. **重複排除と順序保持**: 入力順をできる限り尊重しつつ、展開後の重複トークンは 1 度だけ出力する。
5. **除外章**: `book.yml: metrics.exclude_chapters` 等の設定と連動して、CLI 側でフィルタを掛けられるよう hook を用意する（Runner 側で別途判定してもよい）。

## 5. 処理フロー（案）
```
raw tokens (ARGV, positionals)
        ↓ TokenShorthand::Resolver.resolve(
              tokens: raw tokens,
              catalog_entries: CatalogLoader.new.entries,
              allow_new: true/false,
              allow_slug_only: true/false,
              allow_missing_slug: true/false,
              allow_cache: true/false,
              allow_auxiliary: true/false,
              allow_metrics_cache: true/false)
resolved entries (TokenShorthand::Data::Entry)
```

Resolver 内部でゼロ埋め・レンジ展開・slug 正規化を行い、catalog.yml と突き合わせた Entry を返す。

### 5.1 Resolver の責務
- **共通入口**: すべての CLI が Resolver を経由し、ここでゼロ埋め・レンジ展開・slug 抽出を一括処理する。
- **カタログ照合**: `catalog_entries`（CatalogLoader 由来の Struct 配列）を number / slug / `number-slug` のキーで逆引きし、該当 Struct を返す。
- **ポリシーフラグの吸収**:
  - `allow_new: false` → catalog に無いトークンで即エラー（`UnknownChapterToken`）。
  - `allow_new: true` → catalog 不在でも `exists: false` の Entry を生成する。
  - `allow_missing_slug: true` → 番号のみ指定も許可し、slug は `nil` のまま Entry を返す。
  - `allow_slug_only: true` → `life` のような slug 単独指定も catalog_entries から逆引き可能にする。
- **共通エラーメッセージ**: どの CLI から呼ばれても同じフォーマットでエラー/警告を出す（例: `章 09 は catalog.yml に存在しません`）。

### 5.2 CatalogLoader との協調
- Loader は catalog.yml を読み込み、既存章の Struct 配列を返すだけの純粋なデータ層とする。
- Resolver は Loader の結果を受け取り、CLI 入力を Struct にマッピングする責務に専念する。これにより Loader/Resolver いずれも単純な API を保ち、影響範囲を限定できる。

### 5.3 Common の章種別と downstream モジュール
- `Common` で定義している章種別（00→preface, 01-89→chapter, 90-98→appendix, 99→postface）を CatalogLoader が読み込み時に `kind` フィールドへ付与し、Resolver から返す Struct に埋め込む。
- `pre_process` / `post_process` など既存で `Common.chapter_kind_for` を参照していたモジュールも、Resolver から渡される Struct の `kind` を見るだけで chapter/preface/appendix 判定が可能になり、chapters.css 等の挿入条件と統合できる。
- これにより CLI と後段処理の両方が同じデータソース（CatalogLoader + Resolver）を共有し、章種別の重複実装を排除できる。
- `.cache/metrics/*.yml` や `.cache/vs/_colophon.pdf`、プロジェクトルートに展開された `_titlepage_legalpage.pdf`, `_toc.md`, `*.html` なども CatalogLoader で分類し、`kind: :cache`/`:auxiliary` と `special?` フラグを付与する。これにより build / clean / metrics コマンドが同一 Struct を基に対象選別できる。

### 5.4 TokenShorthand 名前空間
- `Vivlio::Starter::CLI::TokenShorthand` を新設し、Resolver / CatalogLoader / エラークラス / 共通 Data 定義をこの下に集約する。ファイル構成例: `token_shorthand/catalog_loader.rb`, `token_shorthand/resolver.rb`, `token_shorthand/errors.rb`。
- `TokenShorthand::Resolver.resolve` は `token_shorthand/data.rb` に定義した `TokenShorthand::Data::Entry` を返却し、CLI 側は Common を経由せず `TokenShorthand::Resolver.resolve(...)` を直接呼び出す。
- 旧来 Common が担ってきた CLI トークン加工（`normalize_tokens`/`normalize_chapter_token`/`expand_range_token` など）や `get_file_type`/`get_chapter_number` といった補助関数は、CLI からの直接利用を終了したため、外部互換を確認したうえで段階的に削除する。TokenShorthand 名前空間の内部実装に吸収し、Common には設定・ログなど歴史的ユーティリティのみを残す。
- 一時的に Common 側に Facade を置く場合でも、最終的には TokenShorthand namespace を唯一の API とし、Spec どおりの構成を完了条件とする。

### 5.5 Loader 拡張粒度と Resolver の遅延列挙
- **CatalogLoader の責務**: `catalog.yml` 由来の章エントリのみを一括ロードし、章番号・slug・種別を含む最小限の Struct 配列を返す。`.cache` や `_*.pdf` などの補助ファイルは扱わない。
- **Resolver の拡張ポイント**: `resolve` が `allow_cache:`, `allow_auxiliary:`, `allow_metrics_cache:` などのフラグを受け取り、必要になったときだけ `.cache/vs/**`, `.cache/metrics/**`, `_titlepage_legalpage.pdf`, `_toc.md` 等を遅延スキャンする。スキャン結果は Resolver 内でメモ化し、同コマンド内での再呼び出しに再利用する。
- **CLI からの利用例**:
  1. `vs create 01-foo` → `allow_new: true` のみ指定。catalog 情報だけで十分なため補助ファイルは読み込まない。
  2. `vs build 01-foo` → `allow_cache: true, allow_auxiliary: true` を指定し、`.cache/vs/**` や `_*.pdf` を併せて解決する。
  3. `vs metrics 01` → `allow_metrics_cache: true` を指定し、`.cache/metrics/*.yml` を対象に含める。
- **実装ポイント**:
  - Loader は O(章数) の軽量処理を維持し、Resolver がフラグ駆動で追加列挙する分担を徹底する。
  - `.cache` や `_*.pdf` の列挙ロジックは Resolver 内部の専用メソッドに切り出し、呼び出し時のみ実行する。
  - テストでは各フラグの組み合わせごとに期待される Struct セットが返るかを検証し、遅延ロード部分もユニットテストでカバーする。

## 6. エラーハンドリング指針
1. **存在しない章**: `allow_new: false` の場合 `TokenShorthand::Errors::UnknownChapterToken` を投げ、CLI 側で rescue してエラーメッセージを出力する。
2. **slug 重複**: 新規章作成時に既存 slug と衝突したら警告を出す。Resolver は `catalog_entries` を参照して検知する。
3. **番号不足**: slug のみ指定で `allow_slug_only: false` の場合は `TokenShorthand::Errors::MissingChapterNumber` を投げる。
4. **スラッグ不足**: `allow_new: true` かつ `allow_missing_slug: false` の場合は `TokenShorthand::Errors::MissingChapterSlug` を投げる。
5. **特殊ファイル指定**: `_titlepage_legalpage.pdf` や `.cache/metrics/*.yml` など `special?` が true のエントリを通常章向け CLI が受け取った場合は `TokenShorthand::Errors::UnsupportedSpecialFile` を投げ、clean / cache 系コマンドへの誘導メッセージを共通化する。


## 7. Open Questions
- `allow_new` とは別に、`allow_missing_slug` フラグが必要か。`vs create` / `vs rename` では slug 必須だが、`vs build 01` や `vs metrics 01`, 将来の `vs lint 01` など他コマンドでは番号のみ指定も許容する方針を正式化する。
- Resolver で保持するメタ情報（ユーザー指定順など）をどこまで Struct に残すか。正規化後は元の入力文字列（`03-bar` 等）は破棄して問題ない方針とする。
- 付録（90-98 番台）は既に catalog.yml / CatalogLoader の対象であり、Resolver で chapter と同様に扱う。今後、索引 / 用語集など別系統の単位がショートハンド対象になった場合は、`.cache` や `_*.pdf` と同じく Resolver のフラグ駆動で遅延列挙させる拡張パターンを採用する。

## 8. 共通データ構造（Struct/Data）
- `TokenShorthand::Resolver.resolve` は常に同一フィールド構成の不変データ（`TokenShorthand::Data::Entry`）を返す。`Data.define(:number, :slug, :kind, :basename, :path, :ext, :exists, :catalog_entry, :special?)` を `token_shorthand/data.rb` に定義済み。
- Resolver 側で catalog.yml 由来のメタ情報（章種別や表示名など）を埋め込み、各 CLI は必要な属性のみ参照する。
- すべてのコマンドが同一 Struct を受け取るため、将来的にフィールド追加が必要になっても Resolver を更新するだけでよい。未使用フィールドは参照しなくてよく、モジュールごとの分岐を削減できる。
- pre_process/post_process など章種別に応じた分岐を行うモジュールも、この Struct の `kind` を見るだけで判断可能とする。
- `.ext` には `.md` / `.html` / `.yml` などソース種別を格納し、 `.special?` は `_titlepage_legalpage.pdf` や `_toc.md` のような `_` 始まり特殊ファイルのフラグとして利用する。これにより `clean` や cache ディレクトリ操作でも同じ Struct を使い回せる。




## 移行手順
1. **対象洗い出し**: 既存 CLI（build / metrics / delete / rename / pre_process / post_process など）で `Common.normalize_tokens` を直接呼んでいる箇所を一覧化し、Resolver 化の優先順位を決める。
2. **専用ブランチで実装**: `feature/shorthand-resolver` などのブランチで CatalogLoader + Resolver 経由の API に差し替えを進める。旧実装とのフラグ併存は行わず、新 API のみを実装する。
3. **段階的コミット**:
   - 影響の小さい CLI（例: metrics）から置き換え、Resolver の API を検証する。
   - `allow_new`/`allow_missing_slug`/`allow_cache` などフラグの組み合わせが異なる代表 CLI（create/rename, build, metrics など）を早めにカバーして挙動を確定させる。
   - 各コミットで `rake test` を実行し、必要に応じてサブコマンド単位で PR を分割する。
4. **Common のクリーンアップ**: 全 CLI が Resolver を通る状態になったら、`rake test` を通過させたうえで旧 `Common.normalize_tokens` 系ユーティリティを削除する。

## テスト戦略
1. **Resolver 単体テスト**: ゼロ埋め、降順レンジ、混在トークン、slug-only、`allow_new` / `allow_slug_only` / `special?` 判定などを網羅するユニットテストを追加する。
2. **CatalogLoader + Resolver 結合テスト**: 実サンプルの `catalog.yml` を読み込み、Struct に `kind`, `ext`, `special?` が期待通り付与されるか検証。
3. **CLI 結合テスト**: `rake test` に、`vs build`, `vs metrics`, `vs delete`, `vs create`, `vs rename/renumber` など主要コマンドのシナリオテストを追加し、既存章／新規章／重複／特殊ファイルなどのケースをカバー。
4. **rake test を完了条件に**: 新 API 実装ブランチでは `rake test` が常にパスしていることを完了条件とし、これをもって回帰テストの代替とする。


## コーディング上の注意点

- Rubocopの `Metrics/MethodLength` 制限は無視して良い。[SKILL.md](/Users/mirai/.claude/skills/ruby-coding) の哲学に従い、ロジックを細切れにせず、一つのメソッド内でフェーズコメントを用いて構造化した、文脈の強いコードの実装を推奨する。


## 9. 実装後の成果物
- Resolver 実装完了後は、開発者向けの内部設計書（アーキテクチャ概要、API リファレンス、代表的な利用パターン、拡張手順、テスト観点など）を作成する。
- 仕様書は「何を実現するか」を示す文書として維持し、内部設計書では「どう実装／利用するか」を補完することで、`vs awesome` のような新規コマンドでも Resolver の導入手順を即座に把握できる状態を目指す。

### 内部設計書

- アーキテクチャ概要
   TokenShorthand namespace の構成図（CatalogLoader / Resolver / Data / Errors など）
   典型的な呼び出しフロー（CLI → Resolver → Struct → 後段処理）

- API リファレンス
   Resolver のメソッドシグネチャと主要フラグ (allow_new, allow_missing_slug, allow_cache, …)
   戻り値 Struct のフィールド定義と利用例

- 実装ガイド
   既存 CLI の移行パターン（create/rename, build, metrics, clean 等）
   テスト観点（単体/結合/CLI）とサンプルコード

- 拡張パターン
   索引・用語集など別カテゴリを追加する場合の Resolver 拡張方法
   .cache 系や特殊ファイルを遅延列挙する際のベストプラクティス