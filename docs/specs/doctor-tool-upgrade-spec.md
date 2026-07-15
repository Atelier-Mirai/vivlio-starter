# `vs doctor` ツールバージョンアップ機能 仕様書

> 作成日: 2026-07-12
> ステータス: **提案（未実装・レビュー待ち）**
> 対象: PLANNED.md:94 [High]「`vs doctor` にツールのバージョンアップ機能」。診断（現状）＋不足インストール（`--fix`）に加え、**導入済みツールを最新版へ更新する `--upgrade`** を追加する
> 決定事項（本仕様の提案）:
> - オプション名は **`--upgrade`**（`brew upgrade` / `apt upgrade` の語彙に揃える。`--update` は brew では「インデックス更新」の意味で紛らわしい）
> - **`--upgrade` は `--fix` の上位互換**: 不足ツールのインストール＋導入済みツールの更新を一括で行う（別々に 2 回実行させない）
> - **計画提示 → 確認 → 実行 → 再診断** の 4 段構成。`--yes` で確認スキップ（既存 `--fix` の流儀を踏襲）
> - ツール単位で失敗しても続行し、最後に失敗一覧をまとめる（1 ツールの失敗で全体を中断しない）
> - **Ruby 本体と vivlio-starter 本体は自動更新の対象外とし、新版の検出＋更新手順の案内のみ行う**（§1.4。実行中の自分自身の土台の差し替えであり、失敗時に復旧を案内する主体が失われるため）
> - 対応プラットフォームは既存 `--fix` と同じ **macOS + Homebrew のみ**（doctor.rb:37 の制約を踏襲）
> 関連: `lib/vivlio_starter/cli/doctor.rb`（`execute_doctor`・`checks` テーブル doctor.rb:200 付近・`--fix` のインストール処理 doctor.rb:361–478・inkscape 復旧 doctor.rb:815）, `lib/vivlio_starter/cli/samovar/doctor_command.rb:33`（既存オプション）, メモリ `node26-puppeteer-extract-hang`（Node 26 × vivliostyle 10.6 のデッドロック——バージョン組み合わせ起因の実害事例）

## 0. 背景・問題

`vs doctor --fix` は「無い物を入れる」ことしかできない。導入済みツールの更新は著者が `brew upgrade` / `npm install -g …@latest` を個別に叩く必要があり:

- vivliostyle CLI のようにバグ修正が頻繁なツール（例: Node 26 での Chrome 展開デッドロックは 11.x で修正）を古いまま使い続けてしまう
- ツール群が brew formula / brew cask / npm -g / gem の 4 系統に散らばっており、著者は「何をどのコマンドで更新すべきか」を知らない

doctor は既にツール一覧（`checks` テーブル）と診断機構を持つため、更新機能の置き場所として最適。

## 1. 著者向け仕様

### 1.1 使い方

```bash
vs doctor --upgrade          # 計画を提示し、[y/N] 確認後に一括更新
vs doctor --upgrade --yes    # 確認なしで実行
```

実行の流れ:

```
🔍 現在のバージョンを確認しています…
📋 更新計画:
   qpdf              12.1.0  → 12.2.1   (brew)
   vivliostyle CLI   10.6.0  → 11.2.0   (npm)
   mathjax-full      3.2.2   → 最新     (npm)
   node              22.11.0 → 変更なし  (brew・最新)
   kindle-previewer  （cask）  → 更新あり (brew cask)
   vivlio-starter-pdf 1.4.0  → 1.4.2    (gem)
更新を実行しますか？ [y/N]:
⬆️  qpdf を更新中… ✅
…
🩺 更新後の診断を実行します…（通常の vs doctor と同じ）
✅ 更新完了: 5 件成功 / 0 件失敗

📣 お知らせ:
   Ruby 4.0.5 が公開されています（現在 4.0.3）。rbenv 環境の更新手順:
     brew upgrade ruby-build && rbenv install 4.0.5 && rbenv global 4.0.5
     gem install vivlio-starter   # Ruby 切替後は gem の再インストールが必要です
   vivlio-starter 1.1.0 が公開されています（現在 1.0.0）:
     gem update vivlio-starter
```

- **更新後に必ず通常診断を再実行**する（更新でツールが壊れていないかの確認。inkscape 半壊 cask の教訓）
- 失敗したツールは末尾にまとめ、**手動での復旧コマンドを具体的に提示**する（warning-messages の方針: before→after と対処を添える）
- 更新対象がない（全て最新）場合は「✅ すべて最新です」で終了コード 0

### 1.2 更新対象と更新コマンド

既存 `checks` テーブル（doctor.rb:200 付近）＋ループ外の個別診断ツールを対象とする。系統ごとの更新方法:

| 系統 | 対象 | 更新コマンド |
|---|---|---|
| brew formula | node, qpdf, poppler(pdfinfo/pdftoppm), ghostscript(gs), imagemagick, librsvg(rsvg-convert), vips, tesseract, tesseract-lang, mecab, mecab-ipadic | `brew upgrade <formula>`（冒頭に `brew update` を 1 回） |
| brew cask | kindle-previewer, inkscape | `brew upgrade --cask <cask>`。inkscape は失敗時に `brew reinstall --cask --force inkscape` へフォールバック（doctor.rb:815 の既存知見を流用） |
| npm -g | @vivliostyle/cli, textlint 一式（doctor.rb:472 の packages 定義を共用）, mathjax-full | `npm install --loglevel=error -g <pkg>@latest` |
| gem | vivlio-starter-pdf（導入済みの場合のみ） | `gem update vivlio-starter-pdf` |

- **未導入ツールは `--fix` と同じインストール処理へ委譲**（既存コードの呼び出し。§0 決定事項「上位互換」）
- **waifu2x / rouge は更新対象外**（rouge は本 gem の依存として Bundler 管理・waifu2x は導入経路が多様なため）。計画表に「対象外（手動）」と明示
- **Ruby 本体・vivlio-starter 本体（この gem）は更新しない**。新版の検出と更新手順の案内のみ行う（§1.4）

### 1.3 バージョン組み合わせの安全策

メモリ `node26-puppeteer-extract-hang` の実害（Node 26 × vivliostyle 10.6 が Chrome 展開でデッドロック）を踏まえ:

- **node を更新する場合は必ず @vivliostyle/cli も同時に最新へ更新**する（計画表で連動を明示。node のみの選択更新は提供しない）
- 更新後の再診断で vivliostyle の起動確認（既存 `cli_tool_ok?`——壊れたラッパー検出込み）が失敗したら、🔴 で「node と vivliostyle CLI のバージョン組み合わせ」を疑う具体的な案内を出す

### 1.4 Ruby・vivlio-starter 本体の「新版お知らせ」（検出＋案内のみ）

自動更新はせず、`--upgrade` 実行の末尾（§1.1 の 📣 ブロック）で新版の公開を知らせる:

- **Ruby 本体**: 起動中の `RUBY_VERSION` と公開済み最新 patch を比較し、新しい patch があれば案内する。自動更新しない理由: (1) 導入経路が多様（rbenv/rvm/asdf/mise/Homebrew/システム Ruby）で一律の更新コマンドが存在しない、(2) Ruby はバージョンごとに gem 領域が分かれるため、更新は vivlio-starter 一式の再インストールまでがワンセット——実行中の `vs` 自身の土台の差し替えになる、(3) 失敗すると doctor 自身が起動できず復旧案内の主体が失われる
  - 案内は**導入経路を判別した上で**その経路に合った手順を提示する。判別は `which rbenv/rvm/asdf/mise` ＋ `RbConfig::CONFIG['prefix']` のパス（`~/.rbenv/versions/` 配下か等）で行い、rbenv なら「`brew upgrade ruby-build` → `rbenv install X.Y.Z` → `rbenv global X.Y.Z` → gem 再インストール」、判別不能なら ruby-lang.org への誘導に留める
  - **gem の再インストールが必要な旨を必ず添える**（切替後に `vs` が見つからなくなる事故の予防が案内の主目的）
  - 同一 patch 系列の更新のみ対象（4.0.3 → 4.0.5 は案内、4.0 → 4.1 のようなマイナー/メジャーは対象外——gemspec の `required_ruby_version` との整合確認を伴うため、リリースノートの責務とする）
- **vivlio-starter 本体**: RubyGems 上の最新版と `VivlioStarter::VERSION` を比較し、新しければ `gem update vivlio-starter` を案内する
- 通常の `vs doctor`（`--upgrade` なし）ではこの問い合わせを**行わない**（診断はオフラインで完結するという既存の性格を保つ）

## 2. 実装

### 2.1 構造

`lib/vivlio_starter/cli/doctor/tool_upgrader.rb`（新規・`config_salvager.rb` の並び）に切り出す。doctor.rb は 1289 行あり、これ以上の肥大を避ける。

```ruby
module VivlioStarter
  module CLI
    module DoctorCommands
      # vs doctor --upgrade の実装。
      # 更新対象の列挙・現在/最新バージョンの取得・計画提示・実行・結果集計を担う。
      module ToolUpgrader
        module_function

        # ツール定義: [表示名, 系統(:brew/:cask/:npm/:gem), パッケージ名, バージョン取得コマンド]
        TOOLS = [ ... ].freeze

        def run!(options)  # => 終了コード
      end
    end
  end
end
```

- `doctor_command.rb` に `option '--upgrade', '導入済みツールを最新版へ更新（不足分はインストール）', default: false, key: :upgrade` を追加。`execute_doctor` 冒頭で `--upgrade` 指定を検出したら `ToolUpgrader.run!` → 続けて通常診断（既存フロー）を実行
- `--fix` と `--upgrade` の同時指定は `--upgrade` に一本化（🟡 で通知）

### 2.2 バージョン取得

- **現在版**: ツールごとの `--version` 出力を正規表現でパース（`qpdf --version` / `npm ls -g --depth=0 --json` / `gem list vivlio-starter-pdf` 等）。パース失敗時は「不明」とし、更新対象には含める（更新して害はない）
- **最新版**: `brew outdated --json` / `brew outdated --cask --json` / `npm outdated -g --json` を各 1 回だけ実行してまとめて取得（ツールごとの問い合わせはしない——遅い）。`npm outdated` は差分がないと exit 0・あると exit 1 で JSON を返す点に注意
- **新版お知らせ（§1.4）の取得元**:
  - Ruby: ruby-lang.org 公式のリリースデータ `https://raw.githubusercontent.com/ruby/www.ruby-lang.org/master/_data/releases.yml`（YAML）から起動中 patch 系列の最新を取る。`rbenv install --list` は手元の ruby-build 定義依存で古い版しか返さないため使わない（実測: ruby-build 20260503 は 4.0.3 まで——古い定義では新版を検出できない）
  - vivlio-starter: RubyGems API `https://rubygems.org/api/v1/versions/vivlio-starter/latest.json`
  - いずれも**タイムアウト 2 秒・失敗時は無言でスキップ**（お知らせは付加情報であり、オフラインでも `--upgrade` 本体の brew/npm 更新を妨げない。ただし §2.2 末尾のオフライン検知で中断した場合はそもそも到達しない）
- ネットワーク不通時: `brew update` / `npm outdated` の失敗を検知したら「最新版の確認ができません（オフライン？）」と 🔴 を出して中断（中途半端な更新をしない）

### 2.3 実行と集計

- 系統ごとに直列実行（brew は同時実行不可）。各ツールの成否を `[名前, :ok/:failed, before, after]` で収集
- 出力は `Common.log_always`（doctor は診断コマンドのためログレベルに関わらず表示、既存流儀）
- すべて終わったら §1.1 の再診断（既存 `execute_doctor` の診断部をそのまま流す）
- 終了コード: 全成功＋再診断 OK → 0、1 件でも失敗または再診断 NG → 1

## 3. テスト

外部コマンド実行はテストで実際には走らせない。`system` / `capture_command` 相当を注入可能にする（ruby-coding-rules の DI 流儀）:

1. **計画生成**: `brew outdated` / `npm outdated` のスタブ JSON から更新計画（対象・現在版・最新版・系統）が正しく組まれる。全最新なら「更新なし」
2. **連動規則**: node が対象になったとき @vivliostyle/cli が必ず計画に入る（§1.3）
3. **失敗継続**: 2 番目のツールが失敗しても 3 番目以降が実行され、集計に failed が載る・終了コード 1
4. **確認プロンプト**: `--yes` なしで n 応答 → 何も実行せず 0、`--yes` で即実行
5. **オフライン検知**: `brew update` 失敗 → 中断・終了コード 1
6. **新版お知らせ**: releases.yml / RubyGems API のスタブ応答で (a) 新 patch あり → 導入経路（rbenv スタブ）に応じた手順が案内に含まれる・gem 再インストールの注意が含まれる、(b) 最新なら何も出ない、(c) マイナー/メジャー差は案内しない、(d) 取得失敗（タイムアウト/不通）でも 📣 ブロックが黙ってスキップされ終了コードに影響しない
7. **手動確認（自動テスト外）**: 実機で `vs doctor --upgrade` を通し、再診断まで完走すること

## 4. 手順（実装順序）

1. `tool_upgrader.rb` の骨格＋ TOOLS 定義（既存 `checks` テーブル・`--fix` のパッケージ対応を移す。**doctor.rb 側の定義と二重管理にならないよう、brew/npm パッケージ名は TOOLS に一元化して `--fix` からも参照**するリファクタを含める）
2. バージョン取得（§2.2）→ 計画提示 → 実行・集計（§2.3）
3. `doctor_command.rb` のオプションとヘルプ文言
4. テスト（§3）→ `rake test`
5. ドキュメント: README の doctor 節・`contents/` の環境構築章に追記 → `ruby copy_to_scaffold.rb`

## 5. スコープ外

- **Linux / Windows 対応**: 既存 `--fix` と同じく対象外（診断のみ可）
- **バージョン固定（ピン止め）・ロールバック**: brew/npm に委ねる。doctor は「最新にする」以外の状態管理をしない
- **Ruby 本体・vivlio-starter 本体の自動更新**: 検出＋案内のみ（§1.4 に理由を記載）。rbenv 検出時のみ確認付きで半自動更新する中間案（rbenv は旧版が残る非破壊方式のため技術的には成立する）も検討したが、v1 では複雑さに見合わないため見送り——要望が続けば再検討
- **選択的更新 UI（ツールを個別に選ぶ）**: v1 は全対象一括のみ。要望があれば `--only <tool>` を後日検討
