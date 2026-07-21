# CLI オプション解析（`--opt=value` 対応とトークン正規化の重複）に関する調査報告

> 作成日: 2026-07-21
> ステータス: **未対応（棚上げ・将来のリファクタリング資料）**。`vs build` のみ 2026-07-21 に個別対応済み
> 目的: `vs build --theme=blue` が動かなかった件の調査で判明した「`=` 区切りオプションの対応状況がコマンドごとにバラバラ」「トークン正規化の実装が複製され片方だけ直っている」構造を記録し、将来の共通化リファクタリングの資料とする。
> 関連ファイル: `lib/vivlio_starter/cli/samovar/build_command.rb`（正規化・2026-07-21 改修済み）, `lib/vivlio_starter/cli/samovar/preflight_command.rb:156`（複製・未改修）, `lib/vivlio_starter/cli/samovar/new_command.rb`・`lib/vivlio_starter/cli/samovar/pdf_command.rb`（正規化なし）, `lib/vivlio_starter/cli/common.rb`（`current_log_level` の ARGV 直接走査）

## 1. 要約

- Samovar（2.4.1 / 2.5.1 とも）は **`--opt=value` 記法を解さない**。`--log=debug` のようなトークンは「解釈できないトークン」として弾かれ、`vs` は 🟡 とともに `--help` を表示して終わる。
- そのため `build` は独自のトークン正規化（`--log=x` → `--log x` へ開く）を `#initialize` に持っている。**この実装は 2026-04-13 の「preflight 実装」コミットで `preflight_command.rb` へそのままコピーされた**（当時 build 側は 1 行も変更されていない＝純粋な複製）。
- 結果、**同じ機能の実装が 3 系統**に散っている: ① build の正規化 ② preflight の正規化（①の複製）③ `Common.current_log_level` の ARGV 直接走査（`--log=x` を独自に正規表現で解釈）。
- コピー元にあった**バグ（値なし `--log` の直後のトークンが黙って捨てられる）も複製されている**。2026-07-21 に build 側だけを修正したため、**現在は名前も中身も違う 2 実装**になっている（分岐が開き始めた状態）。
- さらに `new` / `pdf:*` は正規化を持たず、**`vs new mybook --log=debug` や `vs pdf:pages a.pdf --dpi=200` は今も落ちる**。著者から見ると「`=` が使えるコマンドと使えないコマンドがある」という一貫性のない CLI になっている。

## 2. 発端

`vs build ./number_games/number_games.md --theme=blue` が

```
🟡 代わりに --help を表示します。
```

となった（2026-07-21・利用者報告）。`--theme blue`（空白区切り）なら動くが `--theme=blue` は動かない。一方 `--log=info` は動くため、「`=` は使えるはず」という利用者の期待と食い違っていた。

## 3. 根本原因（Samovar の実装）

読んだのは `samovar-2.5.1`（実行時は bundler 経由で 2.4.1・挙動は実測で同一）。

### 3.1 `=` 記法を解さない

`Samovar::Options#parse`（`lib/samovar/options.rb:165`）:

```ruby
while option = @keyed[input.first]
  result = option.parse(input)
  ...
end
```

`@keyed` は**フラグ文字列そのもの**（`--log`）をキーにしたハッシュで、トークンの完全一致でしか引けない。`Flag#prefix?`（`lib/samovar/flags.rb:204`）も `@prefix == token` の等値比較で、Samovar 内に `=` を分割する処理は存在しない。よって `--log=debug` はどのオプションにも一致せず、ループを抜けて**未消費のまま残り** `Could not parse token "--log=debug"` になる。

### 3.2 値フラグは次のトークンを無条件に食う

`ValueFlag#parse`（同 213 行）:

```ruby
if prefix?(input.first)
  if @value
    flag, value = input.shift(2)   # ← 次のトークンを無条件に値とみなす
    return value
```

したがって素の Samovar では `--log --no-clean` は「`--log` の値＝`--no-clean`」と解釈される。プロジェクト側の正規化が値なし `--log` に `info` を補っているのは、この挙動への対処である（設計としては妥当）。

### 3.3 オプションは位置引数より後にしか置けない

`Many#parse`（`lib/samovar/many.rb:88`・既定 `stop: /^-/`）は「`-` で始まるトークンに当たるまで」を貪欲に取る。`Command` は宣言順（`many :targets` → `options`）に解析し、`Options#parse` は `input.first` が一致する間しか消費しない。

```
vs build x.md --no-clean   → OK
vs build --no-clean x.md   → 🔴 Could not parse token "x.md"
vs build --high 10         → 🔴 Could not parse token "10"
```

これは `--theme` 固有ではなく**全オプション共通の既存挙動**である（今回の変更で生じたものではない）。

## 4. 重複の実態

### 4.1 履歴

`git log -S "normalize_log_option_tokens"`（識別子の増減があったコミットのみ）:

| コミット | 日付 | 内容 |
|---|---|---|
| `af93e746` | 2025-12-25 | Samovar 化 — `build_command.rb` に初出 |
| `b6e2b423` | **2026-04-13** | **「preflight 実装」— `preflight_command.rb` へコピー**（同コミットで build 側は無変更） |
| `be395945` | 2026-04-25 | `vs build 00` の不具合修正（build 側のみ） |
| `9a1bfc2b` | 2026-05-21 | 名前空間フラット化に伴うファイル移動 |

2026-07-21 の改修前まで、両者は**空行 1 つを除いて完全一致**していた（差分で確認）。

### 4.2 複製されたバグ — 値なし `--log` の直後のトークンが消える

改修前の実装（現在も preflight に残る）:

```ruby
if next_value.nil? || next_value.start_with?('-')
  normalized << 'info'
  idx += 1        # ← ここで 1 進め
else
  ...
  next            # 値ありの経路は next で末尾の += 1 を回避している
end
...
idx += 1          # ← ループ末尾でもう 1 進む＝合計 2
```

値なし `--log` のときだけインデックスが 2 進み、**次のトークンが `normalized` に積まれないまま読み飛ばされる**。

実測（2026-07-21 時点）:

| コマンド | 入力 | 結果 |
|---|---|---|
| build（改修後） | `--log --no-clean` | `clean=false` ✅ |
| preflight（未改修） | `--log --no-verify` | `verify=true` ❌ **`--no-verify` が消える** |
| preflight（未改修） | `--no-verify --log` | `verify=false` ✅（順序を変えれば効く） |

「`--log=info --no-verify` と書けば効くのに `--log --no-verify` だと効かない」という、原因の見当がつかない非対称になる。

### 4.3 「`--log` を解釈する実装」が 3 系統ある

| # | 場所 | 解釈方法 | 用途 |
|---|---|---|---|
| ① | `build_command.rb`（改修後 `normalize_value_option_tokens`） | トークン列を書き換えて Samovar へ渡す | `options[:log_level]` |
| ② | `preflight_command.rb:156`（`normalize_log_option_tokens`） | 同上（①の 2026-04-13 時点のコピー） | `options[:log_level]` |
| ③ | `common.rb` `current_log_level` | **`ARGV` をパターンマッチで直接走査**（`/^--log=(.+)$/` と `['--log', level]` の 2 形） | 実際のログ出力の閾値 |

③ が独立しているため、**Samovar が弾いたオプションでもログレベルだけは効く**という捻れがある（例: `vs new mybook --log=debug` は解析エラーになるが、エラー表示自体は debug レベルで出る）。また `new_command.rb` の `--log` はキー名が `:log`（build/preflight は `:log_level`）で、ここも揃っていない。

## 5. コマンド横断の対応状況（2026-07-21 実測）

値を取るオプション（`option '--x <y>'` 形式）を持つ全コマンドで `--opt=value` を試した結果:

| コマンド | オプション | `=` 記法 | 正規化の有無 |
|---|---|---|---|
| `build` | `--log` / `--theme` | ✅ 動く | あり（2026-07-21 改修済み） |
| `preflight` | `--log` | ✅ 動く | あり（①の複製・**バグ残存**） |
| `new` | `--log` | 🔴 `Could not parse token "--log=debug"` | なし |
| `pdf:pages` | `--dpi` / `--pages` / `--output` | 🔴 同上 | なし |
| `pdf:rasterize` | `--dpi` / `--quality` | 🔴 同上 | なし |

ブール系オプション（`--no-clean`・`--high` 等）は値を取らないため `=` の問題は起きない。

## 6. 影響評価

- **利用者影響（中）**: `=` が使えるコマンドと使えないコマンドが混在する。`--dpi=200` のような数値オプションは `=` で書く習慣が強く、踏みやすい。
- **利用者影響（低〜中）**: preflight の `--log <他オプション>` でオプションが黙って無視される。**エラーも警告も出ない**ため気づけない（`vs preflight --log --no-verify` で検証が走ってしまう）。
- **保守影響（中）**: 現状は「同じ責務の 3 実装」。今回 build だけ直したことで**名前も中身も異なる 2 実装**になり、次に誰かが preflight を直しても build と揃う保証がない。
- **リスク（低）**: 正規化は `#initialize` でトークン列を書き換えるだけで、本処理には触れない。共通化の副作用は小さい。

## 7. 対応の選択肢

### 案 A: 正規化を 1 箇所へ共通化する（推奨）

`SamovarCommands` 配下に小さなモジュール（例: `OptionTokenNormalizer`）を置き、各コマンドは「値を取るオプションと既定値の表」だけを宣言する。

```ruby
module OptionTokenNormalizer
  # VALUE_OPTIONS = { '--log' => 'info', '--theme' => nil } を持つクラスで include する
  def normalize_value_option_tokens(input) = ...
end
```

- 利点: 重複が構造的に消える。`new` / `pdf:*` へ `include` 1 行で展開でき、CLI 全体で `=` 記法が揃う。
- 注意: `pdf_command.rb` は `type: Integer` の値を持つ（`--dpi=200` → `'200'` を渡せば Samovar が型変換するので問題ないが、テストで確認すること）。
- 規模: 新規モジュール 1 ファイル ＋ 各コマンド 2〜3 行。

### 案 B: `preflight` にも同じ修正を移植するだけ

- 利点: 変更最小・影響範囲が明確。
- 欠点: 複製は残り、次の複製を誘発する。`new` / `pdf:*` の `=` 非対応も残る。

### 案 C: Samovar 本体へ `=` 対応を提案（上流修正）

- `Options#parse` と `Flag#prefix?` に `=` 分割を入れれば全コマンドで解決する。
- 欠点: 上流の反応待ちでリリースを縛れない。当面は案 A/B との併用が必要。

### 併せて検討したい派生課題

- **`--log` 解釈の一本化**: ③ `Common.current_log_level` が ARGV を直接読む構造は、正規化後のトークンと二重管理になっている。共通化のついでに「正規化済みトークンから 1 回だけ決める」形へ寄せられないか。
- **`--log` のキー名統一**: `new_command.rb` の `:log` を `:log_level` へ揃えるか（`vs new` 側の参照箇所の確認が必要）。
- **オプションを位置引数より前に置けない件（§3.3）**: 正規化器は「どのオプションが値を取るか」を知っているので、**オプション群を末尾へ寄せる**処理を足せば `vs build --theme=blue x.md` も通せる。従来エラーだった入力が通るようになるだけで後方互換は壊れない。ただし全コマンドの挙動変更になるため、案 A の共通化と同時に判断するのが安全。

## 8. 2026-07-21 に実施済みの変更（参考）

`vs build` のみ、利用者報告への即応として次を実施した（本報告の課題は未解決のまま残る）。

- `normalize_log_option_tokens` → `normalize_value_option_tokens` へ改名し、`VALUE_OPTIONS = { '--log' => 'info', '--theme' => nil }` の表で一般化
- `--theme=blue` / `--theme=#e91e63` に対応（`--theme=` は空値として 🔴 無効な色名＋候補提示へ）
- §4.2 のトークン脱落バグを修正（対象外トークンを必ず順序どおり素通しする実装へ）
- テスト 5 件を `test/vivlio_starter/cli/samovar/build_command_test.rb` に追加

## 9. 再現・確認用スニペット

```bash
# コマンドを実行せず、引数解析だけを確認する（vs new が実際にディレクトリを作らないよう
# コマンドクラスを直接 new する）
ruby -Ilib -e '
require "vivlio_starter/cli/startup"
S = VivlioStarter::CLI::SamovarCommands
[[S::BuildCommand, %w[x.md --theme=blue], :theme],
 [S::NewCommand, %w[mybook --log=debug], :log],
 [S::PdfPagesCommand, %w[a.pdf --dpi=200], :dpi]].each do |klass, argv, key|
  puts "#{argv.join(" ")} -> #{klass.new(argv.dup).options[key].inspect}"
rescue StandardError => e
  puts "#{argv.join(" ")} -> 🔴 #{e.message}"
end'

# preflight のトークン脱落（verify=true なら脱落＝バグ残存）
ruby -Ilib -e '
require "vivlio_starter/cli/startup"
c = VivlioStarter::CLI::SamovarCommands::PreflightCommand.new(%w[--log --no-verify])
puts "verify=#{c.options[:verify].inspect}"'
```
