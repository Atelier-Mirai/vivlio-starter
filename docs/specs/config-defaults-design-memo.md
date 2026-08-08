# 既定値と廃止値の持ち方 — 検討メモ

対象: `lib/vivlio_starter/cli/common.rb` の設定層を整理する開発者
記録日: 2026-08-08 / 状態: **設計は確定・未実装** ／ 次: §5 の残る未決 1 点を実装時に決めて着手

---

## 0. なぜ整理するのか

きっかけは「キーを 1 つ廃止するだけで触る場所が増え続けている」ことだった。
2026-08-08 に 9 キーを廃止した際、`default_config_schema` から消し、
`RETIRED_CONFIG_KEYS` へ登録し、読み出し側のフォールバックを直し、
`book.yml` を編集し、`copy_to_scaffold.rb` を回す——という手順になった。

個々は正しく動く。だが同じ「既定値」という概念が 4 通りの持ち方で散っており、
**そのせいで「book.yml に書いてあるのに違う値で動く」余地が実際に 6 件ある**（§2.1）。

---

## 1. 現状の棚卸し（実測）

### 1.1 既定値を持つ場所が 4 系統

| 場所 | 持ち方 | 例 |
| :--- | :--- | :--- |
| `default_config_schema` | キーを列挙。ほとんどが `nil` | `lint: { disabled_rules: nil, … }` |
| `default_*` メソッド群 | 実値を持つ | `default_vivliostyle` の `quiet: true` |
| ドメイン側の定数 | コードのそばに置く | `BookSettingsCss::DEFAULT_HEADING_CHARS` |
| 読み出し地点のリテラル | 読むたびに書く | `@config[:context_width] \|\| 40` |

### 1.2 スキーマの 87% は既定値を持っていない

```
default_config_schema の葉キー総数: 112
  nil（目録のみ）    :  97   ← 86.6%
  実値あり（既定値） :  15
```

**「既定値スキーマ」を名乗っているが、実体はキーの目録である。** `nil` の 97 件が
果たす唯一の役割は、`CONFIG.lint.disabled_rules` のようなドット記法を
`NoMethodError` にしないこと。実際の既定値は読み出し地点かドメイン定数の側にある。

実値を持つ 15 件も `directories.*`（8）・`cache.*`（2）・`vivliostyle.*`（2）に偏っており、
**「パスとツール設定だけがスキーマに実値を持つ」**という不揃いな状態にある。

### 1.3 ドメイン定数 27 件のうち 14 件は設定の裏打ち

```
DEFAULT_* 定数の総数        27 件（16 ファイル）
  book.yml のキーを裏打ち   14 件  ← 二重管理。表へ移すべきもの
  純粋な実装定数            13 件  ← 設定ではない。ドメインに残すべきもの
```

**残す 13 件**: `DEFAULT_MATTR_WINDOW`（手法パラメータ）、`IndexLibrary::DEFAULT_PATH`、
`MermaidRenderer::DEFAULT_THEME`、`DEFAULT_WAIFU2X_BIN`、`DEFAULT_LOG_LEVEL`、
`DEFAULT_PROGRESS_VERB`、`TalkRegistry::DEFAULT_DISPLAY`、`DEFAULT_PAGE_WIDTH_MM/HEIGHT_MM`、
`New::DEFAULT_ANSWERS` ほか。

**「ドメイン定数を表に載せるのは筋が悪い」問題は、設定を裏打ちしているか否かで自然に切れる。**
設定でない 13 件は表に載らない。

### 1.4 宣言する表が 4 つに分かれている

| 表 | 役割 |
| :--- | :--- |
| `default_config_schema` | 現役キーの目録＋一部の既定値（§1.2） |
| `RETIRED_CONFIG_KEYS` | 廃止キーと移行先の案内 |
| `REQUIRED_BOOK_KEYS` | 著者が埋めるキーと、警告に出す記入例 |
| `RESERVED_CONFIG_KEYS` | `Data` のメソッド名と衝突する予約語 |

`RESERVED_CONFIG_KEYS` だけは性質が違う（`Data` の実装制約であってキーの状態ではない）ので、
統合の対象は前 3 つ。

### 1.5 キーの状態が暗黙に 4 つ

```
スキーマにある + 実値あり     → 既定値として効く
スキーマにある + nil          → 目録に載っているだけ（既定値は別の場所）
スキーマにない + 廃止表にある → 警告して無視
スキーマにない + 廃止表にない → 自由拡張として素通し
```

どれも明示的に宣言されておらず、**2 つの表の差分として読み取るしかない。**

---

## 2. 現に起きている実害

### 2.1 同じ既定値が食い違っている（6 件）

| キー | `book.yml` | コード | 差が出るとき |
| :--- | ---: | ---: | :--- |
| `theme.frontispiece.heading_chars` | 10 | 8 | `BookSettingsCss::DEFAULT_HEADING_CHARS` |
| `theme.frontispiece.lead_chars` | 24 | 20 | `BookSettingsCss::DEFAULT_LEAD_CHARS` |
| 同上（EPUB 合成側） | 10 / 24 | 8 / 20 | `HeadingImageComposer::DEFAULT_METRICS` |
| `page.chapter_pagebreak` | any | recto | スキーマと `DEFAULT_CHAPTER_PAGEBREAK` の**両方**が recto |
| `glossary.max_definition_length` | 500 | 200 | `unified_index_manager.rb:328` の `\|\| 200` |

**今は `book.yml` が勝つので表には出ない。** 著者がその行を消した瞬間だけ、
誰も宣言していない別の値で動きはじめる。`heading_chars` は扉絵の見た目が変わるキーなので、
「10 にしたはずが 8 で組まれた」と感じる場面が実際にありうる。

`page.chapter_pagebreak` は 3 箇所に 2 つの値がある（`book.yml` = `any` /
スキーマ = `recto` / 定数 = `recto`）。

### 2.2 同じ既定値が同義のまま複数箇所にある

```
readability      book.yml / DEFAULT_READABILITY / analyzer.rb:212 のインラインリテラル   3 箇所
context_width    unified_index_manager.rb ×2 ・ index_candidate_extractor ・ review_markdown_generator   4 箇所
metrics プリセット  book.yml に 5 プリセット全文 ／ DEFAULT_PRESETS に同じもの   2 箇所
```

今は一致しているが、**一致を保つ仕組みが無い。** §2.1 は同じ構造が既に破れた例である。

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

### 2.4 「記述の有無」と「著者が選んだか」を区別できない

`authored_key?` が答えるのは「`book.yml` にそのキーが書かれているか」だけ。
`book.yml` には現役キーを全部載せる方針なので、**現役キーでは常に真**になり情報量がゼロ。

実害: `vs rename` が改番のたびに無意味な警告を出していた（2026-08-08 撤去・`ee615cea`）。
詳細は `config-retirement-guidelines.md` §3。

---

## 3. 制約（動かせない前提）

1. **`book.yml` に現役キーを全部載せる。** 著者がキーを知る手段は他に無い
   （2026-08-07 決定・`config-key-criteria-guidelines.md` §1）
2. **スキーマ外のキーは素通しする。** 自由拡張として意図した仕様
   （`test_should_pass_through_unknown_sections_and_keys`）
3. **`book.yml` はコメントを保ったまま扱う。** `copy_to_scaffold.rb` も `doctor` の
   `config_salvager` も `gsub` のテキスト置換で、YAML の読み書きを経由しない

---

## 4. 方針: 案 A — 宣言を 1 つの表に寄せる

キーごとに「名前・既定値・状態・移行先」を 1 行で宣言し、
`default_config_schema` と `RETIRED_CONFIG_KEYS` はそこから導出する。

```ruby
# 値は Data で持つ（§4.3）
Spec = Data.define(:default, :retired, :authored) do
  def initialize(default: nil, retired: nil, authored: nil) = super
  def retired? = !retired.nil?
  def authored? = !authored.nil?
end

CONFIG_KEYS = {
  # 現役キー: 既定値を持つ
  %i[glossary max_definition_length]   => Spec[default: 500],
  %i[index_glossary context_width]     => Spec[default: 40],
  %i[theme frontispiece heading_chars] => Spec[default: 10],
  %i[page chapter_pagebreak]           => Spec[default: 'any'],

  # 著者が埋めるキー: システムの既定値を持たない。値は警告に出す記入例（§4.2）
  %i[book main_title]                  => Spec[authored: '本のタイトル'],

  # 廃止キー: 移行先を案内して無視する
  %i[metrics mattr_window]             => Spec[retired: '語彙多様度を測る窓幅は算出方法そのもので…'],
}.freeze
```

### 4.1 これで解けること

| 現状の問題 | 解け方 |
| :--- | :--- |
| §2.1 の食い違い 6 件 | 既定値の宣言が 1 箇所になり、構造的に起きなくなる |
| §2.2 の重複 | 読み出し地点の `\|\| 40` が全部消える |
| §1.4 の 4 つの表 | 3 つが 1 つになる（`RESERVED_CONFIG_KEYS` は性質が違うので残す） |
| §1.5 の暗黙の 4 状態 | `default:` / `authored:` / `retired:` として明示される |
| §1.2 の名前と実体の乖離 | 目録と既定値表が同一物になる |

**表と `book.yml` の一致はテストで担保する。** scaffold の `book.yml` に書かれた値と
`CONFIG_KEYS` の `default:` が一致することを検査すれば、§2.1 は再発しない。
既存の `book_yml_consumption_test.rb`（全キーが lib から参照されているかの検査）と対になる。

### 4.2 「著者が埋めるキー」は `REQUIRED_BOOK_KEYS` を吸収する

`book.main_title` にシステムの既定値は無い。scaffold は `{{MAIN_TITLE}}` という
プレースホルダを置き、`vs new` が対話で埋める。

`New::DEFAULT_ANSWERS[:main_title] = '新しい本'` はあるが、これは**対話プロンプトの
既定**（Enter だけ押したときの値）であってシステムの既定値ではない。`vs new` の
関心事なのでドメイン側に残す（§1.3 の「残す 13 件」に含まれる）。

**この状態はすでに実装されており、4 つ目の表に置かれている。**

```ruby
# common.rb:1003
REQUIRED_BOOK_KEYS = {
  %i[book main_title] => '本のタイトル',
  %i[book author]     => '著者名',
  %i[project name]    => 'mybook'
}.freeze
```

値は未設定時の警告に出す記入例で、そのまま貼れる形で表示される。

```
🟡 config/book.yml の推奨キーが未設定です: book.main_title, book.author
       → config/book.yml に次のように書いてください。
         book:
           main_title: 本のタイトル
```

したがって `authored:` の値は真偽値ではなく**記入例の文字列**にする。
`CONFIG_KEYS` へ吸収すれば宣言場所が 1 つ減り、情報も増えない。

```ruby
%i[book main_title] => Spec[authored: '本のタイトル'],
```

**判定方法はこの実装を踏襲する。**

```ruby
REQUIRED_BOOK_KEYS.keys.select { blank?(cfg.dig(*it)) }
```

`authored_key?`（書かれているか）ではなく **`blank?`（値が空か）**で見ている。
これが正しいやり方で、§4.5 の根拠にもなっている。

### 4.3 表の値は Data で持つ（決定）

ハッシュリテラルではなく `Data.define` を使う。**打ち間違いが即座に落ちるため。**

```ruby
Spec[defualt: 500]   # → ArgumentError: unknown keyword: :defualt
{ defualt: 500 }     # → 静かに通り、既定値を持たないキーとして振る舞う
```

130 行の表で 1 箇所やらかしたときに、後者は見つけようがない。
`Data.define` は `::[]` を備えるのでハッシュとほぼ同じ軽さで書け、凍結も自動、
`retired?` `authored?` のような述語も持てる。

### 4.4 合成規則は `deep_merge_config` に一本化する（決定）

既定値と著者の指定を合成する規則を 1 つに決め、各コマンドが独自に実装するのをやめる。
`resolve_preset` の再実装（§2.3）を撤去すれば、プリセットの部分上書きバグが同時に解ける。

### 4.5 「著者が選んだか」には答えない（決定）

「その値は著者が考えて選んだのか、scaffold の既定値のまま触っていないのか」には答えない。

**原理的に答えられない。** `book.yml` に全キーを載せる原則の下では、誰の `book.yml` にも
値が書いてあり、「触っていない」の痕跡が残らない。

**答えられなくて困らない。** 理由は 2 つ。

- **既存プロジェクトは既定値の変更に影響されない。** 全員が明示値を持つので、既定値を
  変えても既存プロジェクトの出力は変わらない。scaffold が変わり、新規プロジェクトだけ
  新しい値になる。予測可能で安全な挙動である
- **「効かない組み合わせ」の警告は値で書ける。** §4.2 の `blank?` がその実例。
  「X を設定しているのに Y が無効で効かない」と言いたければ両方の**値**を見ればよい

したがって `authored_keys` / `authored_key?` は**廃止キー検出の内部実装に降格**し、
公開 API から外す。`config-retirement-guidelines.md` §3 で引いた線
（使えるのは廃止キーだけ）が実装にも反映される。

### 4.6 表の大きさ

現状 112 葉キー＋廃止 12 件で、およそ 130 行。5 万行規模のコードベースでは許容範囲
（ユーザー判断・2026-08-08）。ただし `common.rb` は既に 1,200 行あるので、
**別ファイル（`lib/vivlio_starter/cli/config_keys.rb`）へ切り出す**のが素直。

---

## 5. 決定と残る未決

### 決定済み（2026-08-08）

| 論点 | 決定 | 節 |
| :--- | :--- | :--- |
| 方針 | 案 A（宣言を 1 つの表に寄せる） | §4 |
| 表の値の形 | `Data.define`。打ち間違いが即座に落ちるため | §4.3 |
| 著者が埋めるキー | `REQUIRED_BOOK_KEYS` を吸収。`authored:` の値は記入例の文字列 | §4.2 |
| 合成規則 | `deep_merge_config` に一本化。`resolve_preset` の再実装を撤去 | §4.4 |
| 「著者が選んだか」 | 答えない。`authored_keys` は廃止キー検出の内部実装へ降格 | §4.5 |
| 食い違い 6 件の直し方 | `book.yml` を正とし、表の実装後にまとめて直す | §7 |
| 表の置き場所 | `lib/vivlio_starter/cli/config_keys.rb` へ切り出す | §4.6 |

### 残る未決

**`authored:` キーの `CONFIG` 上の表現。** `book.main_title` が未設定のとき、
`CONFIG.book.main_title` は `nil` を返せばよいか。

- 現状は `wrap_config` が `book.yml` の値をそのまま載せるので、空文字列か `nil` になる
- 読み出し側は `blank?` で判定しているため、どちらでも動く
- ただし表を導出元にすると「`default:` が無いキーの `CONFIG` 上の値は何か」を
  明示的に決める必要がある。`nil` で統一するのが素直だが、`''` を期待している
  読み出し側が無いかは実装時に確認する

---

## 6. 採らなかった案

### 案 B: スキーマは目録に徹し、既定値はドメインに置く

`nil` 並びを正と認め、既定値は各ドメインの `DEFAULT_*` 定数へ一本化する。

- 変更は小さいが、**§2.1 の食い違いが残る**。「このキーの既定値は？」に答えるには
  実装を追う必要があり、`book.yml` のコメントとの一致は人間が保つしかない
- 今回の 6 件は、まさにその「人間が保つ」が破れた結果である

### 案 C: `book.yml` を既定値の正典にする

同梱 `book.yml` を実行時に読み、コードは既定値を持たない。

- 著者が見るファイルと実装が必ず一致するが、gem 同梱ファイルを実行時に読む必要があり、
  プロジェクト外（`vs new` 前・直接ビルド）で成立しない。§3-3 とも相性が悪い
- ただし**「著者が見る値と実装の値が食い違ってよいのか」**という問いは案 A にも残る。
  案 A はこれを「表を正典とし、`book.yml` との一致をテストで担保する」形で解く

---

## 7. 移行の順序

§2.1 の食い違い 6 件は、**`CONFIG_KEYS` の実装後にまとめて直す**（ユーザー判断・2026-08-08）。

理由: いま定数だけ直しても、表を作るときに同じ箇所をもう一度触ることになる。
また 6 件はいずれも `book.yml` が勝つため**現時点で実害が出ていない**（著者がその行を
消したときだけ現れる潜在的な不整合である）。

正とするのは `book.yml` の値。`book.yml` に書かれていなかった場合に `CONFIG_KEYS` から
読めるようになって初めて、この修正は意味を持つ。

---

## 8. これが決まると動かせるもの

| 待っているもの | 依存の中身 |
| :--- | :--- |
| §2.1 の食い違い 6 件 | 表が無いと直しても二度手間。`book.yml` を正とする（§7） |
| `resolve_preset` の部分上書きバグ | *何に対して*マージするかが決まらない（§2.3） |
| `contents/61-developer.md` の全面書き直し | 設定層の説明が書けない |
| `config-retirement-guidelines.md` §3・§4 | 現状の説明として書いてあり、書き直しになる |

---

## 9. 関連

- `config-key-criteria-guidelines.md` — そのキーは設定であるべきか（判断軸 5 本）
- `config-extension-guidelines.md` — キーの足し方（`CONFIG` アクセスの型）
- `config-retirement-guidelines.md` — キーのやめ方（`RETIRED_CONFIG_KEYS`）
- `config-access-unification-spec.md`（archives）— 現在の `CONFIG` を作った仕様
