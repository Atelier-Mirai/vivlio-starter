# 手動フロー（vs pdf / vs entries / ルート vivliostyle.config.js）撤去仕様

作成日: 2026-07-05 / 作成者: Claude (Fable 5) /
位置づけ: [vivlioverso-p4-investigation.md](vivlioverso-p4-investigation.md) §8 スコープ外項目
「`vs pdf` / `vs entries` 等の著者向け単体コマンドの workspace 化（ルート運用のまま）」の決着。

---

## 1. 背景（調査で確定した事実・2026-07-05）

「著者向け手動フロー（`vs entries` → `vs pdf`）」は P4 完了時点で実体を失っている:

1. **`vs entries` はルーティング不在** — `root_command.rb` の public/internal どちらの
   コマンドマップにも `entries` が無く、CLI から呼べない（ヘッダコメントの記載は陳腐化）。
2. **`vs pdf`（config なし経路）は動作不能** — `ensure_entries_file!` がルートの `*.html` を
   glob して entries.js を自動生成するが、P4 以降ルートに中間 HTML は存在しない
   （`--no-clean` でも workspace 内）。0 件の entries.js が生成され空振りする。
3. **パイプラインは手動経路を通らない** — `execute_pdf` / `execute_print_pdf` の全呼び出しが
   `config_path:`（workspace の用途別生成 config）付き。config なし経路の利用者は
   Samovar `vs pdf` のみだった。
4. **ルート `vivliostyle.config.js` も単独で使えない** — `import './entries.js'` の実体が
   scaffold にも生成物にも無い。P3-4 で全文生成化した際の存在意義（手動フロー用）が
   前提ごと消えている。

workspace 化（`vs pdf` を workspace の sections config へ向ける案）も検討したが、
単章ビルド `vs build 11` が既に高速な部分再生成を提供しており、開発者デバッグは
`npx vivliostyle build -c .cache/vs/build/pdf/vivliostyle.config.sections.js` の直叩きで
足りるため、**撤去（削除）を採る**（ユーザー決定・2026-07-05）。

## 2. 撤去対象

| 対象 | 措置 |
|---|---|
| Samovar `vs pdf`（`PdfCommand`） | クラスとルーティングを削除（`pdf:compress` 等の Public コマンドは維持） |
| `PdfCommandRunner` の config なし経路 | `config_path:` / `output_path:` を必須化。`ensure_entries_file!`・`SingleDocDecider`（`VIVLIO_SINGLE_DOC`）・`target_output` リネーム機構（`vs pdf [output]` 専用だった）を削除 |
| `EntriesCommands.execute_entries` 系 | 削除。`build_entry` / `extract_html_title` は `VivliostyleConfigWriter` / `EpubBuilder` が利用するため残置 |
| `VivliostyleConfigWriter.write_root_config!` 系 | `root_config_content` / `backup_unmanaged_root_config!` / `ROOT_CONFIG_MARKER` ごと削除。メタデータリゾルバ（`resolve_title` 等）は用途別 config / EPUB config が共用するため残置 |
| `BookSettingsCss` からの呼び出し | `write_root_config!` 呼び出しを削除 |
| ルート / scaffold の `vivliostyle.config.js` | ファイル削除（scaffold は copy_to_scaffold.rb の同期対象外のため直接削除） |
| `package.json` の `build:pdf` 系 script | 削除（ルート config 前提のため） |
| `.gitignore` の `/entries.js` | 削除 |
| book.yml スキーマ `vivliostyle.entries_file` / `config_file` | 既定値・README 記載を削除（コード上の消費者なし） |
| `clean.rb` の `entries.js` | `ACTIVE_ROOT_PATTERNS` → `LEGACY_ROOT_PATTERNS` へ移動（旧バージョン残骸掃除・削除挙動は不変） |

## 3. 残すもの（誤削除防止）

- `PdfCommands` モジュール自体（パイプライン＋ `pdf:compress` / `pdf:pages` / `pdf:rasterize` / `pdf:read`）。
- `Common::VIVLIOSTYLE_CONFIG_FILE` 定数 — `doctor` が旧プロジェクト検出マーカーとして参照。
- `EntriesCommands.build_entry` / `extract_html_title` — workspace entries 生成の実装基盤。
- パイプラインのステップラベル（`generate entries.js` 等）— 内部名。改名はスコープ外。

## 4. 付随修正

- **エスケープバグの統合修正**: workspace 用 `config_content` の
  `gsub("'", "\\'")` は置換文字列中の `\'`（後方一致バックリファレンス）誤解釈バグを持つ。
  ルート config 側で修正済みだったブロック形 `gsub(/[\\']/) { "\\#{it}" }` へ一本化する。
- 原稿修正: `12-quickstart.md` / `13-new.md`（プロジェクトツリーから `entries.js` /
  `vivliostyle.config.js` を削除）、`61-developer.md`（内部コマンド表・Step 6・単章ビルド・
  clean 説明・PDF 生成節の記述を workspace 実態へ更新）。
- 既存プロジェクトの移行: ルートに残る `vivliostyle.config.js`（・`.bak`）は無害な残骸。
  自動削除はしない（設定ファイルの自動削除は危険）。CHANGELOG で手動削除可と案内。

## 5. 検証

- `rake test` 全緑・`bundle exec rubocop` クリーン。
- 将来の `vs build myawesome.md --pdf`（V2.0 直接ビルド構想）はルート config に依存しない
  （workspace 生成 config で実現する）ため、本撤去は布石を損なわない。
