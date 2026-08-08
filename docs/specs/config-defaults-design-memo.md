# 既定値と廃止値の持ち方 — 検討メモ（叩き台）

対象: `lib/vivlio_starter/cli/common.rb` の設定層を整理する開発者
記録日: 2026-08-08 / 状態: **未決・叩き台** ／ 次: 方針を決めてから実装

---

## 0. なぜ整理するのか

きっかけは「キーを 1 つ廃止するだけで触る場所が増え続けている」ことだった。
2026-08-08 に 9 キーを廃止した際、`default_config_schema` から消し、
`RETIRED_CONFIG_KEYS` へ登録し、読み出し側のフォールバックを直し、
`book.yml` を編集し、`copy_to_scaffold.rb` を回す——という手順になった。

個々は正しく動く。だが同じ「既定値」という概念が 4 通りの持ち方で散っており、
キーの状態も暗黙に 4 つある。**この散らばり自体が、後述の実害を生んでいる。**

---

## 1. 現状の棚卸し（実測）

### 1.1 既定値を持つ場所が 4 系統

| 場所 | 持ち方 | 例 |
| :--- | :--- | :--- |
| `default_config_schema` | キーを列挙。ほとんどが `nil` | `lint: { disabled_rules: nil, … }` |
| `default_*` メソッド群 | 実値を持つ | `default_vivliostyle` の `quiet: true` |
| ドメイン側の定数 | コードのそばに置く | `Analyzer::DEFAULT_MATTR_WINDOW` |
| 読み出し地点のリテラル | 読むたびに書く | `@config[:context_width] \|\| 40` |

### 1.2 スキーマの 87% は既定値を持っていない

```
スキーマの葉キー総数: 112
  nil（目録のみ）    :  97   ← 86.6%
  実値あり（既定値） :  15
```

**`default_config_schema` は「既定値スキーマ」を名乗っているが、実体はキーの目録である。**
`nil` の 97 件が果たしている唯一の役割は、`CONFIG.lint.disabled_rules` のような
ドット記法を `NoMethodError` にしないこと。実際の既定値は読み出し地点か
ドメイン定数の側にある。

実値を持つ 15 件も `directories.*`（8 件）・`cache.*`（2 件）・`vivliostyle.*`（2 件）に
偏っており、**「パスとツール設定だけがスキーマに実値を持つ」**という不揃いな状態にある。

### 1.3 キーの状態が暗黙に 4 つ

```
スキーマにある + 実値あり     → 既定値として効く
スキーマにある + nil          → 目録に載っているだけ（既定値は別の場所）
スキーマにない + 廃止表にある → 警告して無視
スキーマにない + 廃止表にない → 自由拡張として素通し
```

どれも明示的に宣言されておらず、**2 つの表の差分として読み取るしかない。**

### 1.4 宣言場所が 3 箇所

| 表 | 役割 |
| :--- | :--- |
| `default_config_schema` | 現役キーの目録＋一部の既定値 |
| `RETIRED_CONFIG_KEYS` | 廃止キーと移行先の案内 |
| `RESERVED_CONFIG_KEYS` | `Data` のメソッド名と衝突する予約語 |

---

## 2. 現に起きている実害

### 2.1 同じ既定値が複数箇所にあり、食い違っている

**`glossary.max_definition_length` は 2 つの答えを持つ。**

| 場所 | 値 |
| :--- | ---: |
| `config/book.yml` | **500** |
| `unified_index_manager.rb:328` の `\|\| 200` | **200** |
| `default_config_schema` | `nil` |

著者がこのキーを消すと 200 になるが、`book.yml` は 500 と言っている。
どちらが「既定値」なのか、コードにも文書にも答えがない。

**`readability` の既定値は 3 箇所にある。**

```ruby
config/book.yml                   readability: { standard: 40, easy: 60 }
config_loader.rb:86               DEFAULT_READABILITY = { easy: 60, standard: 40 }
analyzer.rb:212                   config[:readability] || { easy: 60, standard: 40 }
```

今は一致しているが、**一致を保つ仕組みが無い。**

**`context_width || 40` は 4 箇所に散っている**
（`unified_index_manager.rb` ×2・`index_candidate_extractor.rb`・`review_markdown_generator.rb`）。

### 2.2 「記述の有無」と「著者が選んだか」を区別できない

`authored_key?` が答えるのは「`book.yml` にそのキーが書かれているか」だけである。
`book.yml` には現役キーを全部載せる方針（著者の発見可能性のため）なので、
**現役キーの `authored_key?` は全プロジェクトで常に真**になり、情報量がゼロになる。

実害: `vs rename` が改番のたびに「`metrics.exclude_chapters` を見直してください」と
出していた（2026-08-08 に撤去・コミット `ee615cea`）。詳細は
`config-retirement-guidelines.md` §3。

### 2.3 既定値との合成規則が場所ごとに違う

`metrics/config_loader.rb#resolve_preset` は全か無かで判定するため、
プリセットに `section:` だけ書いて `chapter:` を書かないと**著者の指定が警告なく捨てられる**。

```ruby
custom = metrics_config[name.to_sym]
return custom if custom.is_a?(Hash) && custom[:chapter]   # chapter が無いと丸ごと捨てる
DEFAULT_PRESETS[name.to_sym] || DEFAULT_PRESETS[:standard]
```

`Common.deep_merge_config` は同じ問題を正しく解いている（部分指定でも兄弟キーが残る）のに、
そちらを使っていない。**合成規則が 1 つに決まっていないため、各所で再実装される。**

---

## 3. 制約（動かせない前提）

整理案はこの 3 つを満たす必要がある。

1. **`book.yml` に現役キーを全部載せる。** 著者がキーを知る手段は他に無い
   （2026-08-07 決定・`config-key-criteria-guidelines.md` §1）
2. **スキーマ外のキーは素通しする。** 自由拡張として意図した仕様
   （`test_should_pass_through_unknown_sections_and_keys`）
3. **`book.yml` はコメントを保ったまま扱う。** `copy_to_scaffold.rb` も `doctor` の
   `config_salvager` も `gsub` のテキスト置換で、YAML の読み書きを経由しない

---

## 4. 案（叩き台）

### 案 A: 宣言を 1 つの表に寄せる

キーごとに「名前・既定値・状態・移行先」を 1 行で宣言し、
`default_config_schema` / `RETIRED_CONFIG_KEYS` はそこから導出する。

```ruby
CONFIG_KEYS = {
  %i[glossary max_definition_length] => { default: 500 },
  %i[index_glossary context_width]   => { default: 40 },
  %i[metrics mattr_window]           => { retired: '窓幅は算出方法そのもので…' },
  %i[lint disabled_rules]            => { default: nil },
}.freeze
```

- **利点**: 既定値の所在が 1 箇所になる。§2.1 の食い違いが構造的に起きなくなる。
  キーの状態が `default:` / `retired:` として明示される
- **欠点**: 表が大きくなる（現状 112 葉キー＋廃止 12 件）。ドメイン側の定数
  （`DEFAULT_MATTR_WINDOW` 等）をどう扱うか——設定でないものまで表に載せるのは筋が悪い
- **未決**: 読み出し側は `CONFIG.x.y` のままでよいか。表から既定値が来るなら
  `|| 40` は全部消える

### 案 B: スキーマは目録に徹し、既定値はドメインに置く

`default_config_schema` の役割を「ドット記法を保証する目録」だと認め、`nil` 並びを正とする。
既定値は各ドメインの `DEFAULT_*` 定数に一本化し、読み出し地点のリテラルを禁じる。

- **利点**: 現状からの変更が小さい。既定値がそれを使うコードの隣にあり、読みやすい
- **欠点**: 「このキーの既定値は？」に答えるには実装を追う必要がある。
  `book.yml` のコメントに書いた既定値との一致は、人間が保つしかない（§2.1 が残る）
- **未決**: `default_*` メソッド群（実値 15 件）はどちらへ寄せるか

### 案 C: `book.yml` を既定値の正典にする

同梱 `book.yml` に書かれた値を既定値として読み、コードは既定値を持たない。

- **利点**: 著者が見るファイルと実装が必ず一致する。§2.1 が原理的に起きない
- **欠点**: gem 同梱の `book.yml` を実行時に読む必要があり、プロジェクト外
  （`vs new` 前・直接ビルド）で成立しない。§3-3 の「テキスト置換で扱う」とも相性が悪い
- **判定**: おそらく不可。だが**「著者が見る値と実装の値が食い違ってよいのか」**という
  問いは案 A・B にも残るので、記録しておく

---

## 5. 決めるべきこと

1. **`default_config_schema` は何なのか。** 既定値表か、キーの目録か。
   87% が `nil` である以上、名前と実体が合っていない
2. **既定値の単一の所在をどこにするか。** 案 A（1 つの表）か案 B（ドメイン定数）か
3. **「著者が選んだか」に答える必要はあるか。** あるなら記述の有無とは別の機構が要る。
   無いなら `authored_keys` は廃止キー検出の内部実装に降格してよい
4. **既定値との合成規則を 1 つに決めるか。** 決めるなら `deep_merge_config` に寄せ、
   `resolve_preset` の再実装をやめる

---

## 6. これが決まると動かせるもの

| 待っているもの | 依存の中身 |
| :--- | :--- |
| `resolve_preset` の部分上書きバグ | *何に対して*マージするかが決まらない（§2.3） |
| `contents/61-developer.md` の全面書き直し | 設定層の説明が書けない |
| `config-retirement-guidelines.md` §3・§4 | 現状の説明として書いてあり、書き直しになる |

---

## 7. 関連

- `config-key-criteria-guidelines.md` — そのキーは設定であるべきか（判断軸 5 本）
- `config-extension-guidelines.md` — キーの足し方（`CONFIG` アクセスの型）
- `config-retirement-guidelines.md` — キーのやめ方（`RETIRED_CONFIG_KEYS`）
- `config-access-unification-spec.md`（archives）— 現在の `CONFIG` を作った仕様
