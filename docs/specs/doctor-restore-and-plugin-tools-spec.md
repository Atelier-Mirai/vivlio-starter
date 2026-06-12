# Vivlio Starter Phase 5: doctor 設定復元 / プラグインツール統合 仕様書

| 項目 | 内容 |
|---|---|
| 文書名 | Phase 5: doctor による設定ファイル復元・プラグイン外部ツール統合 仕様書 |
| 対象 | vivlio-starter Gem v1.0.0-beta 以降 / vivlio-starter-pdf プラグイン |
| 関連 | `docs/specs/precondition-guard-spec.md`（Phase 1〜4） |
| 位置づけ | Precondition Guard 段階導入計画の Phase 5 |
| 作成 | 2026-06-11 |

---

## 1. 背景と目的

Phase 1〜4 で、コマンド実行前に前提条件違反を検出・停止する Guard/Check 基盤を整備した。
Phase 5 では「検出した違反を **修復** する」側へ踏み込む。対象は次の 2 件。

1. **設定ファイル復元**: 利用者が `config/book.yml` / `config/catalog.yml` 等を誤って削除・破損させた場合に、`vs doctor --fix` で `project_scaffold` から安全に復元する。
2. **プラグイン外部ツール統合**: Enhanced Mode（`vivlio-starter-pdf`）が必要とする OCR 系外部ツール（tesseract / tesseract-lang / poppler / vips）の案内・診断を、本体 `vs doctor` 側へ統合する。

### 1.1 現状調査の結論（実装前の事実確認）

| 観点 | 現状 |
|---|---|
| OCR ツールの `--fix` インストール | **既に実装済み**。`doctor.rb` の `checks` に tesseract / tesseract-lang / vips / poppler が含まれ、`--fix` で `brew install` される |
| scaffold からの設定復元 | textlint 系のみ実装済み（`copy_textlint_assets_from_scaffold!`）。book.yml / catalog.yml は未対応 |
| YAML 妥当性検証 | `Common.ensure_required_yaml_files!` が存在・妥当性を検証（ただし違反時は `abort`） |
| プラグインの案内 | プラグインの `post_install_message` が手動 `brew install tesseract …` を促す（doctor が自動化済みなのに重複案内） |
| OCR ツールの診断条件 | プラグイン非導入時も無条件に「不足」報告される（Enhanced Mode 専用なのに区別なし） |

> したがって Phase 5 の実体は「新規インストール処理の追加」ではなく、**(A) 設定ファイル復元の新設**と、**(B) プラグイン連動による診断・案内の整理**である。

### 1.2 ライセンス上の整理（設計の前提）

`vivlio-starter-pdf` を別 gem に分離した理由は **HexaPDF（AGPL）を本体の Ruby 依存として bundle しない**ことにある。
一方、tesseract / poppler / vips は subprocess で呼び出す外部 CLI であり、本体 gem が `brew install` を実行してもライセンス感染は発生しない。
**OCR ツールのインストール・診断を本体 doctor が担うことは、プラグイン分離の方針と矛盾しない。**

---

## 2. スコープ

### 2.1 含む

- `config/` 配下全体（YAML 各種 + 辞書ディレクトリ）の欠落・破損からの復元（`vs doctor --fix` の一部）
- 復元時のバックアップ・プレースホルダ展開・対話確認
- 破損ファイルからのサルベージ復元（機能 D・best-effort）
- YAML 妥当性検証の Check 化（Guard 層との共有）
- プラグイン検出に連動した OCR ツール診断のラベル整理
- プラグイン `post_install_message` の文言修正

### 2.2 含まない

- HexaPDF や OCR ツールを本体の **Ruby 依存**として追加すること（方針に反する）
- Windows / Linux でのパッケージ自動インストール（既存どおり macOS/Homebrew のみ）
- 破損 YAML を「正しく直す」こと。本仕様の復元は **全体置換 + バックアップ**が基本であり、機能 D のサルベージはあくまで「**再入力削減の最善努力（best-effort）**」であって正確性は保証しない。誤抽出があってもバックアップ（`.bak`）に原本が残るため破壊にはならない、という前提に立つ。

---

## 3. 機能 A: 設定ファイル復元

### 3.1 対象範囲

`config/` 配下のうち scaffold に同名で存在する全エントリ（ファイル + ディレクトリ）を対象とする。
本体リポジトリと scaffold の `config/` は**全エントリが一致**していることを確認済み（2026-06-11）。

| エントリ | 種別 / scaffold の形態 | 復元方針 |
|---|---|---|
| `config/book.yml` | ファイル / プレースホルダ入りテンプレート（`{{MAIN_TITLE}}` 等 5 箇所） | プレースホルダを既定値へ展開して復元（破損時は機能 D でサルベージ） |
| `config/catalog.yml` | ファイル / 実値 | scaffold を復元（破損時は機能 D で contents/ から再構築） |
| `config/page_presets.yml` | ファイル / 実値 | scaffold をそのまま復元 |
| `config/post_replace_list.yml` | ファイル / 実値 | scaffold をそのまま復元 |
| `config/textlint_allowlist.yml` | ファイル / 実値 | scaffold をそのまま復元（既存の textlint 復元と統合） |
| `config/textlint_prh.yml` | ファイル / 実値 | scaffold をそのまま復元（同上） |
| `config/.textlintrc.yml` | ファイル / 実値 | scaffold をそのまま復元（同上） |
| `config/spellcheck_dictionaries/` | ディレクトリ | 欠落時のみ scaffold から再帰コピー |
| `config/textlint_dictionaries/` | ディレクトリ | 欠落時のみ scaffold から再帰コピー（既存復元と統合） |

> book.yml のプレースホルダ展開は `vs new` の `rewrite_book_yml` / `yaml_escape_double_quoted` と同等の処理。
> ただし doctor では対話入力を行わず、`{{MAIN_TITLE}}` → 「新しい本」等の**既定値**へ静的展開する（`NewCommands::DEFAULT_ANSWERS` 相当）。
>
> **既存の `copy_textlint_assets_from_scaffold!` との統合**: textlint 系 4 点（`.textlintrc.yml` / `textlint_allowlist.yml` / `textlint_prh.yml` / `textlint_dictionaries/`）は既に scaffold 復元が実装済み。本機能の復元ロジックへ吸収し、二重実装を避ける（`copy_textlint_*` は新ロジックへ委譲または統合）。
>
> **ディレクトリの扱い**: `spellcheck_dictionaries/` / `textlint_dictionaries/` は YAML ではないため「破損」判定はせず、**ディレクトリが存在しない場合のみ**再帰コピーで復元する（中身の個別検証は行わない）。
>
> **`_README.md`**: scaffold にも存在する。利用者の編集対象ではないが、誤って削除することも考えられる為、存在しない場合には復元対象とする（欠落しても機能に影響しないが、利用者の利便性向上に繋がる）。

### 3.2 復元の判断と安全規約（最重要）

利用者の編集物を破壊しないことを最優先とする。

| 状況 | 判定 | アクション |
|---|---|---|
| ファイルが**存在しない** | 欠落 | scaffold から復元する（バックアップ不要） |
| ファイルが**存在し妥当な YAML** | 正常 | **触らない**（既存を尊重） |
| ファイルが**存在するが不正な YAML** | 破損 | `<path>.bak.<timestamp>` へ退避 → scaffold から復元（退避先を明示表示） |

**規約**
- 破損ファイルを**バックアップなしに上書きしてはならない**。
- 復元は `--fix` 指定時のみ実行する。`--fix` なしの `vs doctor` は検出・報告のみ。
- 非対話（`--yes`）時はバックアップを取った上で自動復元。対話時は復元可否を確認する。
- 復元後は「`vs new` で作られる初期状態に戻った」旨と、バックアップから設定を書き戻す導線を案内する。

### 3.3 出力例

```
# 欠落の場合
🔴 設定ファイルが見つかりません: config/catalog.yml
✅ config/catalog.yml を初期状態から復元しました

# 破損の場合（--fix）
🔴 設定ファイルが不正です: config/book.yml（YAML 解析に失敗）
        破損したファイルを config/book.yml.bak.20260611_143022 へ退避しました
✅ config/book.yml を初期状態から復元しました
        以前の設定は上記バックアップから書き戻せます

# --fix なし
🔴 設定ファイルが不正です: config/book.yml（YAML 解析に失敗）
        修復するには vs doctor --fix を実行してください
```

---

## 3D. 機能 D: 破損ファイルからのサルベージ復元（best-effort）

機能 A の「破損 → バックアップ + scaffold で全体置換」は安全だが、利用者が入力済みの書名・著者・章構成まで初期値に戻ってしまう。
機能 D は **3.2 のバックアップを取った後・scaffold 置換の前に**、破損ファイルから救出できる値を最善努力で抽出し、置換後のファイルへ書き戻して再入力を減らす。

### 3D.1 大原則

- **正確性は保証しない**。抽出は「破損箇所がその値の行に無ければ拾える」程度のもの。
- **必ず .bak を残す**（機能 A の規約）。誤抽出・取りこぼしがあっても原本から確認できる。
- 書き戻した値には**「復元値（要確認）」を明示**し、利用者に検証を促す。正しさを主張しない。
- サルベージに失敗しても**機能 A の素の復元へフォールバック**する（例外を握りつぶして既定値復元に進む）。

### 3D.2 catalog.yml — ファイルシステムからの再構築（パースしない）

破損した catalog.yml を解析するのではなく、**`contents/*.md` から章構成を再構築**する。これが最も確実。

- 章スラッグ: `contents/` の `NN-slug.md` から取得（アンダースコア始まりのシステムページは除外）。
- セクション割当（PREFACE / CHAPTERS / APPENDICES / POSTFACE）: 章番号から決定。`TokenResolver` の `KIND_RANGES`（`0=preface / 1-89=chapter / 90-98=appendix / 99=postface`）を再利用する。
- 順序: 章番号の昇順。

**復元できない情報（明示する）**:
- **部タイトル**（`【第一部：…】`）— catalog.yml にしか存在しない。
- **意図的な除外**（コメントアウトされた章）— 同上。

> 章構成そのものは高精度で戻るが、部タイトルと除外意図は失われる。出力で「部タイトル・除外設定は復元されません。必要なら .bak から書き戻してください」と案内する。

### 3D.3 book.yml — 行ベース正規表現での最善努力抽出

YAML パースが失敗しても、`key: "value"` 形式の**トップレベル単一行スカラー**は行スキャンで拾える。

**抽出対象（救出できる見込みが高い項目に限定）**:

| キー | 例 | パターン |
|---|---|---|
| `main_title` / `subtitle` | `main_title: "..."` | `^\s{2}main_title:\s*["']?(.+?)["']?\s*(#.*)?$` |
| `author` / `publisher` / `series` / `release` / `contact` | 同上 | 同様の単一行パターン |
| `project.name` | `  name: "..."` | 同上 |

**抽出しない（取りこぼし容認）**:
- `legal.disclaimer` / `trademark` / `twemoji` 等の**複数行ブロックスカラー（`|` 記法）** — 行スキャンでは境界を正しく判定できないため対象外。これらは .bak からの手動コピーに委ねる。
- ネスト構造・配列値 — 正確な復元が困難なため対象外。

**手順**:
1. 破損 book.yml を行単位で読み、上記キーを抽出（破損行は単に拾えないだけで処理は継続）。
2. scaffold テンプレートのプレースホルダを、抽出値があればそれで、無ければ既定値で展開。
3. 抽出した値が 1 件でもあれば「以下を復元値として書き戻しました（要確認）」と一覧表示。

### 3D.4 出力例

```
🔴 設定ファイルが不正です: config/catalog.yml（YAML 解析に失敗）
        破損したファイルを config/catalog.yml.bak.20260611_143022 へ退避しました
✅ config/catalog.yml を contents/ から再構築しました（11 章）
        ⚠️ 部タイトル・除外設定は復元されません。必要なら上記バックアップから書き戻してください

🔴 設定ファイルが不正です: config/book.yml（YAML 解析に失敗）
        破損したファイルを config/book.yml.bak.20260611_143027 へ退避しました
✅ config/book.yml を復元し、以下の値を救出しました（要確認）:
        - main_title: はじめての技術書づくり
        - author: アトリヱ未來
        ⚠️ 免責・商標などの複数行設定は復元されません。必要なら上記バックアップから書き戻してください
```

---

## 4. 機能 B: 設定妥当性 Check の共有（Guard 層との連携）

### 4.1 新規 Check

`Common.ensure_required_yaml_files!` の検証ロジック（存在 + `YAML.safe_load` が Hash/Array か）を
**abort しない Check** として切り出し、Guard 層・doctor 層で共有する。

```ruby
# lib/vivlio_starter/cli/guards/config_validity_check.rb
module VivlioStarter::CLI::Guards
  # 必須 YAML が存在し、かつ妥当な YAML として解析できるかを検証する。
  # 存在のみを見る CatalogFileCheck より厳格（破損も検出する）。
  class ConfigValidityCheck < BaseCheck
    # @param paths [Array<String>] 検証対象（既定: Common::REQUIRED_YAML_FILES）
    def initialize(paths: Common::REQUIRED_YAML_FILES)
      @paths = paths
      super()
    end

    def validate
      @paths.filter_map { check_one(it) }
    end

    private

    def check_one(path)
      return error("設定ファイルが見つかりません: #{path}") unless File.file?(path)

      parsed = YAML.safe_load(File.read(path, encoding: 'utf-8'), aliases: true)
      return nil if parsed.is_a?(Hash) || parsed.is_a?(Array)

      error("設定ファイルの内容が空または不正です: #{path}")
    rescue StandardError => e
      error("設定ファイルの YAML 解析に失敗しました: #{path}", detail: e.message)
    end
  end
end
```

### 4.2 既存 Check との関係

| Check | 検証範囲 | 主な利用元 |
|---|---|---|
| `CatalogFileCheck` | catalog.yml の**存在**のみ | build / lint / 各コマンド Guard（軽量・高速） |
| `ConfigValidityCheck` | 必須 YAML 4 種の**存在 + 妥当性** | doctor（修復判断の根拠）／ preflight の網羅診断 |

> コマンド冒頭の Guard には軽量な `CatalogFileCheck` を維持し、`ConfigValidityCheck` は doctor / preflight の「丁寧な診断」側に置く。役割分担は Phase 1〜4 の「Guard は弾く / preflight・doctor は診断する」方針を踏襲する。

### 4.3 doctor からの利用

doctor は `ConfigValidityCheck#validate` の結果を用いて 3.2 の判定（欠落 / 正常 / 破損）を行い、
`--fix` 時に復元する。doctor 専用に YAML 検証を再実装しない。

---

## 5. 機能 C: プラグイン外部ツールの診断統合

### 5.1 プラグイン検出

`vivlio-starter-pdf` が利用可能かを判定する（既存の provider 検出ロジックを再利用）。
OCR ツール（tesseract / tesseract-lang / vips / poppler）は **Enhanced Mode 専用**のため、
診断表示をプラグインの有無で出し分ける。

| プラグイン状態 | OCR ツールの扱い |
|---|---|
| 導入済み | 通常の必須ツールとして「不足」を報告し `--fix` で導入（現状どおり） |
| 未導入 | 「（任意: pdf:read Enhanced Mode 用）」と注記し、不足でも**エラー扱いにしない** |

> 現状は未導入でも無条件に「不足」と報告していた。これを区別し、プラグインを使わない利用者へのノイズを減らす。
> なお `--fix` で OCR ツールを導入する挙動自体は維持する（先回りインストールは許容範囲）。

### 5.2 出力例

```
# プラグイン未導入時
🟡 任意ツール（pdf:read Enhanced Mode 用・vivlio-starter-pdf 利用時に必要）:
        - tesseract / tesseract-lang（OCR エンジン）
        - vips（画像処理）
        gem install vivlio-starter-pdf 後、vs doctor --fix でまとめて導入できます
```

### 5.3 プラグイン側 post_install_message の修正

`vivlio-starter-pdf.gemspec` の `post_install_message` を、手動 `brew install` の列挙から
**本体 doctor への誘導**へ改める。

```
[vivlio-starter-pdf]
Enhanced Mode の OCR には外部ツール（tesseract / tesseract-lang / poppler / vips）が必要です。
  vs doctor --fix
で本体側からまとめて導入できます（macOS / Homebrew）。
手動の場合: brew install tesseract tesseract-lang poppler vips
```

> プラグインは本体 gem のリポジトリ外のため、この修正は**別リポジトリでの作業**となる。本仕様書では方針のみ規定し、本体側の実装とは独立して進める。

---

## 6. 実装方針（本体 gem）

### 6.1 ファイル構成

| ファイル | 変更 |
|---|---|
| `lib/vivlio_starter/cli/guards/config_validity_check.rb` | 新規（4.1） |
| `lib/vivlio_starter/cli/guards.rb` | `require` 追加 |
| `lib/vivlio_starter/cli/doctor.rb` | 設定復元（3章 + 機能 D）・OCR 診断ラベル整理（5章）を追加。既存 `copy_textlint_assets_from_scaffold!` を新復元ロジックへ統合 |
| `lib/vivlio_starter/cli/doctor/config_salvager.rb`（新規・任意） | 機能 D のサルベージ抽出（catalog 再構築 / book.yml 行スキャン）。doctor.rb の肥大化を避けるため切り出す |

### 6.3 doctor への追加メソッド（イメージ）

```ruby
# config 復元（--fix 時）。既存の copy_textlint_assets_from_scaffold! と同じ scaffold 起点。
def restore_config_files!(options)
  # ファイル: 欠落 or 破損を ConfigValidityCheck で判定して復元
  Guards::ConfigValidityCheck.new.validate.each do |violation|
    path = extract_path(violation)

    if File.file?(path)
      # 破損: 必ず .bak へ退避してから（機能 A の規約）
      backup = backup_corrupt_file!(path)
      # 機能 D: 退避後・置換前にサルベージを試みる（失敗は握りつぶし素の復元へ）
      salvaged = ConfigSalvager.salvage(path, backup) rescue nil
    end

    restore_from_scaffold!(path, salvaged:) # book.yml はプレースホルダ展開（salvaged 優先）
  end

  # ディレクトリ: 欠落時のみ再帰コピー（YAML 検証はしない）
  restore_missing_dirs!(%w[spellcheck_dictionaries textlint_dictionaries])
end
```

- `restore_from_scaffold!` は `copy_textlint_*` と同じ `gem_root/lib/project_scaffold/config/` を参照。
- book.yml のプレースホルダ展開は `NewCommands` の既存ロジックを抽出・共有するか、doctor 内に最小限で実装する（過剰共有を避ける。Phase 3 の `RelaxedCheck` 同様、必要十分な範囲に留める）。
- `ConfigSalvager.salvage` は破損ファイルから救出値を返す（catalog: contents/ から章配列を再構築 / book.yml: 行スキャンで scalar Hash を返す）。例外時は `nil` を返し、素の scaffold 復元へフォールバックする。

---

## 7. テスト仕様（Minitest）

### 7.1 ConfigValidityCheck（Check 単体）

| ID | 前提 | 期待 |
|---|---|---|
| CV-01 | 4 種すべて存在・妥当 | 違反 0 件 |
| CV-02 | catalog.yml 欠落 | :error 1 件・該当パス |
| CV-03 | book.yml が不正 YAML（`{{` 等の壊れた内容） | :error 1 件・YAML 解析失敗を detail に |
| CV-04 | book.yml の中身が空 | :error 1 件 |

### 7.2 設定復元（doctor）

| ID | 前提 | 期待 |
|---|---|---|
| DR-01 | catalog.yml 欠落 + `--fix` | scaffold から復元・ファイルが妥当 YAML になる |
| DR-02 | book.yml 破損 + `--fix` | `.bak.<ts>` が作られる・本体は妥当・プレースホルダが残らない |
| DR-03 | 妥当な book.yml + `--fix` | **変更されない**（バックアップも作らない） |
| DR-04 | 破損 + `--fix` なし | 復元しない・`vs doctor --fix` を案内する |
| DR-05 | `spellcheck_dictionaries/` 欠落 + `--fix` | scaffold から再帰コピーで復元される |
| DR-06 | `spellcheck_dictionaries/` が存在（中身一部欠け） + `--fix` | **触らない**（ディレクトリは存在のみ判定） |

### 7.3 サルベージ復元（機能 D）

| ID | 前提 | 期待 |
|---|---|---|
| SV-01 | catalog.yml 破損 + contents/ に NN-slug.md 群 | catalog が contents/ から再構築され、章番号順・正しいセクションに配置される |
| SV-02 | catalog.yml 破損 + 部タイトル/除外あり | 章は復元されるが部タイトル・除外は失われる旨が案内される |
| SV-03 | book.yml 破損（title 行は無傷） | main_title / author 等が救出され、復元ファイルに反映される |
| SV-04 | book.yml 破損（title 行自体が破損） | 当該値は救出されず既定値になる・他の無傷行は救出される（取りこぼし容認） |
| SV-05 | サルベージ中に想定外例外 | 機能 A の素の復元へフォールバックする（exit せず復元は完了する） |

> サルベージは「best-effort」のため、SV-04 のように取りこぼしが起きても**テストはそれを許容**する（救出できた分だけ反映され、原本は .bak に残る）ことを保証する。

### 7.4 プラグイン連動診断

| ID | 前提 | 期待 |
|---|---|---|
| PT-01 | プラグイン未導入（検出を stub） | OCR ツール未導入が :error にならず 🟡 注記で表示 |
| PT-02 | プラグイン導入（検出を stub） | OCR ツール未導入が通常の不足として報告 |

> DI: プラグイン検出・`File`/scaffold パス・`brew` 実行は注入またはテンポラリプロジェクトで差し替え、グローバル状態を汚さない（Phase 1〜4 のテスト方針を踏襲）。

---

## 8. 段階的導入計画（Phase 5 内）

| ステップ | 内容 | 優先度 | 状態 |
|---|---|---|---|
| 5-1 | `ConfigValidityCheck` を新設し Guard 層へ追加（テスト CV-01〜04） | 高 | ✅ 実装済み（2026-06-11） |
| 5-2 | doctor の設定復元（config 配下全体: 欠落→復元、破損→バックアップ+復元、ディレクトリ→欠落時コピー、--fix ガード）。既存 `copy_textlint_*` を統合（DR-01〜06） | 高 | ✅ 実装済み（2026-06-11） |
| 5-3 | 機能 D サルベージ（catalog は contents/ 再構築 / book.yml は行スキャン / 失敗時フォールバック）（SV-01〜05） | 中 | ✅ 実装済み（2026-06-11） |
| 5-4 | doctor の OCR ツール診断をプラグイン検出に連動（PT-01〜02） | 中 | ✅ 実装済み（2026-06-11） |
| 5-5 | プラグイン側 post_install_message を doctor 誘導へ修正（別リポジトリ） | 低 | ✅ 実装済み（2026-06-11・vivlio-starter-pdf リポジトリ） |

> 5-2 までで「再入力は発生するが安全な復元」が完成する。5-3 は再入力削減の上乗せであり、独立して後追い実装できる（5-3 未実装でも 5-2 の素の復元として機能する）。

---

## 9. 補足: 既存実装との非重複確認

- OCR ツールの `brew install` 自体は**既存**（`doctor.rb` の `--fix`）。Phase 5 で重複追加しない。
- textlint 設定の scaffold 復元は**既存**（`copy_textlint_assets_from_scaffold!`）。設定復元（機能 A）はこの仕組みを config 配下全体へ横展開し、textlint 系も新ロジックへ**統合**する（二重実装にしない）。
- YAML 検証は `Common.ensure_required_yaml_files!` に**既存**。Check 化で abort しない形へ切り出し共有する（ロジック二重化を避ける）。
- 章番号→セクション判定は `TokenResolver::KIND_RANGES` に**既存**。機能 D の catalog 再構築はこれを再利用する（判定ロジックを複製しない）。

---

## 10. サルベージ精度の前提（合意事項）

機能 D の精度は次の理解で合意済み（2026-06-11）。実装・レビュー時の判断基準とする。

- **catalog.yml**: 章構成（スラッグ・順序・セクション）は contents/ から**高精度**で再構築できる。部タイトルと意図的除外は**構造上復元不能**で、これは仕様上の制約として受け入れる（案内で明示）。
- **book.yml**: トップレベル単一行スカラーは**最善努力で抽出**。複数行ブロックスカラー（legal.*）と、破損箇所がその値の行にある場合は**取りこぼす**。これは欠陥ではなく仕様（best-effort）。
- 取りこぼし・誤抽出はいずれも `.bak` に原本が残るため**非破壊**。サルベージは「再入力削減の利便機能」であり、正確性の保証機能ではない。
