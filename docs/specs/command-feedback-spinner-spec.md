# コマンド応答メッセージの統一と CLI スピナー 仕様書

> 作成日: 2026-07-12
> ステータス: **提案（未実装・レビュー待ち）**
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

### 1.2 監査と対象（実装時に確定）

実装の最初のタスクとして Public コマンド全 25 種を監査し、「既定レベルで結果報告が出るか」を表にする。現時点で判明している主な是正対象と文言案:

| コマンド | 現状 | 文言案 |
|---|---|---|
| `vs clean` | 無音（log_action のみ） | `🧹 中間生成物を削除しました（キャッシュ 12 件・カバー 3 件）` |
| `vs clean --all` | 同上 | 同上＋対象カテゴリ列挙 |
| `vs resize` | 要監査 | `🖼 画像を最適化しました（WebP 24 件生成・スキップ 3 件）` |
| `vs rename` / `vs renumber` | 要監査 | `📝 3 ファイルをリネームしました（10→12, …）` |
| `vs index:apply` ほか index 系 | 要監査 | `📚 索引辞書を適用しました（155 語）` |

- 各 clean 系関数（`clean_cover_files` 等）は削除件数を**戻り値で返す**よう変更し、`execute_clean` 末尾で集計して 1 行にまとめる

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

1. `Spinner` ＋テスト → pipeline への装着（効果が最大・変更 1 箇所）
2. ログ出力との干渉処理（§2.1 の消去フック）
3. Public コマンド応答監査 → 是正（`vs clean` から着手）
4. `rake test` ＋ 手動確認（§3-4）
5. ドキュメント: `VS_NO_SPINNER` を README のトラブルシュートに追記 → `ruby copy_to_scaffold.rb`

## 5. スコープ外

- **進捗率（プログレスバー）**: ステップ所要時間は内容依存で予測できないため、パーセント表示はしない（ステップ番号 n/total まで）
- **Windows 端末（cmd.exe）の描画互換**: darwin/Linux の ANSI 前提。tty 判定で守られるため実害はないが、動作保証はしない
- **応答メッセージの多言語化**: 既存ログと同じく日本語のみ
