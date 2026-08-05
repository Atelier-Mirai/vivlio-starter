# 報告書：デッドコード候補（リリース前の整理用）

> 作成日: 2026-08-03
> ステータス: **処置済み（2026-08-06）。§7 に何をどうしたかを記す**
> 起票: `Common.validate_book_config!` が本番経路から呼ばれていないことが
> `index-term-selection-spec.md` Phase 5 の実装中に判明し、他にも同種があるはずとの判断
> 対象: `lib/vivlio_starter/**/*.rb`（`lib/project_scaffold/` は除外）

**§1〜§6 は調査時点（2026-08-03）の記録である。**現在のコードの姿は §7 を見ること。
§1〜§6 をそのまま残しているのは、走査の組み方（§5）と分類の判断（§2 の「単なる
デッドコードより悪い」等）が次の整理で再利用できるためで、**候補一覧としては
すでに古い**。

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

---

## 7. 処置の記録（2026-08-06）

`PLANNED.md` の「クロスリファレンスの死にコードを撤去する」と合わせて実施した。
`rake test` 2,388 件・RuboCop 428 ファイルとも通過。

### 7.1 撤去したもの

| 対象 | 場所 | 撤去の根拠 |
|---|---|---|
| `CrossReferenceProcessor.process_cross_references` と専用の私有ヘルパー 7 個 | `cross_reference_processor.rb` | 未定義の `generate_report` を呼ぶ到達不能コード。段取りは `process_cross_references_for_files` が持つ |
| `PreProcessCommands.process_cross_references` | `pre_process.rb` | 委譲先の `MarkdownTransformer.process_cross_references` が存在しない |
| `SectionBuilder.ensure_chapter_html_up_to_date!` | `section_builder.rb` | §4 の「呼び忘れか」は**否**。mtime 比較で再生成を省く設計は `book_yml_regeneration_spec.md` の「常に再生成する」に置き換わっている |
| `EpubBuilder.embed_cover?` | `epub_builder.rb` | 表紙埋め込みの判定は `Common.epub_embed?` / `Common.kindle_embed?`（フレーバ別）へ移った |
| `IndexCandidateExtractor#export_candidates!` と `BANNER` | `index_candidate_extractor.rb` | 書き出す `config/index_candidates.yml` を読む実装が無い。レビューは `_index_glossary_review.md` へ一本化 |
| `ReviewMarkdownGenerator#cleanup!` | `review_markdown_generator.rb` | レビューファイルの削除は `clean.rb` の `REVIEW_FILE_PATTERNS` が担う |
| `ScoringEngine#filter_by_threshold` | `scoring_engine.rb` | 採否を閾値から帯へ移して用途を失った（`index-term-selection-spec.md` Phase 5） |
| `ChapterConfig.configured_chapters` / `.all_integers?` | `chapter_config.rb` | catalog 読み出しは `CatalogLoader.load_existing_basenames` を各所が直接呼ぶ形になった |

いずれもテストを道連れに削除した。`samovar_smoke_test.rb` にあった
`configured_chapters` のスタブは、呼ばれないメソッドを差し替えていたので外した。

### 7.2 繋いだもの（§2.1・案 A）

`validate_book_config!` を `missing_book_config_keys`（検査）と
`warn_missing_book_config`（案内）に分け、**案内を `ensure_configured!` へ移した**——
廃止キー案内と同じ関門なので全コマンドが通る。検査自体は `reload_configuration!` で
毎回行い、結果だけを持ち越す。module load 時点で出すと、まだログレベルも決まっておらず、
`new` / `doctor` / `help` にも無関係な警告が付くためである。

警告は「直し方」を添える（`warning-messages-actionable` の方針）:

```
🟡 config/book.yml の推奨キーが未設定です: book.main_title, book.author, project.name
        → config/book.yml に次のように書いてください。
        book:
          main_title: 本のタイトル
          author: 著者名
        project:
          name: mybook
        このままでも動作しますが、PDF のタイトル・著者・出力ファイル名が空欄になります。
```

### 7.3 残したもの（明示だけ加えた・§2.2・案 A）

`HierarchicalIndex` は**本番から完全に切り離した上で残した**。
それまで唯一の本番参照だった `UnifiedPageBuilder#load_index_data!` の
`link_count`（ログ 1 行のため）は `@index_data` から直接数える形にしてある——
残しておくと「索引の重複排除はここ」という誤読を招くためで、**中途半端に
繋がっているより、切って所在を書くほうが読み違えない**。

クラス冒頭に「本番から未接続」「使い道は `index-main-reference-spec.md` §R8」
「同一ページの重複排除は実際には `BacklinkDeduplicator` が PDF のページマップで行う」
を明記した。

### 7.4 見送ったもの

- **§3.1 の `find_term`**: 報告書は「テストからのみ参照」に分類したが、
  **`unified_index_manager.rb:628` が本番で呼んでいる**。誤検出である
- **§3.2 の `unsafe?` / `armed?` / `clear!`、§3.1 の `update_definition!`**:
  小さな述語・ユーティリティで、消す利得が薄いので据え置き
- **`ChapterConfig` の章番号パーサ 2 個**: 走査では「使われている」に見えるが、
  実際に効いていたのは `HeadingProcessor` の同名コピーのほう。
  **同名メソッドの重複という §0 の限界そのもの**で、機械的な走査では拾えない。
  → §7.5 で片付けた

### 7.5 章番号パーサ——一本化して、廃止済みと分かって撤去した（2026-08-06）

**結論から言うと、寄せる前に「誰のためのパーサか」を確かめるべきだった。**
`ChapterConfig` と `HeadingProcessor` の二重実装を前者へ一本化したが、その直後に
**そもそも両方とも廃止済みのキーのための実装**だと判明し、丸ごと撤去した。
一本化の作業は無駄だった。同じ失敗を避けるための記録として残す。

**何が起きていたか。** 章構成のソースは 2025-11-26 のコミット `95f9f9c5`
「feat: catalog.yml ベースの章管理に移行しビルド系を更新」で
`book.yml: chapters` から `config/catalog.yml` へ移り、`book.yml` からキー自体も
消えている。ところが**読み手だけが残っていた**——`common.rb` のスキーマの
`chapters: nil` と、それを解釈する `HeadingProcessor.configured_main_chapter_tokens`
（6 形式）、その下請けの章番号パーサ 2 実装である。
`Common::CONFIG.chapters` は現行のどのプロジェクトでも常に nil で、
この分岐に入ることはない。

**なぜ走査で見つからなかったか。** §5 の走査は「メソッドが参照されているか」しか
見ない。`configured_main_chapter_tokens` は `main_chapter_order` と
`CrossReferenceProcessor` から**確かに呼ばれている**ので、走査上は生きて見える。
死んでいたのは呼び出しではなく**入力**（`CONFIG.chapters` が常に nil）だった。
**§0 の「原理的に追えない」に、もう 1 項目加えるべきである——設定キーの値が
常に既定値のままで、分岐に入らない実装。**

**気付く機会はあった。** `configured_main_chapter_tokens` にはテストが 1 件も
無かった。そのとき「無テストだから固定してから移そう」と進めたが、**無テスト
だったのは廃止済みだったから**である。「この規模の分岐に、なぜテストが無いのか」を
先に問うべきだった。

**撤去したもの**（連鎖）:

| 撤去 | 呼び出し元が消えた理由 |
|---|---|
| `common.rb` スキーマの `chapters: nil` | キーが `book.yml` に無い |
| `HeadingProcessor.configured_main_chapter_tokens` | 上を読む唯一の実装 |
| `tokens_from_chapter_numbers` / `all_integer_strings?` | 上の下請け |
| `ChapterConfig.parse_chapter_numbers_from_string` | 同上（一本化した先） |

`main_chapter_order` は「単章ビルドの override → ワークスペースの HTML から検出」の
2 段になり、`ChapterConfig` に残るのは `htmls_for_range` だけになった。

**実害もあった。** 移行前に作ったプロジェクトの `book.yml` に `chapters:` が
残っていれば、正典であるはずの `catalog.yml` を差し置いて章順を書き換える。
ベータ公開（2026-04-26）より前の廃止なので実在するプロジェクトは無く、
廃止キーの案内（`RETIRED_CONFIG_KEYS`）は置いていない。

**綴りが同型の実装は `CatalogLoader` と `TokenResolver` に残っている。**
一本化を検討したが担うものが違う——`CatalogLoader.parse_shorthand_to_numbers` は
著者が並べる表を読むので読めない行で全体を止めず、
`TokenResolver::Resolver#normalize` は CLI 引数を受けるので番号以外も正当な入力で、
返すのも `Integer` ではなくゼロ埋めトークンである。
**同じ綴りでも「読めなかったとき何をするか」が違うものは、一本化すると
どちらかの正しさを壊す。**
