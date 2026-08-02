# 報告書：デッドコード候補（リリース前の整理用）

> 作成日: 2026-08-03
> ステータス: **調査のみ。削除は未着手**
> 起票: `Common.validate_book_config!` が本番経路から呼ばれていないことが
> `index-term-selection-spec.md` Phase 5 の実装中に判明し、他にも同種があるはずとの判断
> 対象: `lib/vivlio_starter/**/*.rb`（`lib/project_scaffold/` は除外）

---

## 0. この報告書の読み方

**ここに挙げたものは「削除してよい」ではなく「調べる価値がある」候補である。**
機械的な走査は名前の照合しかできず、次は原理的に追えない。

- 動的呼び出し（`send` / `define_method` / Samovar のコマンドルーティング）
- 同名メソッドが複数クラスにあるケース（名前だけでは区別が付かない）
- Ruby 側から呼ばれるフック（`included` / `prepended` / `method_missing`）

したがって **1 件ずつ確認してから消すこと**。走査スクリプトは
`docs/specs` には置かず、必要なら本書 §5 の要領で書き直す。

---

## 1. 要旨

| 分類 | 件数 | 性格 |
|---|---|---|
| **§2 実害あり**（動いていないのに実装がある） | 2 | 最優先。消すか、繋ぐかを決める |
| **§3 テストからのみ参照** | 17 | 実装は誰も使っていない。テストごと消すか、使うか |
| **§4 走査の誤検出** | 6 | Ruby のフック。**消してはいけない** |

走査結果は全 2,803 メソッド中 23 件。母数に対して少ないのは、
この規模のコードベースとしては健全な水準である。

---

## 2. 実害のあるもの（最優先）

### 2.1 `Common.validate_book_config!` — 著者に届かない検証

`common.rb:986`。`book.main_title` / `book.author` / `project.name` の未設定を
検出して警告する実装だが、**本番経路では一度も実行されない**。

```ruby
def reload_configuration!(silent: false)
  ...
  validate_book_config!(raw_config) unless silent   # ← silent のときは走らない
```

`reload_configuration!` の本番呼び出しは **module load の 1 箇所だけ**で、
そこは `silent: true` である（`common.rb:1005`）。非 silent の呼び出しは
テスト（`cover_test.rb` / `create_commands_test.rb`）にしかない。

**単なるデッドコードより悪い。** 「実装済みの著者向け検証」に見えて、
実際には誰にも届いていない。`vs build` でタイトルが空欄の PDF ができても
警告は出ない。

**判断の分かれ道**:

| 案 | 内容 |
|---|---|
| **A. 繋ぐ** | `Common.ensure_configured!` から呼ぶ。廃止キーの案内（`warn_retired_config_keys`）と同じ関門で、全コマンドが通る。**本来やりたかったのはこちらのはず** |
| B. 消す | 検証自体が不要だと判断するなら、メソッドとテスト（`common_validate_book_config_test.rb`）ごと削除 |

A なら 1 行で済む。実装・テストとも既にあるので、**費用対効果は A が明らかに高い**。

> 参考: 同じ「著者の book.yml を検査して知らせる」機構は
> `config-extension-guidelines.md` §4 に整理済み（`ensure_configured!` が関門）。

### 2.2 `HierarchicalIndex` — 機能の 8 割が未接続

`lib/vivlio_starter/cli/index/hierarchical_index.rb`（115 行）。
本番から使われているのは `add_entry` と `link_count` だけで、
それも**ログ 1 行のため**である。

```ruby
# unified_page_builder.rb:138-142
@hierarchical_index.add_entry(term, link)
Common.log_info("索引データを読み込み: … #{@hierarchical_index.link_count} 件のリンク")
```

未接続のまま残っている機能:

| メソッド | 意図された機能 |
|---|---|
| `deduplicate_same_page!` | 同一ページの重複排除（実際は `BacklinkDeduplicator` が PDF ページマップで行っている） |
| `calculate_page_ranges` | 連続ページの範囲表記「12-15」 |
| `get_hierarchy` / `root_terms` / `children_of` | 階層化索引（親子項目） |
| `entry_count` | — |

ファイル冒頭に「Phase 3 機能」とあるが、その Phase 3 は来ていない。

**判断の分かれ道**: `calculate_page_ranges` と階層化索引は
`index-main-reference-spec.md` §R8 / `PLANNED.md` に**将来案として生きている**。
消すと再実装になる。

| 案 | 内容 |
|---|---|
| **A. 残して明示する** | クラス冒頭に「未接続。使うのは `index-main-reference-spec.md` R8」と書き、`log_info` の依存も外す |
| B. 消す | 将来案を諦める、または実装時に書き直す前提で削除（`calculate_page_ranges` は 20 行程度なので再実装は軽い） |

**A を推す。** 実装済みで動くコードを消して再実装するのは損である。
ただし現状は「使われているように見えて実は使われていない」ので、
**その旨をコードに書く**のが最小の手当てになる。

---

## 3. テストからのみ参照されているもの（17 件）

実装は本番から呼ばれず、テストだけが呼んでいる。
**テストがあるぶん「動くことは保証されているが、誰も使っていない」状態**である。

### 3.1 索引ドメイン（11 件・最も多い）

| メソッド | 場所 | 備考 |
|---|---|---|
| `deduplicate_same_page!` | `hierarchical_index.rb:40` | §2.2 |
| `calculate_page_ranges` | `hierarchical_index.rb:53` | §2.2 |
| `get_hierarchy` | `hierarchical_index.rb:77` | §2.2 |
| `root_terms` | `hierarchical_index.rb:82` | §2.2 |
| `children_of` | `hierarchical_index.rb:88` | §2.2 |
| `entry_count` | `hierarchical_index.rb:93` | §2.2 |
| `export_candidates!` | `index_candidate_extractor.rb:148` | `config/index_candidates.yml` を書き出す。**この YAML を読む実装が無い**（レビューは `_index_glossary_review.md` に一本化された）。有力な削除候補 |
| `cleanup!` | `review_markdown_generator.rb:258` | レビューファイルの削除。`vs build` の clean が担っているなら不要 |
| `filter_by_threshold` | `scoring_engine.rb:87` | **2026-08-03 に採否を閾値から帯へ移したので用途を失った**（`index-term-selection-spec.md` Phase 5）。削除候補 |
| `find_term` | `unified_terms_manager.rb:80` | |
| `update_definition!` | `unified_terms_manager.rb:192` | |

索引ドメインに偏っているのは、この領域が**設計を何度も入れ替えてきた**ためである
（候補 YAML → レビュー md、閾値 → 帯）。旧設計の部品が残っている。

### 3.2 その他（6 件）

| メソッド | 場所 |
|---|---|
| `unsafe?` | `image_filename_sanitizer.rb:39` |
| `all_integers?` | `chapter_config.rb:77` |
| `configured_chapters` | `chapter_config.rb:92` |
| `embed_cover?` | `epub_builder.rb:515` |
| `armed?` | `rotate_table_images.rb:79` |
| `clear!` | `metrics/cache.rb:90` |

これらは**述語メソッド・小さなアクセサ**が多く、消す利得は小さい。
「テストのためだけに公開している」だけなら、private 化で足りることもある。

---

## 4. 走査の誤検出（消してはいけない）

| メソッド | 場所 | 理由 |
|---|---|---|
| `included` | `doctor.rb:147` / `post_process.rb:74` / `prism_lines.rb:43` / `resize.rb:91` | `Module#included` フック。Ruby が呼ぶ |
| `prepended` | `option_token_normalizer.rb:45` | `Module#prepended` フック。同上 |
| `ensure_chapter_html_up_to_date!` | `section_builder.rb:95` | 要確認。名前から察するに呼ばれるべき処理で、**呼ばれていないなら §2 側の問題** |

`ensure_chapter_html_up_to_date!` だけは性格が違う。
**「呼び忘れ」なら実害がある**ので、優先して確認すること。

---

## 5. 走査の再現方法

```ruby
# lib/ 内で定義され、どこからも参照されないメソッドを列挙する
LIB = Dir.glob('lib/vivlio_starter/**/*.rb').reject { it.include?('/project_scaffold/') }
lib_all = LIB.map { File.read(it, encoding: 'utf-8') }.join("\n")

# 末尾が ! / ? のメソッド名は \b が使えないので境界を組み立てる
def boundary(name) = name.match?(/\w\z/) ? '(?![\w!?])' : ''
def ident_regex(name) = /(?<!\w)#{Regexp.escape(name)}#{boundary(name)}/
def def_regex(name)   = /^\s*def (?:self\.)?#{Regexp.escape(name)}#{boundary(name)}/

# 参照数 = 識別子の出現 − 定義行の出現。0 以下なら候補
```

**踏んだ落とし穴を 2 つ記録しておく**（同じ走査を書き直すときのために）:

1. **`\b` は `!` / `?` の後ろで効かない。** `ensure_configured!` を
   `/\bensure_configured!\b/` で探すと 1 件も当たらず、全メソッドが
   「未使用」に見える
2. **定義行を数える正規表現にも末尾境界が要る。** `def execute` で数えると
   `def execute_clean` `def execute_pdf` まで定義として数え、
   実際は呼ばれている `execute` が「未使用」に化ける

この 2 つを踏むと候補が 322 件・619 件と膨れ上がり、使い物にならない。
正しく組めば 23 件に収まる。

---

## 6. 進め方の提案

1. **§2.1 `validate_book_config!` を先に決める**（繋ぐ／消す）。1 行で終わり、
   著者への影響が最も大きい
2. **§4 の `ensure_chapter_html_up_to_date!` を確認する**。呼び忘れなら不具合
3. **§3.1 の索引ドメイン 11 件**をまとめて整理する。旧設計の残骸なので、
   `index-term-selection-spec.md` / `index-main-reference-spec.md` の実装が
   一段落してから触るのが安全
4. §3.2 は急がない。private 化で足りるものが多い

**削除するときは 1 件ずつコミットを分ける。** まとめて消すと、
何かが壊れたときにどれが原因か分からなくなる。
