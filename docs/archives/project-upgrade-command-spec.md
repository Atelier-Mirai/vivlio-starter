# 既存プロジェクトのアップグレード専用コマンド（`vs upgrade`）仕様書

> 作成日: 2026-07-12
> ステータス: **提案（未実装・レビュー待ち）**
> 対象: PLANNED.md:19 [Low]「既存プロジェクトのアップグレード専用コマンド（`vs sync` / `vs upgrade`）」。`vs new <既存> --add-missing` の役割を引き継ぎ、さらに「既存ファイルが新しい雛形で更新された場合の取り込み（diff 提示・選択適用）」まで行う
> 決定事項（本仕様の提案）:
> - コマンド名は **`vs upgrade`**。著者の意図（「gem を新しくしたのでプロジェクトも追従させたい」）に直結する語。`vs sync` は開発側の scaffold 同期（copy_to_scaffold.rb）と語が衝突するため不採用。doctor 統合も不採用（doctor は環境診断、upgrade はプロジェクト資産の更新——PLANNED の判断どおり別コマンド。なお外部**ツール**の更新は `vs doctor --upgrade`＝doctor-tool-upgrade-spec.md が担い、責務が重ならない）
> - **「著者が触ったか」の判定に雛形マニフェスト（`config/scaffold.lock`）を導入**する。展開時点の各ファイルのハッシュを記録し、三者比較（雛形の旧版/新版/プロジェクト現物）を可能にする——これが無いと「雛形が変わった」と「著者が変えた」を区別できず、diff 提示が全ファイル手動確認になってしまう
> - **著者データ領域には絶対に触れない**（§1.3 の除外リスト。ハッシュ判定以前の一律除外）
> - `vs new --add-missing` は **1 リリース間は残して非推奨警告**、その後削除
> 関連: `lib/vivlio_starter/cli/new.rb:16,57,118`（`SCAFFOLD_SOURCE`・`--add-missing` の現行実装・`expand_scaffold`）, `lib/vivlio_starter/cli/samovar/new_command.rb:18`, `lib/vivlio_starter/cli/doctor/config_salvager.rb`（設定ファイル復元の既存機構——壊れた必須 YAML の復旧は引き続き doctor の責務）, `copy_to_scaffold.rb`（開発側同期。scaffold の `{{PLACEHOLDER}}` テンプレート化）

## 0. 背景・問題

現状の `vs new <既存> --add-missing` の弱点（PLANNED より）:

1. 「新規作成コマンド」への相乗りで意味が紛らわしい
2. **不足ファイルの追加しかできない**。gem 更新で雛形の既存ファイルが改良された場合（CSS 改良・テンプレート修正など）、著者プロジェクトには反映する手段がない——現に本プロジェクトでは CSS の改良が高頻度で起きており、RC 以降のユーザーは取り込み手段を持たない

## 1. 著者向け仕様

### 1.1 使い方

```bash
vs upgrade              # 計画提示 → ファイルごとに確認しながら適用
vs upgrade --dry-run    # 計画（何が追加/更新/競合か）の表示のみ
vs upgrade --yes        # 競合以外（追加＋未カスタムの更新）を確認なしで適用
```

実行の流れ:

```
🔍 雛形との差分を確認しています…（gem 1.2.0 の雛形）
📋 更新計画:
   追加   stylesheets/talk.css                （雛形の新規ファイル）
   更新   stylesheets/chapter-common.css      （雛形が改良・あなたは未変更 → 自動適用可）
   競合   stylesheets/custom.css              （雛形もあなたも変更 → diff 確認）
   保持   config/book.yml                     （著者データ領域 → 対象外）
適用しますか？ 追加 1 件・更新 3 件 [y/N]:
   競合 stylesheets/custom.css:
   --- 雛形の変更点（diff 表示） ---
   適用しますか？ [y]適用 / [n]スキップ / [d]diff 全文: n
✅ アップグレード完了: 追加 1・更新 3・スキップ 1（バックアップ: .cache/vs/upgrade-backup/20260712-153000/）
```

- **上書き前に必ずバックアップ**（`.cache/vs/upgrade-backup/<timestamp>/` に元ファイルをツリー構造で退避）。完了メッセージで場所を案内
- git 管理下なら「git で差分確認・巻き戻しできます」を添える（検出は `.git` の存在のみ・git 操作はしない）
- 適用後は `config/scaffold.lock` を新しい雛形のハッシュで更新

### 1.2 ファイルの分類（三者比較）

`config/scaffold.lock`（展開時の雛形ハッシュ）・現在の雛形・プロジェクト現物の 3 点から:

| lock との比較 | 雛形の変化 | 分類 | 動作 |
|---|---|---|---|
| プロジェクトに無い | — | **追加** | コピー（従来の --add-missing 相当） |
| 現物 = lock（未カスタム） | 変化あり | **更新** | 自動適用可（--yes で無確認） |
| 現物 ≠ lock（カスタム済み） | 変化あり | **競合** | diff 提示・個別確認（y/n/d） |
| — | 変化なし | **最新** | 何もしない |
| プロジェクトにあるが雛形に無い | — | **保持** | 何もしない（雛形からの削除は追従しない） |

**lock が無い旧プロジェクト**（本機能導入前に `vs new` したもの）: 現物と現在の雛形を直接比較し、一致 → lock に記録して「最新」扱い、不一致 → 安全側に倒して**すべて競合扱い**（初回だけ確認が多くなるが、以後は lock が効く）。

### 1.3 著者データ領域（一律対象外）

`contents/`, `images/`, `covers/`, `codes/`, `data/`, `config/book.yml`, `config/catalog.yml`, `config/characters.yml`（導入後）。

- これらは初回展開後は完全に著者の所有物。雛形側が変わっても**計画表に「保持」とだけ表示**し、diff も出さない（誤爆で原稿を壊すリスクを構造的に排除）
- `book.yml` に新設定キーが増えた場合の追従は対象外（既定値マージ機構——common.rb:177「book.yml に記述がなくても全キーが存在」——により未記載でも動くため、強制追従は不要。新キーの案内はリリースノートの責務）

## 2. 実装

### 2.1 マニフェスト `config/scaffold.lock`

```yaml
# vs new / vs upgrade が管理する自動生成ファイル。手動編集しない。
scaffold_version: 1.2.0        # 展開元 gem のバージョン
files:
  stylesheets/chapter-common.css: "sha256:ab12…"
  templates/_physics_book.md:    "sha256:cd34…"
```

- `vs new` の `expand_scaffold`（new.rb:118）末尾で生成。**`book.yml` はプレースホルダー書き換え後の値ではなく「雛形原本のハッシュ」を記録**（比較対象は常に雛形原本）——ただし §1.3 により book.yml はそもそも upgrade 対象外なので、記録は将来用のメタデータに留まる
- 拡張子は `.lock`（Gemfile.lock の慣習＝「自動生成・手で触らない」の記号）。YAML 形式・`YAML.safe_load` で読む
- lock 自体は著者の git にコミットされる想定（`.gitignore` に入れない）

### 2.2 コマンド構造

- `lib/vivlio_starter/cli/upgrade.rb`（実装）＋ `lib/vivlio_starter/cli/samovar/upgrade_command.rb`（Samovar）＋ `root_command.rb` の `public_commands` へ登録
- プロジェクト必須コマンド（`ensure_configured!` を通す通常経路。プロジェクト外実行は Guard で 🔴）
- diff 生成は外部 `diff` コマンドに依存せず、Ruby 標準添付を使わない場合でも**行単位の簡易 unified diff を自作**（30 行級）または gem 追加なしで済む範囲に留める（実装時判断。表示は 20 行で打ち切り `[d]` で全文）
- `vs new --add-missing`: 実装は残したまま冒頭に「⚠️ 非推奨: vs upgrade を使ってください」を表示（1 リリース後に削除・new_command.rb のオプション定義ごと撤去）

### 2.3 雛形側の対応（開発側）

- `copy_to_scaffold.rb` は変更不要（雛形の中身を作る側。lock は展開時に作られる）
- ただし雛形の `book.yml` テンプレート化（`{{PLACEHOLDER}}`）と同様、**gem リリースごとに雛形が確定**する前提が lock の「scaffold_version」の意味を支える——リリース手順（vivlio-starter-release skill）に変更なし

## 3. テスト

1. **分類ロジック**（中核）: §1.2 の表 5 分類 × lock あり/なしをフィクスチャ雛形（Dir.mktmpdir に mini scaffold を組む）で網羅
2. **著者データ領域**: `contents/` 等が雛形と差分があっても計画に載らない・触られない
3. **バックアップ**: 更新・競合適用の前に元ファイルが退避される。スキップしたファイルは退避されない
4. **lock の生成と更新**: `vs new` 相当の展開で全ファイル分の lock が生まれる／upgrade 適用後に適用分だけハッシュが進む／未適用（スキップ）分は旧ハッシュのまま（次回また競合として出る）
5. **--dry-run**: ファイルシステムに一切書き込まない（lock 含む）
6. **非推奨警告**: `vs new <既存> --add-missing` で警告文言が出て従来動作は維持

## 4. 手順（実装順序）

1. lock の生成（`vs new` 側）＋分類ロジック＋テスト——ここが価値の 8 割
2. `vs upgrade` コマンド（計画表示 → 適用 → バックアップ → lock 更新）
3. `--dry-run` / `--yes`・競合の diff 表示
4. `vs new --add-missing` の非推奨警告
5. README・`contents/` 該当章（プロジェクト運用）にアップグレード手順を追記 → `ruby copy_to_scaffold.rb`
6. `rake test`

## 5. スコープ外・留意点

- **雛形から削除されたファイルの追従削除**: しない（「保持」）。ゴミ掃除は著者判断（リリースノートで案内）
- **三方向マージ（競合ファイルへの雛形変更の自動織り込み）**: しない。y/n の全体適用のみ。部分適用が欲しい著者は git と diff 表示で自力マージ（バックアップがあるため安全）
- **`book.yml` の新キー追記**: しない（§1.3）。壊れた必須 YAML の復元は引き続き `vs doctor`（ConfigSalvager）の責務で、upgrade とは役割を分ける
- **RC 前リリースへの適用**: 本機能を **1.0 より前（RC）に入れる価値が高い**——RC 利用者のプロジェクトに lock が無い状態を最小化できる（§1.2 の lock なしフォールバックはあるが、初回体験が悪い）。優先度 [Low] の再考を推奨
