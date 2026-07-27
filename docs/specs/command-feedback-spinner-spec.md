# コマンド応答メッセージの統一と CLI スピナー 仕様書

> 作成日: 2026-07-12
> 改訂: 2026-07-27（実装完了・§1.2 に監査結果を反映）
> ステータス: **実装済み（2026-07-27）**。残: 実端末での目視確認（§3-4）
> 対象: PLANNED.md:103「コマンド実行時の応答メッセージ」＋ PLANNED.md:104「CLI スピナー（ビルド進捗表示）」。どちらも「コマンドが黙って見える」問題の解消なので 1 本に統合
> 決定事項（本仕様の提案）:
> - **応答規約**: 利用者向け（Public）コマンドは、成功時に必ず 1 行の結果報告（何を・何件）を**既定ログレベル（warn）でも表示**して終わる。`Common.log_result` を規約の器とする
> - **スピナーは外部ライブラリを使わず簡易自作**（`ora`/`cli-spinners` は Node の資産で Ruby CLI には持ち込めない。Ruby 側 gem を足すほどの規模でもない——スレッド＋`\r` 書き換えで 40 行級）
> - スピナーの表示条件は「**TTY かつ 既定ログレベル（warn 以下）**」。`--log`（info/debug）時・リダイレクト時・CI では出さない（逐次ログ・パイプ出力と干渉させない）
> 関連: `lib/vivlio_starter/cli/common.rb`（`log_result` / `current_log_level` / ログ規約）, `lib/vivlio_starter/cli/build/pipeline.rb`（`execute(step)`——スピナーの装着点・step.label がそのまま進捗表示名になる）, `lib/vivlio_starter/cli/clean.rb:125`（応答が info レベルの `log_action` のみで既定では無音の代表例）, `lib/vivlio_starter/cli/samovar/build_command.rb:373`（`print_created_files_message`——応答規約の既存の良い例）

## 0. 背景・問題

1. **応答の不統一**: `vs build` は「○○.pdf を作成しました (38.2s)」を出すが、`vs clean` は既定レベルでは何も表示せず終わる（`log_action` は info レベルのため）。実行して無音だと「効いたのか分からない」
2. **ビルドが止まって見える**: `vs build` は数十秒〜数分かかるが、既定レベルではステップ間の出力がなく、フリーズと区別が付かない

## 1. 応答メッセージ規約

### 1.1 規約

- **Public コマンド（root_command.rb:44 の一覧）は、成功時に `Common.log_result` で 1 行の結果報告を出して終了する**。書式: `<やったこと>（<対象・件数などの実績>）`
- 実績値（件数・ファイル名）を必ず含める。「完了しました」だけの空報告は不可（warning-messages の「actionable」方針の成功版）
- 何もすることがなかった場合も無音にせず、その旨を報告する（例: `削除対象はありませんでした`）
- 逐次の経過報告は従来どおり `log_action`（info）のまま——**変えるのは「最後の 1 行」だけ**

### 1.2 監査結果（2026-07-27 実施）

Public コマンド全 26 種を監査した。判断は「**副作用が目的のコマンドか、出力そのものが目的のコマンドか**」で分かれる。

**是正不要（出力そのものが結果になっている）**

`metrics`（解析結果を表示）／`lint`（🟡 と 💡 で指摘を表示）／`doctor`（診断結果を列挙）／`index`（サブコマンド一覧）／`help`／`open`（PDF が開く）。実行して確認済み。これらに 1 行足すのは冗長なので触らない。

**既に結果報告がある**

`build`（`📚 ….pdf を作成しました (38.2s)`）／`preflight`（3 段階の最終行）／`cover`／`upgrade`。

**是正した（副作用が目的なのに既定では無音だった）**

| コマンド | 是正後の文言 |
|---|---|
| `vs clean` | `✅ 削除しました（キャッシュ 2 件・生成物 12 件）` ／ 対象ゼロなら `✅ 削除対象はありませんでした` |
| `vs rename`（単章） | `✅ 11-workflow を 12-workflow に変更しました` |
| `vs rename`（一括連番） | `✅ 3 章の連番を付け直しました` ／ 変更なしなら `✅ すでに正しい連番です（変更はありません）` |
| `vs resize` | `✅ 画像を最適化しました（WebP 24 件生成・最新のため据え置き 3 件）` ／ 全件が最新なら `✅ 画像はすべて最新でした（1 件を確認）` ／ 対象なしも報告 |
| `vs index:apply` | `✅ 辞書を更新しました（索引 2 件・用語集 0 件・リジェクト 0 件）` |

**残り全コマンドも `log_result` へ揃えた（2026-07-28 追加）**

当初は「既定で何らかの出力があり無音ではない」ものを見送ったが、**応答が返ること自体が利用者の安心感・信頼感につながる**という方針で全 24 コマンドに広げた。

| コマンド | 是正後の文言 |
|---|---|
| `vs create` | `✅ 3 章を作成しました（12-intro, 13-basic, 14-apply）` |
| `vs delete` | `✅ 削除しました（文書 1 件・画像ディレクトリ 1 件）` ／ `✅ 削除したものはありません` |
| `vs import` | `✅ インポートしました（contents/ に 12 章）` |
| `vs open` | `✅ vivlio_starter_v1.0.0.pdf を開きました` |
| `vs pdf:compress` | `✅ PDF を圧縮しました: output_compressed.pdf（28.8 MB）` |
| `vs pdf:pages` | `✅ 12 ページを画像化しました（book_images/）` |
| `vs pdf:rasterize` | `✅ 24 ページをラスタライズしました: out.pdf（28.8 MB）` |
| `vs pdf:read` | `✅ Markdown に変換しました: out.md` |
| `vs new` | `✅ プロジェクト "mybook" を作成しました` |
| `vs index:export` | `✅ 索引ライブラリを書き出しました: …（用語集 16 件 / reject 3 件 / 読み 155 件）` |
| `vs index:import` | `✅ 索引ライブラリを取り込みました: 用語集 +2（スキップ 0）…` |
| `vs doctor` | `✅ すべての必要ツールが見つかりました` ／ `⚠️ 不足しているツール: …（3 件）` |
| `vs metrics` | `✅ 27 章を解析しました（総 262417 文字）` |

**`vs index:auto` の総括行は `log_summary`（🔍）のまま**とした。候補抽出の結果は「検証結果の集計」であり、`detail:` で次の操作（`vs index:apply`）を案内する構造が機能しているため。既定ログレベルで常時表示されるので「無音」の問題はない。

ただし同コマンドが出す辞書更新の報告は **`log_always("📝 …")` と絵文字を手書き**しており（`unified_index_manager.rb`）、`log_*` の体系外だった。`log_result(status: :success)` へ移して ✅ に揃えた。

```
✅ 辞書を更新しました: 自動承認 27 語（…）      ← log_result（絵文字の手書きを撤去）
🔍 候補抽出完了: 自動承認 27 件（…）            ← log_summary（維持）
        _index_glossary_review.md を編集後、vs index:apply を実行してください
```

**あわせて点検した「絵文字の手書き」**: `doctor` と `tool_upgrader` にも `log_always('✅ … : OK')` の形が多数あるが、これらは**診断項目の一覧**であってコマンドの最終結果ではないため対象外とした（最終結果は `log_result` へ是正済み）。`🔎 環境診断を開始します…` のような開始告知も同様。

**ビルド経路との共用に注意した箇所**: `pdf:compress` はビルドの最終段からも呼ばれるため、既存の `pipeline_mode?` 判定で分岐し、**ビルド中は従来どおり info レベル**、`vs pdf:compress` として直接叩かれたときだけ `log_result` を出す。

**実装メモ**

- 各 clean 系関数（`clean_cover_files` 等）は削除件数を**戻り値で返す**よう変更し、`execute_clean` が `CleanSummary`（`Data.define`）で内訳を返す。`resize` も同様に `ResizeSummary` を返す。
- **表示は必ず Samovar 層で行う。** ドメイン層（`clean.rb` / `resize.rb`）は件数を返すだけにする。

> ⚠️ **この分離は必須。** `execute_clean` は `vs build` の Step 0、`execute_resize_with_preset` は Step 1 が**対象ディレクトリごとに**呼ぶ。ドメイン層で `log_result` を出すと、`vs build` の最中に
> ```
> ✅ 画像を最適化しました（WebP 0 件生成・スキップ 1 件）
> ✅ 対象画像が見つかりませんでした: stylesheets/images
> ✅ 対象画像が見つかりませんでした: data
> ```
> のように無関係な報告が何行も混ざる（実装中に実際に踏んだ）。**「そのコマンドを実行した人に向けた最終報告」はコマンドクラスの責務**であり、ドメイン層は誰から呼ばれるか分からないという原則で判断する。
>
> なお `rename` と `index:apply` の `log_result` はドメイン層にあるが、これらは `vs rename` / `vs index:apply` 経路からしか呼ばれない（ビルドは `build_index!` という別メソッドを通る）ため問題ない。**新たに報告を足すときは、そのメソッドがビルドから呼ばれないかを必ず確認すること。**

- 実績値の言い方は状況で変える。`WebP 0 件生成` では何が起きたか読み取れないため、全件が最新なら「画像はすべて最新でした」、対象が無ければ「最適化の対象画像はありませんでした」と言い分ける。

### 1.3 確認プロンプトの統一（2026-07-27 追加）

応答メッセージを揃える過程で、**確認プロンプトが 12 箇所すべて独自実装**であることが判明した。絵文字（`❓` / `🟡` / なし）・括弧（`(y/N)` / `[y/N]` / `[Y/n]`）・出力方法（`print` / `$stdout.print` / 独自 `prompt`）がばらばらで、同じ「消していいですか」でもコマンドごとに見た目が違っていた。

`Common.confirm?(message, default: false, input: $stdin)` を新設して全箇所を集約した。

- **表記**: `❓ <質問文> [y/N]:`（既定 Yes のときは `[Y/n]`）。`❓` は既存のログ絵文字（🔵✅🟡🔴🔧🧪🔍📚⚠️❌）と衝突しない
- **応答**: `y` / `yes` を受理（大文字・前後の空白は無視）。Enter だけなら `default`、解釈できない入力は安全側（`false`）へ倒す
- **`input:` で読み取り先を注入できる**——`vs upgrade` と `tool_upgrader` は `deps.stdin` を DI しているため
- スピナーが回っていれば行を消してから出す（`log_*` と同じ扱い）

**挙動が変わった箇所**: `vs new` の最終確認は従来「`n` のときだけ中断」＝ `abc` のような入力でも続行していたが、統一後は**解釈できない入力を中断として扱う**。取り返しのつかない操作の前では安全側が妥当と判断した。

## 2. CLI スピナー

### 2.1 表示仕様

```
⠹ ビルド中: build overall pdf … (3/14)
```

- フレーム: `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`（80ms 間隔・cli-spinners の dots 相当）
- 表示内容: 現在のステップラベル（pipeline の `step.label` をそのまま使用——ログ・計時と語彙が一致する既存設計に乗る）＋ステップ番号/総数
- ステップ完了時は行を消去（`\r\e[K`）して次へ。**完了ログを行として残さない**（既定レベルの静けさを保つ。所要時間の内訳は従来どおり `--log` で見る）
- 🔴🟡 など他のログ出力が割り込む場合は、**出力前にスピナー行を消去してから**ログを出し、出力後に再描画する（`Common` のログ出力関数に消去フックを 1 箇所差し込む）

### 2.2 表示条件（すべて満たすときのみ）

1. `$stdout.tty?` が真（リダイレクト・パイプ・CI では出さない）
2. `Common.current_log_level` が既定（warn）以下（`--log` 指定時は逐次ログが流れるため不要かつ干渉する）
3. `VS_DEBUG` 未設定
4. 環境変数 `VS_NO_SPINNER=1` で無効化可能（エスケープハッチ）

条件を満たさないときは完全に無音（現状維持）。

### 2.3 実装

`lib/vivlio_starter/cli/spinner.rb`（新規）:

```ruby
module VivlioStarter
  module CLI
    # TTY 向けの簡易スピナー。表示条件を満たさないときは何もしない。
    class Spinner
      FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      def self.while(label, &) = new(label).run(&)

      def run
        return yield unless enabled?
        start_thread   # 80ms ごとに \r で再描画
        yield
      ensure
        stop_and_clear
      end
    end
  end
end
```

- 装着点は `UnifiedBuildPipeline#execute`（pipeline.rb の Timer 計測部）1 箇所。`Spinner.while("ビルド中: #{step.label} … (#{i}/#{total})") { step.handler.call }` で全モード（full/single/preflight）に効く
- Vivliostyle 子プロセスの出力: 既定レベルでは子プロセス出力は抑制されている前提（現状の `vs build` が既定で静かなことから成立）。**info 以上では子プロセス出力が流れるため §2.2-2 の条件で自動的にスピナーが消える**——干渉しない
- 例外時: `ensure` で必ず行を消去（スピナー残骸で 🔴 メッセージを汚さない）
- `vs epub` / `vs kindle` 等、pipeline を通らない長時間コマンドがあれば同じ `Spinner.while` を個別装着（監査時に洗い出す）

## 3. テスト

1. **spinner_test**（新規）: 非 TTY で `yield` が素通しされ何も出力されない／TTY スタブで開始・停止後に行が消去される（`\e[K` を含む）／例外時も消去される／`VS_NO_SPINNER=1` で無効
2. **clean 系**: `execute_clean` が件数を集計した `log_result` を 1 回出す。削除対象ゼロでも 1 行出る
3. **応答監査の回帰防止**: 主要 Public コマンドのテストに「成功時に log_result が呼ばれる」アサーションを追加（監査で是正したコマンド分）
4. **手動確認**: 実プロジェクトで `vs build`（TTY）でスピナーが回り、`vs build | cat`・`vs build --log` では出ないこと

## 4. 手順（実装順序）

| # | 内容 | 状態 |
|---|---|---|
| 1 | `Spinner` ＋テスト → pipeline への装着 | ✅ `spinner.rb` 新規・`pipeline.rb#execute` に 1 箇所装着（`spinner_label` でステップ番号/総数を表示） |
| 2 | ログ出力との干渉処理（§2.1 の消去フック） | ✅ `Common#emit` を新設し、全 log_* をそこへ集約。出力前に `Spinner.clear_active_line` を呼ぶ |
| 3 | Public コマンド応答監査 → 是正 | ✅ §1.2 のとおり（26 種監査・5 コマンド是正） |
| 4 | `rake test` | ✅ 1986 runs, 0 failures／RuboCop 396 files, no offenses。**実端末での目視確認は未実施**（§3-4） |
| 5 | ドキュメント | ✅ README に「ビルド中の進捗表示（スピナー）」節を追加 → `ruby copy_to_scaffold.rb` 実行済み |

### 実装時の補足

- **`Common#emit` の新設**: 仕様の「ログ出力関数に消去フックを 1 箇所差し込む」を実現するため、全 log_* が経由する出口を作った。副産物として、今後ログ出力に共通処理を足す場所が 1 箇所に定まった。
- **スピナーの表示条件判定は `Spinner` 側に閉じた**（`enabled?`）。装着側（pipeline）は条件を知らずに `Spinner.while` を呼ぶだけでよい。
- **出力先を DI 可能にした**（`output:` 引数）。テストは `tty?` だけを真に返す `FakeTty`（StringIO 派生）を渡すため、グローバル状態を汚さず並列実行にも耐える。

## 5. スコープ外

- **進捗率（プログレスバー）**: ステップ所要時間は内容依存で予測できないため、パーセント表示はしない（ステップ番号 n/total まで）
- **Windows 端末（cmd.exe）の描画互換**: darwin/Linux の ANSI 前提。tty 判定で守られるため実害はないが、動作保証はしない
- **応答メッセージの多言語化**: 既存ログと同じく日本語のみ
