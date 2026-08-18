# CLI の警告が著者へ届かない問題

## 1. 何が起きているか

`bin/vs` は起動時に **`RUBYOPT=-W0` を付けて自身を再実行する**。`-W0` は Ruby の
警告レベルを 0 にするが、これは処理系の警告（`instance variable not initialized`
など）だけでなく **`Kernel#warn` の出力も丸ごと捨てる**。

```console
$ ruby -e 'warn "警告テスト"'
警告テスト
$ ruby -W0 -e 'warn "警告テスト"'          # 何も出ない
```

そのため `lib/` の `warn` で書いたメッセージは、**`vs` コマンド経由では一度も
著者へ届いていない**。2026-08-18 に `vs-lint-disable` の未クローズ警告を追って
判明した。

## 2. 影響範囲

`lib/vivlio_starter/` の `Kernel#warn` は 6 箇所。うち 1 箇所は発見時に修正済み。

| 箇所 | 内容 | 重大度 |
| :--- | :--- | :--- |
| `startup.rb` `handle_unexpected_error` | **`🔴 例外クラス: メッセージ`** | **最重** |
| `startup.rb` （同・別経路） | 同上 | **最重** |
| `startup.rb` `print_usage_for_invalid_input` | Samovar の解析エラー本文 | **最重** |
| `startup.rb` `handle_interrupt` | `🟡 処理が中断されました（Ctrl+C）` | 中 |
| `startup.rb` `handle_signal` | `🟡 処理が中断されました（SIGTERM 等）` | 中 |
| `frontmatter_generator.rb` | フロントマターの閉じ `---` 忘れ | 中 |
| `techbook/variable_font_injector.rb` | `Common` 未ロード時のフォールバック | 低 |
| ~~`lint/tokenizer.rb`~~ | ~~`vs-lint-disable` の未クローズ~~ | 修正済み |

（末尾 2 行は実装時に見つけた追加分。当初の調査は `startup.rb` 4・`frontmatter_generator.rb`
1・`tokenizer.rb` 1 の計 6 箇所としていた——§9.1 に経緯。）

**最重の 2 件は「予期しない例外が起きても `vs` が何も表示せず終了コード 1 で
終わる」ことを意味する。** 著者から見れば、原因の手がかりが一切ないまま失敗する。
`VS_DEBUG=1` を付けると再実行がスキップされて警告が復活するため、**デバッグ時
だけ症状が消える**という、最もたちの悪い形になっている。

中の 3 件は「知らせたいのに黙っている」類で、`vs-lint-disable` の閉じ忘れは
**ファイル末尾まで校正が無効になる**ため、黙って見逃すのは実害がある。

## 3. なぜ気づけなかったか（テストの死角）

- **ユニットテストはライブラリを直接叩く。** `capture_io { Tokenizer.tokenize(...) }`
  は `-W0` を経由しないので警告が見える。既存テスト（`tokenizer_test.rb` の
  未クローズ警告テスト）は**通っていた**。
- **契約テスト（`cli_contract_test.rb`）も同一プロセスで `CLI.start` を呼ぶ。**
  `bin/vs` を起動しないため、再実行の影響を受けない。
- つまり**現在のテスト構成では原理的に検出できない**。`bin/vs` を子プロセスとして
  起動し、その stderr を見るテストが要る（§6）。

## 4. `-W0` はいま何も抑制していない

導入は初期（`bin/vs` の作成時点まで遡る）で、コメントには "suppress warnings from
process start (incl. Bundler init)" とある。当時は Bundler や gem の初期化で警告が
出ていたと見られる。

**2026-08-18 の実測では、`-W0` を外しても Ruby の警告は 1 行も出ない。**

| コマンド | `-W0` なしでの Ruby 警告 |
| :--- | :--- |
| `vs lint 31` | 0 行 |
| `vs doctor` | 0 行 |
| `vs preflight` | 0 行 |

`strscan` の二重初期化警告は `Gemfile` の一本化で根治済み（`strscan-kramdown-flaky`
の記録）で、それが最後の常連だった可能性が高い。

**ただし「いま 0 行だから外してよい」とは即断しない。** gem を更新すれば復活しうるし、
Ruby 4.0 系では新しい警告が入る。`-W0` の役目（**処理系の警告を著者に見せない**）
自体は妥当なので、残す前提で設計する。

## 5. 対処方針

### 5.1 採る案: 出力手段を用途で分ける

**`Kernel#warn` は「処理系の警告と同じ扱いでよいもの」だけに使い、著者へ必ず
届けたいメッセージには使わない。** `-W0` は残す。

| 文脈 | 使うもの | 理由 |
| :--- | :--- | :--- |
| 例外・シグナルのハンドラ（`startup.rb`） | `$stderr.puts` | **最後の砦**。`Common` が壊れている状況でも動く必要があり、ログレベルにも左右されてはいけない |
| 通常の警告（`tokenizer.rb`・`frontmatter_generator.rb`） | `Common.log_warn` | 🟡 の体裁とログレベル制御が他の警告と揃う。著者が `--log=error` まで下げたなら黙るのが筋 |

`tokenizer.rb` は発見時に `$stderr.puts` で応急修正したが、**本仕様では
`Common.log_warn` へ寄せる**（`SpellChecker` は既に `Common` を使っており、依存は
増えない）。

### 5.2 採らない案

- **`-W0` をやめる**: いま警告が 0 行でも、gem 更新や Ruby のバージョン差で復活する。
  復活したとき著者に無関係な警告が出るのは、元の問題へ戻るだけである。
- **`Warning.warn` をオーバーライドして自前のメッセージだけ通す**: 「`warn` を
  呼んでよい／いけない」の区別がコードから読み取れなくなる。処理系の警告と自前の
  メッセージを文字列で見分けることになり、脆い。
- **`Common.log_*` に一本化する（`startup.rb` も含めて）**: 例外ハンドラが
  `Common` に依存すると、`Common` 側の障害で**エラー表示そのものが失敗**する。
  最後の砦は依存を持たないほうがよい。

### 5.3 RuboCop との関係

`Style/StderrPuts` は `$stderr.puts` を `warn` へ直すよう促す cop で、その理由は
まさに **"to allow such output to be disabled"**（無効化できるようにするため）で
ある。本プロジェクトの要求と正面から衝突するが、`.rubocop.yml` が
`DisabledByDefault: true` を採っているため**この cop は無効**であり、障害にならない。
将来 cop を個別に有効化する場合も、これは有効化しないこと。

## 6. 検証

1. **`bin/vs` を子プロセスとして起動し、stderr を検査するテストを足す。**
   同一プロセスで `CLI.start` を呼ぶ既存の契約テストでは検出できない（§3）。
   - 例外表示: 意図的に例外を起こす経路を用意し、`🔴` が stderr に出ることを見る。
   - 警告: `vs-lint-disable` を閉じない原稿を作り、`vs lint` の stderr に
     警告が出ることを見る。
2. `VS_DEBUG=1` の有無で**出力が変わらない**こと。いまは付けると警告が復活する。
3. 処理系の警告が引き続き抑制されていること（`-W0` を残す以上、`vs` の通常実行で
   Ruby 由来の警告が出ないこと）。

## 7. 再発防止

- **`lib/` に `Kernel#warn` を残さない。** §5.1 の 2 手段のどちらかを使う。
  検出は grep で足りる（`^\s*warn ['"(]`）。CI で見るなら 1 行のスクリプトで済む。
- **「CLI 経由で動くか」を確かめる習慣。** 今回の症状は、ライブラリのテストが
  全部通り、`VS_DEBUG=1` を付けた手動確認でも再現しないという形で隠れていた。
  出力に関わる変更は、**`bin/vs` を素の状態で叩いて目で見る**のが最終確認になる。

## 8. 適用範囲外

`bin/vivlio-starter`（`bin/vs` の別名）も同じ再実行を行うため同様に影響を受けるが、
修正は `lib/` 側で完結するので個別の対応は要らない。

## 9. 実装記録（2026-08-18 実装）

### 9.1 調査は 2 箇所取りこぼしていた

§2 の表は当初 6 箇所としていたが、実装時に **8 箇所**あった。漏れていたのは:

- **`startup.rb` `print_usage_for_invalid_input` の `warn error.message`** — 表では
  `handle_unexpected_error` を「同・別経路」として 2 行に数えていたが、実際には
  `print_usage_for_invalid_input` の中に**別種の警告**（Samovar の解析エラー本文）が
  もう 1 つあった。**これは最重に分類すべきものだった**——実測で `vs --bogus-option` は
  `Could not parse token "--bogus-option"` を失い、**何が読めなかったかを伝えないまま
  `--help` だけを出していた**。皮肉なことに、これが最も再現しやすい症例であり、
  §6 の検証テストはこの経路を使っている。
- **`techbook/variable_font_injector.rb` の `log_warning` フォールバック** —
  `Common` が未ロードなら `warn` へ落ちる構造で、`grep -rn "^\s*warn"` に掛かる。

**教訓**: 調査時の grep は `warn "` の形だけを見ていた。`warn error.message` のように
**引数が変数の呼び出しを取りこぼす**。`^\s*warn[ (]` で引くこと（§7 の再発防止テストは
この形を使っている）。

### 9.2 `Common.log_warn` は stdout へ出る

§6 の検証項目は「`vs lint` の **stderr** に警告が出ることを見る」と書いていたが、
`Common.emit` は `puts` を使うので**出力先は stdout** である。§5.1 で
`Common.log_warn` を選んだ以上、そちらが正しい——本プロジェクトの 🟡 はすべて
stdout に出ており、そこだけ stderr にすると揃わない。

そのため**既存テストの期待値を stderr から stdout へ移した**（`tokenizer_test.rb` 3 件・
`frontmatter_generator_test.rb` 2 件）。`$stderr.puts` で応急修正した直後の状態から
見ると出力先が動くが、応急修正のほうが暫定であって、揃えた先が本来の姿である。

### 9.3 検証テストは実際に旧実装を落とす

`contract/warning_delivery_test.rb` を書いたあと、**`startup.rb` だけを修正前へ戻して
実行し、3 件が落ちることを確かめた**（WD-01・WD-02・WD-05）。「新しいテストが通る」
だけでは、そのテストが問題を捕まえられる証拠にならない。

WD-04 は `-W0` の振る舞いそのもの（`Kernel#warn` は消え `$stderr.puts` は通る）を
実測で固定している。ここが崩れたら本仕様の前提が変わったということなので、
テストが落ちて気づける。

### 9.4 実機確認

| 確認 | 結果 |
| :--- | :--- |
| `vs --bogus-option` の stderr | `Could not parse token "--bogus-option"`（修正前は空） |
| 未クローズ `vs-lint-disable` を含む章に `vs lint --spellcheck-only` | 🟡 が stdout に出る（修正前は無出力） |
| `vs --version` の stderr | 空（`-W0` は引き続き効いている） |
| `VS_DEBUG=1` の有無 | 出力が変わらない |
