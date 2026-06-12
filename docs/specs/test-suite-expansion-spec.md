# Vivlio Starter テストスイート拡充仕様書（RC 品質保証）

| 項目 | 内容 |
|---|---|
| 文書名 | テストスイート拡充仕様書（パッケージング / 成果物検査 / ファズ / 契約 / 冪等性 ほか） |
| 対象 | vivlio-starter Gem v1.0.0-beta 以降（RC 移行前の品質保証） |
| 関連 | `docs/specs/precondition-guard-spec.md` / `docs/specs/doctor-restore-and-plugin-tools-spec.md` / `test/vivlio_starter/robustness/README.md` |
| 位置づけ | 既存スイート（単体・統合・ロバストネス・前提条件・判型）を補完する 11 グループの新設 |
| 作成 | 2026-06-12 |

---

## 1. 背景と目的

RC 移行に向けて、既存テストが**カバーしていない種類の欠陥**を対象とするテスト群を追加する。
選定は「このプロジェクトが過去に実際に踏んだ不具合」からの逆算を基本とする。

| 過去の不具合（実績） | 対応する新テスト |
|---|---|
| gem パッケージングの同梱漏れ・混入（ホワイトリスト化で 430MB→55MB） | PK: パッケージング E2E |
| Chromium / Vivliostyle 由来の Type 3 フォント混入 | FT: PDF フォント検査 |
| VFM 2.x の脚注定義入れ替え（上流更新による破壊） | CN: 依存カナリア |
| 破損 YAML での起動 abort・スタックトレース（Phase 5 で修復系を追加） | FZ: ファズ / プロパティ |
| `copy_textlint_*` が誤パス参照で何もコピーしていなかった | MB / PK: 実環境での E2E 検証 |
| 外部ツール不在時の生ログ露出（robustness 4-1 系で一部対応済み） | DG: 機能縮退テスト |

### 1.1 既存テスト資産と新テストの分担（重複させない）

| 既存 | 守備範囲 | 新テストとの境界 |
|---|---|---|
| `rake test`（単体・統合） | ロジックの入出力 | 新テストはロジックを再検証しない |
| `robustness/` | 悪意ある入力・割り込み・外部コマンド不在の**エラーメッセージ品質**（`missing_external_command_test.rb` は vivliostyle / inkscape / imagemagick の3件） | DG は「**不在でも機能縮退して完走する**」挙動を対象とし、メッセージ品質の再検証はしない。NF は robustness へ追加配置 |
| `guards/` + 各コマンドテスト | 前提条件違反の検出・終了コード | CL は Guard ロジックを再検証せず、**help / 終了コードの契約**のみ対象 |
| `samovar_smoke_test.rb` | コマンド → ドメイン層の解決・呼び出し | CL は解決確認を再実装しない |
| `page_layout/`（`rake test:layout`） | 判型（MediaBox 等）の寸法 | MB / FT は判型を再検証せず、同じ「実ビルド + pdf-reader 検査」のインフラ（`BookYmlPatcher` / `VsBuilder` 相当）を**共通ヘルパーへ抽出して共用**する |

---

## 2. スコープ

### 2.1 含む

- 新テスト 11 グループ（MB / FT / PK / FZ / DG / NF / CL / DC / ID / EP / CN）
- 実行階層の整理（`rake test` への組み込み可否、新規 rake タスク）
- `page_layout_test.rb` 内のビルド補助モジュールの共通ヘルパー化（テスト支援コードのみ）

### 2.2 含まない

- 本体ロジックの変更（テストが新たな不具合を発見した場合は**別タスクとして切り出す**。テスト導入と修正を混ぜない）
- GitHub Actions の CI 整備そのもの（§14 に方針のみ記す。現状 workflows/ には labeler のみ）
- ミューテーションテスト・性能ベンチマーク（RC 後の検討事項とする）

---

## 3. 実行階層と rake タスク設計

実ビルドを伴うテストは遅い（1 ビルド数十秒〜）。階層を明確に分ける。

| rake タスク | 内容 | 含むグループ | 実ビルド |
|---|---|---|---|
| `rake test`（既存） | 高速スイート。新規分を追加 | FZ / DG / NF / CL / DC（+ 既存全部） | なし |
| `rake test:layout`（既存） | 判型テスト | （既存のまま） | あり |
| `rake test:manual`（新設） | **リポジトリ実体＝マニュアルの実ビルドと成果物検査** | MB / FT / EP / ID | あり（原則 1 回を共有） |
| `rake test:package`（新設） | gem ビルド → 隔離インストール → 動作確認 | PK | あり |
| `rake test:release`（新設） | RC 前総点検の集約タスク | test → layout → manual → package を順次実行 | あり |
| `rake test:canary`（新設・任意） | 上流最新版での破壊検知 | CN | あり |

**Rakefile 変更点**
- `rake test` の除外パターンに `test/**/release/**` を追加（`page_layout` と同様）
- `custom_order` に新タスクを追記（`test`, `test:layout`, `test:manual`, `test:package`, `test:release`, `reinstall`）

**ディレクトリ構成**

```
test/vivlio_starter/
  fuzz/                  # FZ（rake test に含む）
  contract/              # CL / DC（rake test に含む）
  robustness/            # DG / NF を追加（rake test に含む）
  release/               # MB / FT / EP / ID / PK / CN（rake test から除外）
  support/build_helper.rb  # BookYmlPatcher / VsBuilder / PdfInspector の共通化
```

---

## 4. MB: マニュアルフルビルド（警告ゼロ）

### 4.1 目的

リポジトリ実体は「マニュアル原稿を `vs build` でビルドする dogfooding 構造」である。
これを**最重要の統合テスト**として固定する: フルビルドが exit 0 かつ警告ゼロで通ること。

### 4.2 「警告ゼロ」の定義

- `vs build` の標準出力・標準エラーに **🔴 行および 🟡 行が 1 行も含まれない**こと
- 既定ログレベル（warn）で実行する（🟡/🔴 は常時表示されるため検出可能）
- 終了コードが 0 であること

### 4.3 前提作業（導入時の一度きり・最重要）

導入前に現状のマニュアルビルドで出る警告を**棚卸しし、ゼロにしてから**テストを固定する
（生まれた瞬間から赤いテストにしない）。棚卸しで見つかった警告の修正は本仕様のスコープ外
タスクとして個別に処理する。意図して残す警告が存在する場合は、許容リスト
（`test/vivlio_starter/release/allowed_warnings.yml`）を設け、1 件ごとに理由をコメントで残す。

### 4.4 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| MB-01 | リポジトリルートで `vs build` | exit 0・PDF が生成される |
| MB-02 | 同上 | 出力に 🔴 行が無い |
| MB-03 | 同上 | 出力に 🟡 行が無い（許容リスト記載分を除く） |

### 4.5 実装方針

- `release/manual_build_test.rb`。**ビルドは 1 回だけ実行し、出力ログと生成 PDF をクラスレベルで共有**する（FT も同じ成果物を検査する）。
- 実行ディレクトリ汚染対策: ビルドはリポジトリ実体で行うため、テスト後に `vs clean` 相当の後始末を行う（`--no-clean` は使わない）。
- 必要ツールが無い環境では `skip`（CI 未整備のため、ローカル実行を前提とする）。

---

## 5. FT: PDF フォント検査（Type 3 回帰）

### 5.1 目的

Chromium / Vivliostyle 更新で再発し得る Type 3 フォント混入と、フォント非埋め込みを検出する。

### 5.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| FT-01 | MB-01 の生成 PDF | 全ページの全フォントに `Subtype /Type3` が**存在しない** |
| FT-02 | 同上 | 全フォントが埋め込み済み（FontDescriptor に FontFile 系キーを持つ。標準 14 フォントの例外は許容しない） |
| FT-03 | 同上 | 使用フォント名一覧に標準添付書体（Zen Old Mincho / Zen Kaku Gothic New / Zen Maru Gothic / hackgen35 のサブセット名）が含まれる |

### 5.3 実装方針

- 一次手段は **pdf-reader gem**（page_layout で導入済み）。`page.fonts` から Subtype / FontDescriptor を走査する。外部コマンド（pdffonts）への依存は増やさない。
- 検査ロジックは `support/build_helper.rb` の `PdfInspector` として実装し、page_layout からも将来利用可能にする。
- 失敗時は「ページ番号・フォント名・Subtype」を列挙して報告する（どの原稿が原因か追跡できるように）。

---

## 6. PK: パッケージング E2E

### 6.1 目的

gemspec ホワイトリスト方式の最大リスク「リポジトリでは動くが gem に入っていない」を検出する。

### 6.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| PK-01 | `gem build` した .gem の内容一覧 | `lib/project_scaffold/` の全ファイル（config / contents / stylesheets / fonts / templates / covers / codes / data / sources）と `bin/` が**リポジトリと同一構成**で含まれる |
| PK-02 | 隔離 `GEM_HOME` へインストール | `vs --version` / `vs --help` が exit 0 |
| PK-03 | 隔離環境の scaffold から一時プロジェクトを構成し `vs build` | exit 0・PDF 生成（インストール物のみで完結） |
| PK-04 | .gem の内容一覧 | `test/` `docs/` `contents/`（リポジトリ直下）`.claude/` `.github/` `*.bak*` `.DS_Store` が**含まれない**（混入の再発防止） |

### 6.3 実装方針と注意

- `release/packaging_test.rb`。`gem build` → `Gem::Package.new(path).contents` で一覧検査（PK-01/04 はインストール不要で高速）。
- PK-02/03 は `GEM_HOME`/`GEM_PATH`/`PATH` を一時ディレクトリへ向けて `gem install <built.gem>` し、サブプロセスで実行する。
- **`vs new` は使わない**: `vs new` は内部で `vs doctor --fix` を自動実行するため、テストから brew インストールや waifu2x ダウンロードが走る危険がある。代わりにインストール先の `lib/project_scaffold/` を一時ディレクトリへコピーし、book.yml のプレースホルダを既定値展開してプロジェクトを構成する（`vs new` の対話・doctor を経由しない）。
- 外部ツール（node / vivliostyle 等）はホスト環境のものを使う。不足環境では PK-03 のみ `skip`。

---

## 7. FZ: ファズ / プロパティテスト

### 7.1 目的

パーサ・サルベージ系に「任意入力で例外を出さない」という**性質**を保証する。
個別ケースの単体テスト（既存）では拾えない想定外入力を網羅する。

### 7.2 検証する性質

| ID | 対象 | 性質 |
|---|---|---|
| FZ-01 | `ConfigSalvager.salvage('config/book.yml', 任意文字列, scaffold)` | 例外を送出しない。戻り値は nil または「YAML.safe_load が Hash を返す content」を持つ Result |
| FZ-02 | `ConfigSalvager.salvage('config/catalog.yml', 任意文字列, scaffold)` + ランダムな contents/ 構成 | 同上（content は妥当な YAML） |
| FZ-03 | `TokenResolver::Resolver#resolve(任意トークン列)` | 例外を送出しない。戻り値は Entry の配列 |
| FZ-04 | `Guards::ConfigValidityCheck.diagnose(任意内容のファイル)` | 例外を送出しない。`:ok / :missing / :corrupt` のいずれかを返す |

### 7.3 実装方針

- 専用 gem は導入せず、Minitest 内の自前ジェネレータで実装する（依存追加を避ける）。
- 入力生成: (a) ランダムバイト列、(b) 妥当な YAML/トークンに対するランダム変異（1 文字削除・挿入・引用符破壊・全角混入・制御文字混入）、(c) 境界値（空・巨大・BOM 付き・CRLF）。
- **シードを固定**し（`Random.new(20260612)` 等）、`rake test` に含めても決定的・高速（1 性質あたり 100〜200 ケース・1 秒以内目安）に保つ。
- 失敗時は再現に必要な入力を `#inspect` でメッセージへ含める。

---

## 8. DG: 外部ツール欠落時のグレースフルデグラデーション

### 8.1 目的

任意ツールが 1 つ欠けた環境で、機能が**クラッシュではなく縮退**して完走することを保証する。
（robustness 既存分はエラーメッセージ品質が対象。本グループは「処理が完走するか」が対象）

### 8.2 テスト項目

| ID | 不在にするツール | 期待（縮退仕様） |
|---|---|---|
| DG-01 | mecab | 索引の読み自動推測が無効化され、index 処理は例外なく完走・🟡 で案内 |
| DG-02 | playwright / chromium | バックリンク重複排除ステップがスキップされ、ビルド相当処理が完走・🟡 で案内 |
| DG-03 | gs (Ghostscript) | `--compress` 指定時に圧縮スキップで完走・🟡 で案内（無指定時は影響なし） |
| DG-04 | waifu2x | resize の AI 拡大が通常リサイズへフォールバック・🟡 で案内 |

### 8.3 実装方針

- `robustness/tool_degradation_test.rb`。実ビルドはせず、該当ステップのドメイン層を
  `Common.external_command_available?` / 各 `command_exists?` の DI・スタブで「不在」にして呼び出す
  （doctor テストで確立済みのスタブパターンを踏襲。グローバル汚染しない）。
- **期待する縮退仕様が未定義（現状クラッシュする）ことが判明した場合は、本テストを pending とし修正タスクを切り出す**（テストと修正を混ぜない）。

---

## 9. NF: macOS 日本語ファイル名（NFD/NFC）

### 9.1 目的

macOS の HFS+/APFS は濁点・半濁点付きファイル名を NFD で保持するため、原稿中の NFC 表記
（`![](images/写真データ.png)`）と実ファイル名が Unicode 正規化差で不一致になる事故を検出する。

### 9.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| NF-01 | NFD 名の画像ファイル + NFC 表記で参照する原稿 | LinkImageValidator が「存在する」と判定する（正規化差で 🔴 にしない） |
| NF-02 | NFD 名の章ファイル（`11-ガイド.md` 相当）を catalog に NFC で記載 | TokenResolver が同一章として解決する |
| NF-03 | 逆方向（NFC ファイル + NFD 参照） | 同上 |

### 9.3 実装方針と注意

- `robustness/nfd_filename_test.rb`。`"が".unicode_normalize(:nfd)` 等でファイルを作成し検証する。
- **このテストは現行実装の不具合を発見する可能性が高い**（正規化処理が未実装の場合）。発見時は
  テストを `skip`（理由コメント付き）にして修正タスクを切り出す。期待仕様は「比較時に
  `String#unicode_normalize` で揃える」こと。
- 章スラッグの命名規約は英数字推奨だが、画像ファイル名は日本語が現実的に使われるため NF-01 を最優先とする。

---

## 10. CL: CLI 契約テスト（help / 終了コード）

### 10.1 目的

全コマンドが守るべき**外形上の契約**を一括で固定する。個別コマンドテストの網羅漏れを防ぐ。

### 10.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| CL-01 | 全 Public コマンドに `--help` / `-h` | exit 0・Usage 文字列を含む・🔴 を含まない |
| CL-02 | 未知のコマンド（`vs nosuchcommand`） | 非 0 終了・help への誘導メッセージ |
| CL-03 | `vs --version` / `vs --help` | exit 0・バージョン文字列 / コマンド一覧 |

### 10.3 実装方針

- `contract/cli_contract_test.rb`。コマンド一覧は root_command の登録から動的に取得し、
  **コマンドを追加すると自動的に契約対象へ入る**構造にする（一覧のハードコードはしない）。
- プロセス起動コストを抑えるため、可能な範囲で `CLI.start(argv)` をインプロセス実行 + `capture_io` で検証する（SystemExit を捕捉）。
- Guard の挙動検証（プロジェクト外で exit 1 等）は guards テスト既存分に委ね、ここでは重複させない。

---

## 11. DC: ドキュメント整合テスト

### 11.1 目的

マニュアル原稿（contents/）と実装の乖離（存在しないコマンド・オプションの記載、
新コマンドのドキュメント漏れ）を静的に検出する。

### 11.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| DC-01 | contents/*.md 中の `vs <サブコマンド>` 表記を抽出 | すべて実在するコマンドである（タイプミス・廃止コマンドの残骸を検出） |
| DC-02 | 全 Public コマンド一覧 | 各コマンドが contents/ のいずれかで言及されている（漏れは失敗ではなく一覧表示付きの失敗メッセージで列挙） |
| DC-03 | contents/*.md 中の `--オプション` 表記（コードスパン内） | 当該コマンドの `--help` 出力に存在する（誤検知が多い場合は許容リストで運用） |

### 11.3 実装方針

- `contract/docs_consistency_test.rb`。正規表現抽出のため誤検知が原理的に避けられない。
  **許容リスト（`contract/docs_allowlist.yml`）を初期整備し、リストにはエントリごとに理由コメントを必須とする。**
- DC-03 は導入コストと誤検知のバランスを見て、初期実装では「コマンド名のみ（DC-01/02）」に
  絞ってよい（段階導入）。

---

## 12. ID: 冪等性テスト

### 12.1 目的

「もう一度実行したら結果が変わる／壊れる」型の不具合（中間ファイル残留・二重変換）を検出する。

### 12.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| ID-01 | `vs build` を 2 回連続実行（マニュアル実体） | 2 回目も exit 0・**意味的同一性**が保たれる（§12.3） |
| ID-02 | `vs doctor --fix` を 2 回連続実行（完全なプロジェクト） | 2 回目は変更ゼロ（バックアップも新規復元も発生しない。DR-03 の全体版） |
| ID-03 | `vs build` → `vs clean` → `vs build` | 成果物が ID-01 と同等・clean 後に中間ファイルが残らない |

### 12.3 「意味的同一性」の定義（重要な落とし穴）

PDF は CreationDate / ID 等のメタデータを含むため**バイト一致では比較できない**。比較は次で行う:
- ページ数の一致
- 各ページ抽出テキストの一致（pdf-reader）
- アウトライン（しおり）構造の一致
- ファイルサイズの近似（±1% 目安）

### 12.4 実装方針

- `release/idempotency_test.rb`。MB と同じ実ビルド系のため `rake test:manual` 階層に置く。
  ただしビルド 2〜3 回を要するため、MB のビルド共有とは独立に実行する（タスク内で最後に回す）。

---

## 13. EP: EPUB 構造検証

### 13.1 目的

EPUB 出力（`output.targets: epub`）の構造妥当性を第三者バリデータで保証する。

### 13.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| EP-01 | targets を epub に切り替えてビルド | exit 0・.epub が生成される |
| EP-02 | 生成 .epub に `epubcheck` | FATAL / ERROR が 0 件（WARNING は初回棚卸しの上、許容リスト運用） |

### 13.3 実装方針と注意

- `release/epub_validation_test.rb`。book.yml の書き換えは page_layout の `BookYmlPatcher` を共通化して再利用する（ブロック終了時に必ず復元）。
- `epubcheck` は Java 依存の外部ツール（`brew install epubcheck`）。**不在時は skip**（doctor の診断対象に加えるかは別途判断とし、本仕様では必須化しない）。

---

## 14. CN: 依存カナリアテスト

### 14.1 目的

@vivliostyle/cli / VFM の上流更新による破壊（VFM 2.x 脚注問題の再来）を、利用者より先に検知する。

### 14.2 テスト項目

| ID | 前提 | 期待 |
|---|---|---|
| CN-01 | 一時ディレクトリに `@vivliostyle/cli@latest` をローカルインストールし、PATH 先頭に向けてマニュアルをビルド | exit 0・FT 検査（Type 3 なし）合格 |
| CN-02 | 同上 | MB の警告ゼロ基準で差分を報告（失敗ではなく警告差分の列挙） |

### 14.3 実装方針と注意

- `rake test:canary` 専用（`rake test:release` にも**含めない**。上流破壊はこちらの欠陥ではないため、リリース判定をブロックさせない）。
- グローバルの npm 環境を**汚さない**: `npm install --prefix <tmpdir>` + PATH 調整で隔離する。
- 将来 GitHub Actions（週次 schedule・failure 許容ジョブ）へ移すことを想定した作りにするが、CI 整備自体は本仕様のスコープ外。現状の workflows/ は labeler のみであることを確認済み（2026-06-12）。

---

## 15. 共通ヘルパーの抽出（テスト支援コードのみ）

`page_layout_test.rb` 内の `BookYmlPatcher` / `VsBuilder` と、新設する PDF 検査を
`test/vivlio_starter/support/build_helper.rb` へ抽出して共用する。

| モジュール | 由来 | 利用先 |
|---|---|---|
| `BookYmlPatcher` | page_layout から移設（ブロック復元保証付き book.yml 書き換え） | page_layout / EP / 将来の判型追加 |
| `VsBuilder` | page_layout から移設（`vs build` 実行 + 成果物探索） | page_layout / MB / ID / PK / CN |
| `PdfInspector` | 新規（フォント走査・テキスト抽出・アウトライン比較） | FT / ID / CN |

> 注意: 本体 `lib/` には一切手を入れない。page_layout_test.rb の変更は「モジュールを require へ置き換える」のみとし、検証ロジック・期待値は変更しない。

---

## 16. テストデータ・環境の安全規約

1. **リポジトリ実体を汚さない**: MB / ID 以外は一時ディレクトリで実行する。MB / ID はビルド後に必ず後始末し、`git status` が汚れないことをテスト自身が確認する。
2. **ネットワーク・brew を起動しない**: テストから `doctor --fix` / `vs new`（内部で doctor --fix）を呼ばない（PK §6.3 参照）。Google Fonts 取得が発生しないよう、標準添付書体のみの構成でビルドする。
3. **グローバル環境を汚さない**: GEM_HOME / npm prefix / PATH の調整はすべてテンポラリ + サブプロセス環境変数で行う。
4. **skip の明示**: 外部ツール不在で実行不能な場合は黙って成功させず、理由付き skip とする。

---

## 17. 段階的導入計画

| ステップ | 内容 | 優先度 | 前提 |
|---|---|---|---|
| T0 | マニュアルビルドの警告棚卸し（§4.3）+ 共通ヘルパー抽出（§15）+ Rakefile タスク整備（§3） | 最高 | — |
| T1 | MB + FT（`rake test:manual` の中核） | 高 | T0 |
| T2 | PK（`rake test:package`） | 高 | T0 |
| T3 | FZ（`rake test` へ追加） | 高 | — |
| T4 | DG + NF（robustness 拡張） | 中 | — |
| T5 | CL + DC-01/02（contract 新設） | 中 | — |
| T6 | ID + EP + DC-03（release 補強） | 低 | T1 |
| T7 | CN（`rake test:canary`）+ CI 方針の別途検討 | 低 | T1 |

> T1〜T2 完了時点で `rake test:release` を成立させ、RC 判定は「このタスクが全件 green」を条件とする。T3 以降は独立に追加できる。

---

## 18. 完了条件（Definition of Done）

- [ ] `rake test` が従来どおり高速（実ビルドなし）のまま、FZ / DG / NF / CL / DC を含んで green
- [ ] `rake test:release` 一発で RC 前総点検が完了する
- [ ] 各テストファイル冒頭に対応する本仕様の ID（MB-01 等）を記載（robustness の既存様式に倣う）
- [ ] 新たに発見された本体側の不具合は修正タスクとして切り出され、本仕様の実装 PR には含まれない
- [ ] CHANGELOG.md に記録
