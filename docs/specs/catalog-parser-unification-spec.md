# catalog.yml パーサ一本化 仕様（catalog-parser-unification）

対象: `lib/vivlio_starter/cli/` の catalog.yml 読み込み系 / 策定日: 2026-07-03 /
ステータス: **実装完了（2026-07-03）** — 全 1423 テスト緑・rubocop クリーン・実プロジェクトでバグ 2 件の実地解消を確認

実装メモ:
- Phase 1: `CatalogLoader` に `CatalogEntry` / `load_labeled_entries` / `collect_labeled` を追加。
  `load_catalog`・`expand_item` 系を kwargs パラメタ化。未知セクション警告を追加。
  新テスト `test/vivlio_starter/cli/build/catalog_loader_test.rb`（同値性ゲート含む 9 件）。
- Phase 2: `TokenResolver#load_catalog_entries` を委譲化・自前パース削除。バグ 1/2 の回帰テスト追加。
- Phase 3: `Metrics::CatalogLoader`（＋テスト）をファイル削除、`resolve_from_catalog` を委譲化。
- **実装中に発見した追加乖離**（§3.5 に追記）: 番号のみファイル（`15.md`）を bare number（`- 15`）で
  参照した際、`find_basenames_by_number` が `NN-*.md` のみ glob して番号のみファイルを落とし、
  TokenResolver（拾う）と乖離していた。`NN.md` も拾うよう修正し両者を一致させた。
- **§3.3 の実装からの微修正**: フォールバック判定は仕様例の `paths.any?` ではなく `entries.empty?` に。
  「catalog に章はあるが全ファイル不在」のとき従来は空を返し warn_no_targets に落ちていた挙動を保存するため
  （`paths.any?` だと catalog 外の Markdown へ誤ってフォールバックしてしまう）。

関連仕様:
- [config-access-unification-spec.md](config-access-unification-spec.md) §4（本仕様の発端。book.yml の統一原則を関連 YAML へ展開する判断）
- `docs/archives/catalog_spec.md`（catalog.yml の記法定義: 4 セクション・部タイトル・ショートハンド）
- `docs/archives/cli_token_resolver_spec.md`（章指定トークン解釈の TokenResolver への集約）

## 0. 経緯と目的

かつて各コマンドが章展開引数を独自に解釈していた問題は、`TokenResolver` への集約で解決した
（build / pre_process / lint / preflight / guards 等の主要コマンドは TokenResolver を使う）。
しかし **catalog.yml の YAML パース層は集約されず 3 実装が残った**ため、
「同じファイルを同じビルドの中で異なる解釈で読む」状態になっている。

本仕様は、YAML パース＋セクション/ショートハンド展開を `Build::CatalogLoader` の
**1 系統に一本化**し、`TokenResolver` は「Entry モデルへの変換とトークン照合」という
上位責務に専念させる。これにより後述の実証済みバグ 2 件が構造的に解消される。

```
build / lint / metrics / preflight / guards / ...   ← 各コマンド
----------------------------------------------------
TokenResolver（Entry モデル・トークン照合）          ← 唯一の窓口
----------------------------------------------------
Build::CatalogLoader（YAML パース・セクション/ショートハンド展開）← 唯一のパーサ
```

エラー耐性（metrics は catalog が壊れていても続行したい等）は
**パーサの実装差ではなく、呼び出し側のポリシー差**として表現する（§3.4）。

## 1. 現状調査（2026-07-02〜03 実測）

### 1.1 読み込み実装 4 系統

| # | 実装 | パースポリシー | ショートハンド | エラー処理 |
|---|---|---|---|---|
| 1 | `Build::CatalogLoader`（`build/catalog_loader.rb:100`） | `safe_load(permitted_classes: [], aliases: true)` | ✅ 展開 | 親切メッセージで raise |
| 2 | `TokenResolver::Resolver#load_catalog_entries`（`token_resolver.rb:133`） | `safe_load`（aliases 不可） | ❌ 誤解釈 | rescue なし（生 Psych 例外） |
| 3 | `Metrics::CatalogLoader`（`metrics/catalog_loader.rb:50`） | `safe_load_file(permitted_classes: [Symbol])`（aliases 不可） | ❌ 非展開 | warn + `{}`（ただし `Psych::AliasesNotEnabled` 等は `Psych::SyntaxError` rescue に掛からず伝播） |
| 4 | `Common.ensure_required_yaml_files!`（`common.rb:111`） | `safe_load(aliases: true, symbolize_names: true)` | —（存在・解析可能性の検証のみ） | abort |

#4 は検証専用で内容を消費しないため一本化の対象外（§3.6）。

消費側の分布:
- **CatalogLoader 系**: `chapter_config.rb:93`、`part_title_generator.rb:37,96`、
  `body_class_injector.rb:62`、`index.rb:72`、guards（`CATALOG_FILE` 定数参照）
- **TokenResolver 系**: `build_command.rb:220`（フルビルドの章解決）、`preflight_command.rb`、
  `lint.rb:485`、`pre_process.rb:301`（相互参照）、`orphan_file_check.rb:17`、
  `catalog_entries_check.rb`、`common.rb`（付録レター採番）、`heading_processor.rb:378`
- **Metrics 系**: `metrics/runner.rb:485`（引数なしの `vs metrics` のみ。
  章の明示指定時は既に TokenResolver を使用 = `runner.rb resolve_target_paths`）

### 1.2 実証済みバグ（2026-07-02 最小プロジェクトで再現）

**バグ1: エイリアス非対称。** catalog.yml に YAML アンカー/エイリアス（`&empty` / `*empty`）を
書くと、CatalogLoader は正常（「DRY な catalog 記述のため許可」と `catalog_loader.rb:94` に
設計意図が明記されている）だが、同じファイルを読む TokenResolver がクラッシュする。

```
[Build::CatalogLoader] OK → ["10-intro", "30-outro"]
[TokenResolver]       例外: Psych::AliasesNotEnabled
```

guards（CatalogLoader 系）は通るのにビルド本体（TokenResolver 系）が落ちる、という非対称。

**バグ2: ショートハンドの解釈乖離。** `CHAPTERS: [10-intro, 21-25, 30-outro]` のとき:

```
[Build::CatalogLoader] OK → ["10-intro", "21-alpha", ..., "25-echo", "30-outro"]   # 21〜25 に展開
[TokenResolver]       OK → ["10-intro", "21-25", "30-outro"]
                            number=21 slug="25" exists=false path=contents/21-25.md  # 幽霊エントリ
```

TokenResolver は `21-25` を「number=21, slug=25」の単一章と誤解釈し、
**21〜25 章が丸ごとビルド対象から脱落**する。一方 `chapter_config.rb`（CatalogLoader 系）は
21〜25 章を展開するため、**1 回のビルド内で 2 つの解釈が同居**する。
なお CLI 引数の `vs build 21-25` は `Resolver#normalize`（`token_resolver.rb:113-117`）が
範囲展開するため正しく動く。壊れているのは **catalog.yml 内に書いた場合**だけ。

補足: `guards/catalog_entries_check.rb:9` のコメントは「TokenResolver は
ショートハンド対応済み」と主張しているが実装と乖離している（本仕様の実装で正しくなる）。

いずれも実プロジェクトの catalog.yml は該当記法を未使用のため顕在化していない「時限バグ」
（config-access-unification Phase 3 で発見された `pdf.compress` と同型）。

### 1.3 その他の乖離

- **未知セクションキー**: CatalogLoader は `SECTION_KEYS`（PREFACE/CHAPTERS/APPENDICES/POSTFACE）
  のみ走査するが、TokenResolver は**トップレベルの全キー**を取り込む（`raw_yaml.flat_map`）。
- **Metrics::CatalogLoader は CatalogLoader の劣化コピー**: セクション展開ロジックを再実装
  しているがショートハンド・エイリアス非対応。存在理由だった「catalog 外の章も分析」は
  明示指定経路（TokenResolver）が既に担っており、固有価値は「破損時 warn + glob フォールバック」
  というエラー耐性だけ。

## 2. 統一後の責務分担

| 層 | 責務 | 持たない責務 |
|---|---|---|
| `Build::CatalogLoader` | YAML パース（safe_load・aliases 許可・permitted_classes []）、セクション走査（SECTION_KEYS 限定）、部タイトルのラベル伝播、ショートハンド展開、ビルド用検証（空カタログ・重複番号） | Entry 生成、トークン照合、エラー握り潰し |
| `TokenResolver` | CatalogLoader の出力を Entry へ変換、CLI トークンの正規化・照合、システムページ | YAML パース、セクション/ショートハンド解釈 |
| 各コマンド | エラー耐性ポリシー（raise / warn+続行 / フォールバック） | パース詳細 |

## 3. 詳細仕様

### 3.1 `Build::CatalogLoader` — 新 API `load_labeled_entries`

TokenResolver が必要とするのは「basename＋ラベル（部タイトル or セクション名）＋セクション」
の 3 つ組。これを返す公開メソッドを追加する。

```ruby
# TokenResolver へ渡す 3 つ組。label は最内の部タイトル（なければセクション名）。
CatalogEntry = Data.define(:basename, :label, :section)

# catalog.yml を解析し、ラベル付きの章一覧を返す（TokenResolver の下層 API）。
# ファイル不在は []（TokenResolver の「カタログなしでも動く」契約を維持するため、
# ビルド専用の load_all_basenames と違い raise しない）。
# 空カタログ・重複番号の検証も行わない（それはビルド時の関心事 = load_all_basenames 側）。
# @return [Array<CatalogEntry>]
def load_labeled_entries(catalog_path: CATALOG_FILE, contents_dir: Common::CONTENTS_DIR)
  return [] unless File.exist?(catalog_path)

  catalog = load_catalog(catalog_path:)
  SECTION_KEYS.flat_map do |section|
    collect_labeled(catalog[section], label: section, section:, contents_dir:)
  end
end

# セクション内を再帰走査し、Hash キー（部タイトル）を label として伝播させつつ
# ショートハンドを展開する。
# @return [Array<CatalogEntry>]
def collect_labeled(items, label:, section:, contents_dir:)
  case items
  in nil then []
  in String | Integer
    expand_item(items, contents_dir:).map { CatalogEntry.new(basename: it, label:, section:) }
  in Array then items.flat_map { collect_labeled(it, label:, section:, contents_dir:) }
  in Hash  then items.flat_map { |k, v| collect_labeled(v, label: k.to_s, section:, contents_dir:) }
  else []
  end
end
```

既存メソッドは**キーワード引数でパラメタ化**する（デフォルト値により既存呼び出しは無変更）:

| メソッド | 変更 |
|---|---|
| `load_catalog` | `(catalog_path: CATALOG_FILE)` を追加。エラーメッセージ内の固定文字列 `CATALOG_FILE` も引数値に |
| `expand_item` / `expand_shorthand` / `find_basenames_by_number` | `(contents_dir: Common::CONTENTS_DIR)` を追加（glob の基点） |
| `load_all_basenames` / `load_existing_basenames` / `load_part_titles` / 検証系 | 変更なし（ビルド用途はデフォルトパスのみ） |

パラメタ化するのは TokenResolver（およびそのテスト）が
`Resolver.new(catalog_path:, contents_dir:)` で任意パスを注入できる契約を持つため
（`token_resolver_test.rb:82-121` が依存）。

### 3.2 `TokenResolver` — パース層の委譲

`load_catalog_entries` を CatalogLoader への委譲に置き換え、
自前パース（`extract_from_yaml` / `normalize_catalog_basename`）を**削除**する:

```ruby
# --- Phase 2: Catalog Loading (カタログ読み込み) ---
# YAML パース・セクション/ショートハンド展開は Build::CatalogLoader に一本化
# （仕様: docs/specs/catalog-parser-unification-spec.md）。
# ここでは CatalogEntry → Entry への変換のみを行う。
def load_catalog_entries
  Build::CatalogLoader
    .load_labeled_entries(catalog_path:, contents_dir:)
    .map { instantiate_entry(it.basename, it.label, section_to_kind(it.section), in_catalog: true) }
    .uniq(&:number)
end
```

- ファイル冒頭に `require_relative 'build/catalog_loader'` を追加
  （`catalog_loader.rb` は他ファイルを require しないため循環はない）。
- `section_to_kind` は維持（fallback 用。実際の kind は `instantiate_entry` 内の
  `KIND_RANGES` が番号レンジから決めるため、挙動は従来どおり）。
- `File.exist?` ガード・`uniq(&:number)` の契約（カタログなし → `[]`、重複番号は先勝ち）は維持。
- 従来あった `.compact` は不要（`instantiate_entry` は nil を返さない）。

### 3.3 `Metrics` — 独自ローダーの廃止

- `metrics/runner.rb` の `resolve_from_catalog` を TokenResolver へ乗せ替え:

```ruby
# catalog.yml から有効章を解決する。
# metrics は統計ツールのため catalog 破損でもハード停止せず、
# 書ける範囲で答える（warn + 全 Markdown フォールバック）。
def resolve_from_catalog
  entries = TokenResolver::Resolver.new.resolve
  paths = entries.select(&:exists?).map(&:path)
  paths.any? ? paths : glob_all_chapters
rescue StandardError => e
  Common.log_warn("catalog.yml の読み込みに失敗したため、全 Markdown ファイルを対象にします: #{e.message}")
  glob_all_chapters
end
```

- `lib/vivlio_starter/cli/metrics/catalog_loader.rb` を**ファイルごと削除**し、
  `runner.rb` の `require_relative 'catalog_loader'`・`@catalog_loader` ivar・
  `attr_reader :catalog_loader` を撤去する。
- `test/vivlio_starter/cli/metrics/catalog_loader_test.rb` も削除する
  （検証対象の消滅による削除。カバーしていた振る舞いは §4 の新テストが引き継ぐ）。

従来の挙動（catalog 不在/空 → glob、破損 → warn + glob、存在する章のみ選択）は
上記コードで完全に保存される。

### 3.4 エラー処理ポリシー（呼び出し側の責務）

| 状況 | CatalogLoader（下層） | TokenResolver | build/preflight 等 | metrics |
|---|---|---|---|---|
| catalog 不在 | `load_labeled_entries` → `[]`（`load_all_basenames` は従来どおり raise） | `[]` | guards（CatalogFileCheck）が 🔴 停止 | glob フォールバック |
| YAML 破損 | 親切メッセージの StandardError を raise | 伝播 | `ensure_required_yaml_files!` が先に abort（通常は到達しない） | rescue → warn + glob |
| 空カタログ | `load_labeled_entries` は検証しない | `[]` | `build_command` が「章が定義されていません」ログ（既存） | glob フォールバック |

### 3.5 意図的な挙動変更の一覧

1. **エイリアス使用時に TokenResolver 系が動くようになる**（バグ1解消）。
2. **catalog.yml 内のショートハンドが TokenResolver 系でも展開される**（バグ2解消）。
   波及先はすべて改善方向: orphan_file_check（ショートハンド対象章を孤立扱いしない）、
   catalog_entries_check（幽霊エントリの偽警告が消える）、付録レター採番、
   pre_process 相互参照の章集合、lint の全章リスト。
3. **未知トップレベルセクションは無視に統一**（従来 TokenResolver だけが取り込んでいた）。
   catalog_spec の定める 4 セクションが正であり、タイプミス（`CHAPTER:` 等）を
   静かに取り込むより無視のほうが安全。ただし黙って落とすと調査困難なため、
   `load_labeled_entries` で未知キーを検出したら `Common.log_warn` で
   「未知のセクションです（有効: PREFACE/CHAPTERS/APPENDICES/POSTFACE）」と知らせる。
4. **パースエラーが CatalogLoader の親切メッセージ**（修復手順つき StandardError）になる
   （従来 TokenResolver 経由は生の Psych 例外）。
5. **命名規約の明文化**: 数字のみの slug（`21-25.md` のようなファイル名）はショートハンドと
   区別できないため非サポート（`shorthand?` の既存判定 `\A\d+-[a-zA-Z]` を正とする）。
   これは CatalogLoader では従来から同じであり、新たな制限ではない。
6. **番号のみファイルの glob 対象化**（実装時に発見・追加）: bare number の catalog エントリ
   （`- 15`）に対し、`find_basenames_by_number` は従来 `NN-*.md`（slug 付き）のみ glob していたため
   番号のみファイル `15.md` を落としていた。これは TokenResolver（従来 `15.md` を拾う）との乖離
   （統一前は build 内で build_command と chapter_config が食い違う原因）だったため、`NN.md` も
   glob 対象に含めて両者を一致させた。slug 付きを先に、番号のみを後に並べる。

### 3.6 変更しないこと（非目標）

- **`Build::CatalogUpdater` の行ベーステキスト編集** — コメント・並び保持のため
  意図的に YAML を経由しない設計（正しい）。
- **`doctor/config_salvager`** — 破損 catalog を前提にパースせず再構築する設計（正しい）。
- **`import/yaml_processor`** — 移行元（他ツール）プロジェクトの catalog を読む別物。
- **`Common.ensure_required_yaml_files!`** — 内容を消費しない存在・解析可能性の検証専用。
- **キャッシュ導入** — catalog は create/rename/delete 中に書き換わり、都度読み直しが
  正しさの前提になっている。パフォーマンス最適化は別タスク（必要になってから）。

## 4. テスト計画

- **新設 `test/vivlio_starter/cli/build/catalog_loader_test.rb`**（`load_labeled_entries` 中心）:
  - ラベル伝播（部タイトル配下 → 部タイトル、直下 → セクション名）
  - ショートハンド `21-25` / `21-23, 25` の展開（contents_dir 注入で fixtures 利用）
  - エイリアス（`&x` / `*x`）を含む catalog のパース成功
  - catalog 不在 → `[]`（raise しない）／破損 → StandardError
  - 未知セクションキーの無視＋warn
  - **同値性保証**: 代表 catalog で `load_all_basenames == load_labeled_entries.map(&:basename)`
    （パーサ一本化のリグレッションゲート）
- **`token_resolver_test.rb` へ追加**:
  - バグ1回帰: エイリアス入り catalog で `resolve` が成功する
  - バグ2回帰: catalog 内 `21-25` が 21〜25 章の Entry に展開される（幽霊エントリでない）
  - 破損 YAML → 親切メッセージの StandardError
- **`metrics/runner_test.rb` へ追加**:
  - 破損 catalog → warn ログ＋glob フォールバックで解析続行
  - catalog 不在 → glob フォールバック（既存挙動の保存確認）

## 5. 実装手順（コミット分割の目安）

1. **CatalogLoader**: kwargs パラメタ化＋`CatalogEntry`/`load_labeled_entries`/`collect_labeled`
   追加＋新テスト（既存消費側は無変更のまま green を確認）
2. **TokenResolver**: `load_catalog_entries` 委譲化・自前パース削除＋バグ1/2 の回帰テスト
3. **Metrics**: `resolve_from_catalog` 乗せ替え＋`metrics/catalog_loader.rb` と同テスト削除
4. **仕上げ**: CHANGELOG（Fixed にバグ2件・Changed にパーサ一本化）、
   config-access-unification-spec §4 から本仕様への参照更新

各段階で `rake test`。全段階完了後に `rake test:standard` と、
実プロジェクトで `vs build`（PDF/EPUB/Kindle）・`vs metrics`・`vs lint`・`vs preflight` を実走。
さらに実プロジェクトの catalog.yml に一時的にエイリアスとショートハンドを書いて
ビルドが通ること（バグ1/2 の実地確認）を行い、元に戻す。

## 6. 範囲外（関連タスク）

- `page_presets.yml` / `post_replace_list.yml` のアクセス統一 — **完了済み**
  （読み込みは各 1 箇所に一元化済み。`safe_load` への揃えも 2026-07-03 実施）。
- catalog 読み込みのキャッシュ/メモ化 — §3.6 のとおり非目標。必要になった時点で別仕様。
