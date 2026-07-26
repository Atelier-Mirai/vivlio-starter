# CLI 引数解析の統一（オプション位置の自由化とログレベルの一本化）仕様書

> 作成日: 2026-07-27
> 改訂: 2026-07-27（方針決定を反映・§4 に決定事項を追加／**Part 1・Part 2 とも実装完了**）
> ステータス: **実装済み（2026-07-27）**
> 目的: `docs/specs/cli-option-parsing-report.md` の残件 2 件——「オプションを位置引数より前に置けない」（§3.3）と「`Common.current_log_level` が ARGV を直接走査している」（§4.3 ③）——を解消する。
> 前提: `--opt=value` 記法の共通化（`OptionTokenNormalizer`）は 2026-07-27 に実装済み。本仕様はその上に載る。
> 関連ファイル: `lib/vivlio_starter/cli/samovar/option_token_normalizer.rb`, `lib/vivlio_starter/cli/common.rb`, `lib/vivlio_starter/cli/startup.rb`, `lib/vivlio_starter/cli/samovar/*_command.rb`

---

## 1. 要約

### 達成する目標

著者が打つ**どちらの順序でも同じように動く**こと。

```
vs build 10 --no-clean   ≡   vs build --no-clean 10
vs lint  10 --fix        ≡   vs lint  --fix 10
```

**全公開コマンドで `--help` が効く**こと（内部コマンドは対象外）。

```
vs build --help / vs pdf:compress --help / vs lint --help  … すべて使い方が表示される
```

### 調査で判明したこと

- 「オプションを位置引数より前に置けない」は**問題の半分でしかなかった**。実際には**コマンドごとに制約の向きが 3 種類に分かれており、うち 1 つは黙って誤動作する**（`RootCommand.command_map` に登録された全 30 コマンドを機械的に分類・実測した結果）。
  - **[A] 位置引数が先に宣言されたコマンド**（8 個）: オプションは**位置引数より後**にしか置けない。`vs build --no-clean 10` が 🔴。
  - **[B] options が先に宣言されたコマンド**（9 個）: **制約が真逆**。位置引数はオプションより後にしか置けない。**`vs lint 10 --fix` / `vs open foo.pdf --verbose` / `vs resize images --high` が 🔴**。
  - **[C] `one` が先に宣言されたコマンド**（`pdf:pages` / `pdf:rasterize`、および options 行を持たない `pdf:compress`）: `Samovar::One` の既定パターンが `//`（何にでもマッチ）のため、**オプションを位置引数として黙って食う**。`vs pdf:pages --help` は**ヘルプが出ず**、`vs pdf:pages --dpi` は `--dpi` が入力 PDF 名として扱われ**エラーも警告も出ない**。
- `--log` については、**`options[:log_level]` が実質使われていない**ことが判明した。ログ閾値は 100% が `ARGV` の直接走査で決まっており、Samovar のオプション宣言は「ヘルプに載せる」ためだけに存在する（例外は `vs new` の 2 箇所）。このため `--log` を宣言していない 16 コマンドでも**ログ閾値だけは効く**（解析自体は 🔴 になる）という捻れが生じている。

---

## 2. 現状の調査結果（2026-07-27 実測）

### 2.1 Samovar 側の仕組み

`Samovar::Command#parse` は `table.merged.parse(input, self)` を呼び、`Table#parse` は **`@rows` を宣言順に 1 回ずつ**処理する（`table.rb:115`）。各行の消費規則は次のとおり。

| 行の種類 | 消費規則 | 出典 |
|---|---|---|
| `Options` | **`input.first` が既知フラグである間だけ**消費する（`while option = @keyed[input.first]`） | `options.rb:165` |
| `Many` | 既定 `stop: /^-/`。**`-` で始まるトークンの手前まで**消費。stop が無ければ**全部**消費 | `many.rb:88` |
| `One` | **既定 `pattern: //`**（空正規表現＝何にでもマッチ）。`input.first` を無条件に 1 つ消費 | `one.rb:21, 82` |
| `Nested` | `input.first` がサブコマンド名なら消費して子へ委譲 | `nested.rb:85` |

要点は 2 つ。

1. **`Options` は先頭から連続する分しか消費しない。** 一度でも非オプションに当たるとその場で止まり、`Table#parse` は同じ行へ戻ってこない。したがって**オプションが位置引数を挟んで分かれていると必ず失敗する**（実測 §2.3 [D]）。
2. **`One` は `-` で始まるトークンを拒まない。** `many` は `stop: /^-/` で自衛しているが、`one` は既定パターンが `//` のため丸ごと食う。

### 2.2 コマンドの宣言順（登録済み全 30 コマンド）

`RootCommand.command_map` に登録されたコマンドについて `table.merged` の行順を機械的に列挙し、あわせて `['x', '-h']`（後置き）と `['-h', 'x']`（前置き）の両方を実際に解析させた結果:

| 分類 | 宣言順 | コマンド | 後置き | 前置き |
|---|---|---|---|---|
| **[A]** 位置引数が先 | `many` → `options` | `build` / `create` / `delete` / `import` / `new` / `preflight` / `rename` / `renumber`（8） | ✅ | 🔴 |
| **[B]** options が先 | `options` → `many` or `one` | `cover` / `index:auto` / `index:export` / `index:import` / `lint` / `metrics` / `open` / `pdf:read` / `resize`（9） | 🔴 | ✅ |
| **[C]** `one` が先 | `one` → `options` | `pdf:pages` / `pdf:rasterize`（2） | ✅ | 🔴（`-h` を食う） |
| **[C']** options 行なし | `one` → `one` | `pdf:compress`（1） | ✅ | ✅（**両方 `one` に食われる**） |
| — | 位置引数を持たない | `clean` / `create:colophon` / `create:cover` / `create:legalpage` / `create:titlepage` / `doctor` / `help` / `index` / `index:apply` / `upgrade`（10） | 🔴 | 🔴 |

`RootCommand` 自身は `options` → `nested` の順で、[B] と同じ形。

この宣言順の違いは意図されたものではなく、コマンドを書いた時期による偶然と見られる（仕様書・コメントに根拠の記述がない）。

なお **`pdf:compress` と `create:cover` は `options` 行そのものを持たない**（`-h/--help` すら宣言されていない）。前者は `-h` が `one :input` に食われるため `help_requested?` の対症療法（§2.3）で救済されているが、後者は `vs create:cover -h` が 🔴 になる。

### 2.3 実測表

いずれも `Command.new(argv)` を直接呼び、`call` はしていない。

**[A] 位置引数が先＝オプションは後置きのみ**

| 入力 | 結果 |
|---|---|
| `build --no-clean x.md` | 🔴 `Could not parse token "x.md"` |
| `build x.md --no-clean` | ✅ `targets=["x.md"]` |
| `rename --force 11 12` | 🔴 `Could not parse token "11"` |
| `rename 11 12 --force` | ✅ `arguments=["11", "12"]` |

**[B] options が先＝位置引数は後置きのみ（[A] と真逆）**

| 入力 | 結果 |
|---|---|
| `lint a.md --fix` | 🔴 `Could not parse token "--fix"` |
| `metrics 10 --all` | 🔴 `Could not parse token "--all"` |
| `open foo.pdf --verbose` | 🔴 `Could not parse token "--verbose"` |
| `resize images --high` | 🔴 `Could not parse token "--high"` |
| `index:auto 10 --verbose` | 🔴 `Could not parse token "--verbose"` |

**[C] `one` がオプションを食う（エラーも警告も出ない）**

| 入力 | 結果 | 深刻度 |
|---|---|---|
| `pdf:pages -h` | ✅ `input="-h"`, `help=nil` — **ヘルプが出ない** | 高（沈黙） |
| `pdf:pages --dpi` | ✅ `input="--dpi"`, `dpi=350`（既定のまま） | 高（沈黙） |
| `pdf:compress -h` | ✅ `input="-h"`, `output=nil` | 高（沈黙） |
| `pdf:pages --dpi 200` | 🔴 `Could not parse token "200"` | 中 |

pdf 系にはこの誤食に対する**対症療法が既に入っている**——`help_requested?`（`pdf_command.rb:55`）が「位置引数として食われた値が `-h`/`--help` か」を判定してヘルプを出している。ヘルプは救えているが、`--dpi` のように**オプションが黙って入力ファイル名にすり替わる**ケースは救えていない。

**[D] オプションの挟み撃ちは必ず失敗する**

| 入力 | 結果 |
|---|---|
| `lint --fix a.md --register` | 🔴 `Could not parse token "--register"` |
| `build x.md --no-clean --log debug` | ✅（オプションが連続しているため） |

### 2.4 ログレベルの実態

```ruby
# lib/vivlio_starter/cli/common.rb:355
def current_log_level
  case ARGV
  in [*, /^--log=(.+)$/, *] then LEVELS[::Regexp.last_match(1).downcase] || 2
  in [*, '--log', level, *] if LEVELS.key?(level) then LEVELS[level]
  in [*, '--log', *] then 2
  else 1
  end
end
```

1. **`options[:log_level]` は実質使われていない。** 参照は `NewCommand#debug?` と `new.rb:256` の 2 箇所（どちらも `vs new` 専用）のみ。`build` / `preflight` の `options[:log_level]` は**宣言されているが誰も読まない**。実際の閾値は 16 箇所すべてが `Common.current_log_level` 経由＝ARGV 走査で決まる。
2. **`--log` を宣言しているのは 3 コマンドのみ**（`build` / `preflight` / `new`）。他 16 コマンドでは `vs lint --log=debug` が 🔴 `Could not parse token` になる。**にもかかわらずログ閾値は 3（debug）に上がる**ため、「エラーにはなるがエラーメッセージだけは debug 詳細で出る」という捻れが起きる。
3. **大文字の扱いが記法によって違う。** `--log=DEBUG` は `downcase` されて 3 になるが、`--log DEBUG` は `LEVELS.key?('DEBUG')` が偽のため 2（info）へ落ちる。
4. **不正な値は黙って info になる。** `--log=verbose` は `LEVELS['verbose']` が nil のため `|| 2`。タイプミスに気づけない。
5. **ログ 1 行ごとに ARGV を全走査する**（メモ化なし）。
6. `startup.rb:14` が `args = Array(argv).dup` としているため **ARGV 自体は消費されず保持される**。`OptionTokenNormalizer` が書き換えるのは dup 側なので、**`=` 記法の共通化はログレベルの挙動に影響していない**（実測で確認済み）。

### 2.5 `log_info` 系の内容（`--log` の配布範囲を決めるための調査）

`log_info` 系（🔵 情報・✅ 成功・🔧 動作）は既定で非表示のため、`--log` を配るかどうかの判断材料として実際の出力内容を確認した。

| ドメイン | `log_debug`（🧪） | `log_info` 系 | 内容の例 |
|---|---|---|---|
| build | 6 | 123 | ビルド段階の進捗 |
| pre_process | 2 | 63 | 章ごとの前処理経過 |
| index | 0 | 52 | 索引スキャンの進捗 |
| clean | 0 | 28 | `🔵 .cache/metrics を削除しました` |
| rename | 0 | 23 | `🔵 images/11-workflow → images/12-workflow` |
| import | 0 | 33 | 変換ステップの経過 |
| metrics / upgrade | 0 | 0 | — |

**結論: 量は実益の証拠にならなかった。** `clean` / `rename` の `log_info` は「どのキャッシュファイルを消したか」「どのディレクトリを改名したか」といった内部トレースであり、**著者が読む必要のある情報ではない**（改名結果はエディタのツリービューで分かり、そもそも `vs rename 11 21` と打った本人が結果を知っている）。これらは ⑤ command-feedback-spinner の「削除しました」「改名しました」で足りる。

対照的に `build` / `preflight` は段階が多く経過を追う意味があり、`new` はプロジェクト生成の内訳を確認する意味がある。**`--log` はこの 3 コマンドに限定する**（§4 決定 D3）。

---

## 3. 課題の整理

| # | 課題 | 深刻度 | 由来 |
|---|---|---|---|
| P1 | コマンドごとにオプションの置ける位置が違う（[A] と [B] が真逆） | **高** | 宣言順の不統一 |
| P2 | `one` がオプションを黙って食う（`-h` すら） | **高**（沈黙するため） | `One` の既定 `pattern: //` |
| P3 | オプションの挟み撃ちが通らない | 中 | `Options` が先頭連続分しか消費しない |
| P4 | `pdf:compress` に `--help` がない（公開コマンドなのに） | 中 | options 行の欠落 |
| P5 | ログ閾値が ARGV 走査に依存し、オプション宣言と分離している | 中 | 歴史的経緯 |
| P6 | `--log` の大文字の扱いが記法で非対称／不正値が黙って通る | 低 | 実装の粗 |

---

## 4. 決定事項

| # | 論点 | 決定 |
|---|---|---|
| **D1** | 宣言順の扱い | **現状の宣言順を維持**し、正規化器が**寄せる向きを宣言順から自動判定**する（[C] の 3 クラスのみ是正）。usage 表示は変わらない（旧 Q1(a)） |
| **D2** | 正規化器の配り方 | **共通基底クラス `VsCommand` を新設**し `prepend OptionTokenNormalizer` を集約する。**`options` は置かない**——置くと `table.merged` の行順が `Options` 先に固定され D1 が崩れるため（実測確認済み）（旧 Q2(b) の改） |
| **D3** | `--log` の配布範囲 | **`build` / `preflight` / `new` の 3 コマンドに限定**（現状維持）。§2.5 のとおり他コマンドの `log_info` は著者向けの情報ではないため、⑤ command-feedback-spinner の応答メッセージへ委ねる |
| **D4** | `--help` の配布範囲 | **全公開コマンド（26）で有効にする**。未宣言は `pdf:compress` のみのため 1 行追加で足りる。**内部コマンド 4 個（`create:cover` / `create:titlepage` / `create:colophon` / `create:legalpage`）は対象外** |
| **D5** | 不正なログレベル値 | **🟡 警告して `info` で続行**（旧 Q3(a)） |
| **D6** | 実施順 | **Part 1 → Part 2**（旧 Q4(a)） |
| **D7** | 既存 `log_info` 群の扱い | **今回は触らない。** ⑤ command-feedback-spinner の実装時に「何を既定で出すか」の設計資料として使い、応答メッセージへ整理統合したうえで削除する（§10.3） |

---

## 5. Part 1: 引数順序の自由化

### 5.1 方針

**`OptionTokenNormalizer` に「トークンの仕分け」を追加し、オプション群と位置引数群を、そのコマンドの宣言順に合わせて並べ替える。**

`Options` は先頭から連続する分しか消費しない（§2.1）ため、**オプションを 1 箇所に固めれば 1 回の走査で全部消費できる**。固める位置は宣言順から決める:

| コマンドの宣言順 | Samovar へ渡す形 | 対象 |
|---|---|---|
| `options` が先 | `[オプション群] + [位置引数群]` | [B] |
| 位置引数が先 | `[位置引数群] + [オプション群]` | [A] |

各群の**内部の相対順序は保つ**（`vs rename 11 12` の `11` と `12` の順序は意味を持つ）。

**これは正規化器が Samovar へ渡す前の内部形式の話であり、著者が打つ順序を制約しない。** どちらの順で打っても同じ形に揃うため、結果が一致する。

```
著者の入力                   正規化器の出力       Samovar の解釈
vs build 10 --no-clean  →   10 --no-clean   →   targets=["10"] clean=false
vs build --no-clean 10  →   10 --no-clean   →   targets=["10"] clean=false
                             ↑ どちらも同じ形へ
```

この方針は P1・P3 を解消する。**P2（`one` の誤食）は並べ替えだけでは解消しない**ため、§5.3 で別に扱う。

### 5.2 仕分けの規則

現在 `value_option_flags` は「値を取るフラグ」だけを導出しているが、並べ替えには**全フラグ名**が要る。同じ仕組み（`table.merged` の走査）で `Samovar::Flag` すべての `prefix` と `alternatives` を集める `all_option_flags` を追加する。

トークン列を先頭から走査し:

1. **既知のフラグ名**（`all_option_flags` に含まれる） → オプション群へ。**値を取るフラグ**（`value_option_flags`）なら、直後のトークンが `-` で始まらない場合に限り**値も一緒に**オプション群へ移す。
2. **それ以外** → 位置引数群へ。

**未知の `-xxx` は位置引数群へ入れる**（現状と同じく Samovar が 🔴 にする）。これにより「タイプミスしたオプションが黙ってオプション扱いされる」ことを防ぐ。

```
vs build --theme blue 10 20
  → 位置引数群 [10, 20] + オプション群 [--theme, blue]
  → build 10 20 --theme blue            （[A] なので位置引数が先）

vs lint a.md --fix b.md --register
  → オプション群 [--fix, --register] + 位置引数群 [a.md, b.md]
  → lint --fix --register a.md b.md     （[B] なので options が先）
```

プロトタイプで次の動作を実証済み:

| 入力 | 結果 |
|---|---|
| `build 10 --no-clean` / `build --no-clean 10` | ともに `targets=["10"] clean=false` |
| `lint 10 --fix` / `lint --fix 10` | ともに `files=["10"] fix=true` |
| `build 10 20 --log debug` / `build --log=debug 10 20` | ともに `targets=["10","20"] log="debug"` |
| `lint --fix a.md --log`（挟み撃ち） | `files=["a.md"] fix=true log="info"` |

### 5.3 P2（`one` の誤食）への対応

[C]・[C'] の 3 コマンド（`pdf:pages` / `pdf:rasterize` / `pdf:compress`）は `one` が `options` より先に宣言されているため、並べ替えでオプションを末尾へ寄せても `one` が先に走り `-h` を食う。**宣言順を `options` → 位置引数 へ変更する**ことで根治する（[B] と同じ形になり、並べ替えの向きも [B] と揃う）。

| 変更するクラス | 現在 | 変更後 | 備考 |
|---|---|---|---|
| `PdfCompressCommand` | `one :input` → `one :output` | `options` → `one :input` → `one :output` | **`-h/--help` の options 自体が存在しない**ため新設する（D4） |
| `PdfPagesCommand` | `one :input` → `options` | `options` → `one :input` | |
| `PdfRasterizeCommand` | `one :input` → `options` | `options` → `one :input` | |

これにより `help_requested?` / `help_flag_argument?`（`pdf_command.rb:55-61`）の対症療法は不要になるため**撤去する**（`options[:help]` を見る他コマンドと同じ形へ揃える）。

なお [B] の `one`（`cover` / `open` / `pdf:read` / `resize`）は `options` が先に走ってフラグを消費し尽くすため、誤食は起きない（実測で確認済み）。`one` に `pattern` を与える案も検討したが、宣言順の是正で構造的に解決するため採らない。

### 5.4 基底クラス `VsCommand`（D2）

```ruby
# lib/vivlio_starter/cli/samovar/vs_command.rb
module VivlioStarter
  module CLI
    module SamovarCommands
      # 公開コマンドの基底クラス。
      # 引数順序の正規化だけを配る（options はあえて置かない——基底に options を
      # 宣言すると Table#merged が親の行を先に並べるため、子の宣言順に関わらず
      # 行順が Options 先に固定され、D1「宣言順を維持する」が成立しなくなる）。
      class VsCommand < Samovar::Command
        prepend OptionTokenNormalizer
      end
    end
  end
end
```

- **公開 26 コマンドが継承する。** `prepend` は継承先へ届くことを実測で確認済み。
- **内部 4 コマンドは `Samovar::Command` のまま**（D4）。位置引数を持たず並べ替えの余地がないため、実害はない。
- `RenumberCommand < RenameCommand` のような既存の継承関係は維持する（`RenameCommand` が `VsCommand` を継承すれば `RenumberCommand` にも届く）。

### 5.5 互換性

- **現在通る入力はすべて通り続ける。** 並べ替えは「宣言順に合わせて固める」だけで、現在通っている入力は既にその形になっている。
- **現在 🔴 だった入力が通るようになる**（後方互換を壊さない方向の変更）。
- **usage 表示は変わらない**（D1・D2 により宣言順を維持するため）。ただし [C] の 3 クラスだけは宣言順を変えるため `pdf:pages <input> [--dpi <value>] …` → `pdf:pages [--dpi <value>] … <input>` となる。
- ただし **[C] の宣言順変更と `OptionTokenNormalizer` の適用はセットで入れる必要がある。** 宣言順だけ変えると `vs pdf:pages a.pdf --dpi 200` が壊れる（`options` が先に走るが `input.first` が `a.pdf` なので何も消費せず、`one` が `a.pdf` を取り、残った `--dpi 200` を誰も消費しない）。

---

## 6. Part 2: ログレベルの一本化

### 6.1 方針

**`--log` は宣言のあるコマンドだけが受け付ける**ものとし、ログ閾値は**その解析結果から 1 回だけ決めて保持する**。`ARGV` の直接走査は廃止する。

これにより P5 の捻れ——「宣言していないコマンドで `--log` を打つと 🔴 になるのに閾値だけは効く」——が構造的に解消する。`--log` を宣言しないコマンドでは、`--log` は単に無効なオプションとして一貫して扱われる。

```ruby
# lib/vivlio_starter/cli/startup.rb
def start(argv)
  args = Array(argv).dup
  command = SamovarCommands::RootCommand.parse(args)
  Common.apply_log_level!(command)   # ← 解析結果から 1 回だけ決める
  result = command.call
  ...
```

```ruby
# lib/vivlio_starter/cli/common.rb
def current_log_level = @log_level || DEFAULT_LOG_LEVEL   # 呼び出し 16 箇所は変更不要
def log_level=(level) ...                                  # テスト・ライブラリ利用向け
def apply_log_level!(command) ...                          # options[:log_level] から解決
```

- **`current_log_level` の名前と戻り値（Integer）は変えない**ため、16 箇所の呼び出しは無変更。
- `Common.log_level=` を公開することで、**テストが ARGV を汚さずに**レベルを制御できるようになる。
- **解析前（`RootCommand.parse` より前）に出る出力は既定レベル（warn）になる。** 現状は ARGV 走査により未知コマンドのエラー表示まで debug になりえたが、解析に失敗した入力のログ指定を尊重する必要はないため、簡潔さを採る。

### 6.2 解決規則（現状からの変更点）

`--log=<level>` / `--log <level>` / 値なし `--log`（= `info`）を受け付ける点は現状どおり。次を是正する。

| # | 現状 | 変更後 |
|---|---|---|
| 1 | `--log=DEBUG` は 3、`--log DEBUG` は 2（記法で非対称） | **両記法とも `downcase` して照合**し、`DEBUG` はどちらも 3 |
| 2 | `--log=verbose` は黙って info | **🟡 警告して `info` へ倒す**（D5） |
| 3 | ログ 1 行ごとに ARGV を全走査 | 起動時 1 回の解決結果を保持 |

不正値の警告文（`warning-messages-actionable` の方針に従い、具体的な修正案と選択肢を添える）:

```
🟡 --log=verbose は不明なログレベルです。
   対処: error / warn / info / debug のいずれかを指定してください（今回は info で続行します）。
```

値なし `--log` の既定 `info` は `OptionTokenNormalizer::BARE_VALUE_DEFAULTS` を唯一の定義とし、`Common` 側はそれを参照する（2 箇所に別々の既定値を置かない）。

### 6.3 `vs new` の 2 箇所

`NewCommand#debug?` と `new.rb:256` は `options[:log_level] == 'debug'` を直接見ている。`Common.current_log_level >= 3` へ寄せ、`--log` の解釈経路を 1 本にする。

---

## 7. 実装計画

Part 1 と Part 2 は独立しており、D6 のとおり Part 1 から着手する。

### Part 1 — ✅ 実装完了（2026-07-27）

| 手順 | 内容 | 対象 | 状態 |
|---|---|---|---|
| 1-1 | `all_option_flags`（全フラグ名の自動導出）を追加 | `option_token_normalizer.rb` | ✅ |
| 1-2 | トークン仕分けと並べ替えを追加（寄せる向きは `options_declared_first?` が宣言順から判定） | `option_token_normalizer.rb` | ✅ |
| 1-3 | 基底クラス `VsCommand`（`prepend` のみ・`options` なし）を新設 | `samovar/vs_command.rb`（新規） | ✅ |
| 1-4 | 公開コマンドの `superclass` を `VsCommand` へ変更し、個別の `prepend` を削除 | 18 ファイル・25 クラス（`RenumberCommand` は継承で追随） | ✅ |
| 1-5 | [C] 3 クラスの宣言順を `options` 先へ変更・`pdf:compress` に `-h/--help` 新設 | `pdf_command.rb` | ✅ |
| 1-6 | `help_requested?` / `help_flag_argument?` を撤去し `options[:help]` へ統一 | `pdf_command.rb`（3 クラス分） | ✅ |

**実装時の補足**

- `all_option_flags` は `BooleanFlag` の `alternatives` に `--no-xxx` が入るため、`[prefix, *alternatives]` を集めるだけで否定形も文字列一致で拾えた（`prefix?` を呼ぶ必要はない）。
- 綴り間違い（`--no-cleen`）と、値を取らないフラグへの `=` 付き指定（`--no-clean=1`）は**位置引数側へ送って従来どおり 🔴 にする**。黙ってオプション扱いすると誤りに気づけないため。
- `RootCommand` は `command_map` に含まれないルーターのため `VsCommand` を継承させていない（`options` → `nested` の順で既に正しく動作する）。
- 検証結果: `rake test` **1966 runs, 0 failures**（+12 件）／`rake test:standard` 同数／RuboCop **393 files, no offenses**。

### Part 2 — ✅ 実装完了（2026-07-27）

| 手順 | 内容 | 対象 | 状態 |
|---|---|---|---|
| 2-1 | `apply_log_level!` / `log_level=` を追加し `current_log_level` を保持値の参照に変更 | `common.rb` | ✅ |
| 2-2 | `CLI.start` で解析後に 1 回だけ適用する | `startup.rb` | ✅ |
| 2-3 | 大文字統一・不正値の 🟡 警告を実装 | `common.rb` | ✅ |
| 2-4 | `vs new` の 2 箇所を `Common.current_log_level` へ寄せる | `new_command.rb` / `new.rb` | ✅ |

**実装時の補足**

- **状態は `class << self` の `@log_level` に置いた。** `Common` は `module_function` を使っており、そのままインスタンス変数を書くと include 先のオブジェクトごとに別の変数になってしまう。`current_log_level` は `Common.log_level` を明示的に呼ぶため、include 経由でも同じ値を見る（テストで固定）。
- **`BARE_VALUE_DEFAULTS` の参照は不要だった**（§6.2 の想定からの変更）。値なし `--log` は正規化器が `info` へ開いてから Samovar に渡すため、`Common` へ届く時点では具体的な値か `nil` しかない。既定値の定義は正規化器の 1 箇所だけで完結する。
- **`CLI.start` を通らない呼び出しはログレベルが既定のままになる。** `NewCommand.new(...).call` を直接呼ぶテストは `Common.apply_log_level!` を挟んで実運用の流れを再現した（`new_commands_test.rb`）。
- ARGV を触っていた既存テスト（`index_step_scope_test.rb`）は `Common.log_level=` へ移行し、ARGV を汚さなくなった。
- 検証結果: `rake test` **1977 runs, 0 failures**（+11 件）／`rake test:standard` 同数／RuboCop **394 files, no offenses**。

---

## 8. テスト計画

### Part 1

- **並べ替えの単体テスト**（`option_token_normalizer_test.rb` に追加）
  - [A] `build 10 --no-clean` と `build --no-clean 10` が**同じ結果**になる
  - [B] `lint 10 --fix` と `lint --fix 10` が**同じ結果**になる
  - [C] `pdf:pages --help` → `help=true`, `input=nil`（**回帰の要**）
  - [C] `pdf:pages --dpi 200` → `dpi=200`, `input=nil`
  - [D] 挟み撃ち `lint --fix a.md --register` → 両オプションが効く
  - 位置引数の相対順序が保たれる（`rename 11 12 --force` と `rename --force 11 12` が同じ `arguments`）
  - 値を取るオプションの値が位置引数と誤認されない（`build --theme blue 10` → `theme="blue"`, `targets=["10"]`）
  - 未知の `-xxx` は位置引数として扱われ、従来どおり 🔴 になる
- **全コマンド横断の契約テスト**: 全公開コマンドについて「オプションを前に置いても後に置いても同じ解析結果になる」ことを機械的に検証する（コマンド定義から入力を自動生成）。宣言順の取り違えを構造的に防ぐ。
- **`--help` の契約テスト**: 公開 26 コマンドすべてで `--help` / `-h` が `options[:help]` を立てること（`pdf:compress` を含む）。

### Part 2

- `apply_log_level!` の単体テスト（`--log=debug` / `--log debug` / `--log=DEBUG` / `--log DEBUG` / bare `--log` / 未指定 / 不正値）
- **ARGV を汚さずに**レベルを設定できること（`Common.log_level = 3`）
- 不正値で 🟡 警告が出て `info` で続行すること
- `--log` を宣言しないコマンドで `--log` が 🔴 になること（捻れの解消を固定する）
- `vs new --log debug` のデバッグ出力が従来どおり出ること（`new_commands_test.rb` の既存テストが通ること）

---

## 9. 影響評価

| 観点 | 評価 |
|---|---|
| 利用者影響 | **改善（大）**。`vs build 10 --no-clean` / `vs lint 10 --fix` という自然な打ち方が通る。`vs pdf:compress --help` でヘルプが出るようになる |
| 後方互換 | **壊さない**。現在通る入力はすべて通り続け、現在 🔴 だった入力が通るようになるだけ |
| usage 表示 | **[C] の 3 コマンド以外は不変**（D1・D2 による） |
| 実装規模 | Part 1: 正規化器 +40 行程度、基底クラス 1 ファイル、26 クラスの `superclass` 変更、`pdf_command.rb` の宣言順変更と対症療法撤去。Part 2: `common.rb` / `startup.rb` の小改修 |
| リスク | **低〜中**。正規化はトークン列の並べ替えのみで本処理に触れない。ただし [C] の宣言順変更は正規化器とセットでなければ壊れる（§5.5）ため、同一コミットで入れる |
| 残件 | Samovar 本体への `=` 対応提案（`cli-option-parsing-report.md` §7 案 C）は引き続き未実施 |

---

## 10. 調査中に見つかった別件（本仕様のスコープ外）

### 10.1 `IndexBuildCommand` の残存 — ✅ 解消（2026-07-27）

`vs index:build` は廃止済みだったが、**`IndexBuildCommand` のクラス定義（`index_command.rb:208-236`）だけが残っていた**。`RootCommand.command_map` に登録されておらず CLI からは到達できない完全なデッドコードで、`docs/archives/test-suite-expansion-spec.md:413` の記述から**ドキュメント側からは削除されたがクラス本体の削除が漏れた**ものと判明した。

削除にあたり、索引ページ生成の実処理が別経路で生きていることを確認した。

```
build/pipeline.rb:457  →  IndexCommands.process_index_for_build!（index.rb:46）
                       →  UnifiedIndexManager#build_index!（unified_index_manager.rb:355）
```

`IndexBuildCommand` はこの `build_index!` を独自に呼び直していただけで、ビルド経路は同メソッドを `process_index_for_build!` 経由で呼んでいる。クラスを削除しても索引生成には影響しない（`rake test` 1977 runs で確認）。

あわせて実態と食い違っていたコメント 2 箇所も是正した。

| 箇所 | 旧記述 | 是正後 |
|---|---|---|
| `index_command.rb:16` | `- index:build: 索引ページを生成（vs build から呼ばれる）` | 索引ページ生成はコマンドを持たず、パイプラインが `process_index_for_build!` を直接呼ぶ旨に変更 |
| `unified_index_manager.rb:147` | `仕様: vs index:apply は内部で vs index:build を実行しない` | 「辞書を更新するだけで索引ページの生成は行わない（生成はパイプラインの責務）」へ変更 |

これで **CLI から到達できない孤立コマンドクラスはゼロ**になった（登録済み 30 コマンド）。

### 10.2 `create:cover` に `--help` がない

内部コマンドのため**対応不要**（D4）。`vs create:cover -h` は 🔴 のままとする。

### 10.3 `clean` / `rename` などの `log_info` 群（⑤ へ引き継ぐ）

D3 により `--log` を配らないため、`clean`（28 箇所）・`rename`（23 箇所）・`import`（33 箇所）などの `log_info` 系は**出力される機会のないコードとして残る**。

**⑤ command-feedback-spinner の実装時に、これらを「著者に何を返すべきか」の設計資料として使う**。`vs clean` なら「削除しました」、`vs rename` なら「改名しました」といった応答メッセージへ整理統合し、**統合が済んだ時点で元の `log_info` 群を削除する**。この順序であれば、既存メッセージが持つ情報（何を対象にどんな操作をしたか）を取りこぼさずに済む。
