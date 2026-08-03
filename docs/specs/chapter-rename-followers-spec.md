# 章名変更の追随仕様書 — 改名フックを登録制にする

> 作成日: 2026-08-03
> ステータス: **実装待ち**
> 起票: `index-main-reference-spec.md` の `main:`（辞書が章名を保持する）を実装した際、
> `vs rename` / `vs renumber` が辞書に触れないため主要参照が黙って壊れることが判明した
> 決定事項:
> - 章名の変更に追随すべき処理は**登録簿 1 つ**に集約する。追随先が増えたら**そこへ 1 行足すだけ**にする
> - 追随先が失敗しても**改名そのものは止めない**。原稿ファイルの移動は既に済んでいるので、途中で止めると中途半端な状態が残る
> - **辞書の `main:` は捨てずに書き換える**。著者の判断＝一次データなので、`contexts` のように「実在しなければ捨てる」扱いはできない
> - 章番号で書かれた設定（`metrics.exclude_chapters` 等）は**追随しない**。範囲指定の意味を機械が推測できないため、警告に留める
> 関連: `lib/vivlio_starter/cli/rename.rb`, `lib/vivlio_starter/cli/build/catalog_updater.rb`, `lib/vivlio_starter/cli/index/unified_terms_manager.rb`, `index-main-reference-spec.md`, `config-extension-guidelines.md`

## 0. 背景

`vs rename` / `vs renumber` は章のファイル名を変える。ファイル名（basename）は
**プロジェクト内の複数の場所から参照されている**ので、変更すればそれらも追随しなければ
壊れる。

現在の追随先は 3 つで、**2 つの実行経路それぞれに直書き**されている。

| 経路 | 場所 |
|---|---|
| 一括改番 | `rename.rb#apply_renumber`（`vs renumber`） |
| 単一改名 | `rename.rb#execute_single_rename`（`vs rename`） |

```ruby
# apply_renumber / execute_single_rename の双方にある（重複）
FileUtils.mv(old_file, new_file)                            # 原稿ファイル
Build::CatalogUpdater.rename_chapter(old, new)              # catalog.yml
FileUtils.mv("images/#{old}", "images/#{new}")              # 画像ディレクトリ
```

**画像ディレクトリの移動は既に 2 箇所へコピーされている**（衝突時の警告文まで同じ）。
追随先が 4 つ目・5 つ目と増えるたびに、この重複が倍で増えていく。

## 1. 追随できていない参照（2026-08-03 調査）

### 1.1 【要対応】辞書の `main:` — 主要参照が黙って壊れる

`index-main-reference-spec.md` の `main:` は章の basename を保持する。

```yaml
- term: Markdown
  main:
    - 21-markdown-tutorial
    - 22-extentions
```

21 章を 20 章へ改番すると `21-markdown-tutorial` は宙に浮き、**索引ページの太字が
黙って消える**。エラーも警告も出ない。

**`contexts` とは扱いが違う。** 辞書には章名を持つ箇所がもう 1 つあり、
本書で 707 件ある `contexts[].chapter` は**自己修復する**——`context_live?` が
実在しない章の context を捨て、本文から拾い直す（`index-glossary-consistency-spec.md` R5）。
表示専用の派生データだから捨てられる。

`main:` は**著者が下した判断**で、捨てたら情報そのものが失われる。書き換えるしかない。

### 1.2 【要対応】辞書の `scanned_chapters`

`vs index:auto` が走査した章の集合（`index-glossary-consistency-spec.md` R7）。
改番後に古い basename が残ると、**ビルド時に「未走査の章がある」と誤警告する**。
本書では現在 0 件だが、`vs index:auto` を実行すれば書かれる。

### 1.3 【追随しない】章番号で書かれた設定

| 設定 | 例 | なぜ追随しないか |
|---|---|---|
| `metrics.exclude_chapters` | `[00, 90-98, 99]` | **範囲の意味を機械が推測できない**。`90-98` は「付録すべて」の意図かもしれず、改番で 89-97 へずらすのが正しいとは限らない |
| `chapters`（ビルド対象の絞り込み） | `"54-56"` | 同上。しかも一時的な指定であることが多い |

**黙って書き換えるほうが危険**なので、追随の対象にしない。
ただし §3.3 のとおり、改番後に「番号で書かれた設定がある」ことは知らせる。

### 1.4 追随済み・対応不要

| 参照 | 状態 |
|---|---|
| `catalog.yml` | `CatalogUpdater.rename_chapter` が追随済み |
| `images/<basename>/` | 追随済み（ただし実装が 2 箇所に重複・§0） |
| 原稿中のクロスリファレンス `@id` | ラベル基準で章名に依らない。対応不要 |
| 生成物（HTML・PDF） | `cleanup_generated_files` が削除する。対応不要 |

## 2. 設計 — `ChapterRename` の登録簿

`lib/vivlio_starter/cli/chapter_rename.rb` を新設する。

```ruby
module VivlioStarter
  module CLI
    # 章名の変更に追随すべき処理の唯一の登録簿。
    # 追随先が増えたら FOLLOWERS へ 1 行足す。呼び出し側（rename.rb）は変えない。
    module ChapterRename
      module_function

      # 追随先。label は失敗時のメッセージに使う。
      # handler は (old_basename, new_basename) を受け、追随したら true を返す。
      FOLLOWERS = [
        Follower.new(label: 'catalog.yml',   handler: ->(old, new) { ... }),
        Follower.new(label: '画像ディレクトリ', handler: ->(old, new) { ... }),
        Follower.new(label: '索引辞書',        handler: ->(old, new) { ... })
      ].freeze

      # 章名の変更を全追随先へ伝える。
      # @param old_basename [String] 例 '21-markdown-tutorial'
      # @param new_basename [String] 例 '20-markdown-tutorial'
      def follow!(old_basename, new_basename)
        FOLLOWERS.each do |follower|
          follower.handler.call(old_basename, new_basename)
        rescue StandardError => e
          Common.log_warn("#{follower.label} の追随に失敗しました: #{e.message}",
                          detail: "#{old_basename} → #{new_basename} を手作業で反映してください")
        end
      end
    end
  end
end
```

### 2.1 失敗しても改名は止めない

`follow!` は 1 つの追随先が落ちても他を続け、例外を外へ投げない。

**原稿ファイルの移動は追随より先に済んでいる**ので、途中で `abort` すると
「ファイルは新しい名前、catalog は古い名前」という中途半端な状態が残る。
それより、追随できなかったものを**名指しで警告して先へ進む**ほうが復旧しやすい。

これは画像ディレクトリの既存実装（衝突したら警告して続行）と同じ立場である。

### 2.2 呼び出し側は 1 行になる

```ruby
# apply_renumber
rename_map.each do |old_basename, info|
  FileUtils.mv(info[:old_file], info[:new_file])
  ChapterRename.follow!(old_basename, info[:new_basename])
end

# execute_single_rename
FileUtils.mv(old_md, new_md)
ChapterRename.follow!(old_basename, new_basename)
```

画像ディレクトリの重複（§0）はこれで解消する。

### 2.3 一括改番での順序

`vs renumber` は複数章を一度に動かすので、**中間状態での衝突**がありうる
（21→20, 22→21 と動かすとき、22→21 の時点で 21 が空いている必要がある）。

現在の実装は `rename_map.each` でファイル移動を先に全部済ませてから
画像ディレクトリを回している。**この 2 段構えを維持する**——
`follow!` も全ファイル移動の後にまとめて回す。

```ruby
rename_map.each { FileUtils.mv(it[:old_file], it[:new_file]) }   # 先に全ファイル
rename_map.each { ChapterRename.follow!(old, it[:new_basename]) } # その後に追随
```

## 3. 要件

### R1: 辞書の `main:` を書き換える

`UnifiedTermsManager` に章名の一括置換を足す。

```ruby
# 章名の変更に追随して main: を書き換える。
# main は著者の判断＝一次データなので、実在しない章を指していても捨てない
# （contexts のように「捨てて拾い直す」ことができない）。
# @return [Integer] 書き換えた語数
def rename_chapter_in_main!(old_basename, new_basename)
```

- 単一値・リストの両方を扱う
- 該当が 0 件なら辞書を書き換えない（無用な `generated_at` 更新を避ける）
- 書き換えたら `log_info` で語数を報告する

### R2: 辞書の `scanned_chapters` を書き換える

同じく `UnifiedTermsManager` に足す。`main:` と同じ呼び出しで済ませる
（辞書の読み書きを 2 回に分けない）。

### R3: `catalog.yml`・画像ディレクトリを登録簿へ移す

既存の処理を `FOLLOWERS` の項目として移設する。**挙動は変えない**——
画像ディレクトリの衝突時警告もそのまま持っていく。

### R4: 番号で書かれた設定があることを知らせる

改番後、`metrics.exclude_chapters` や `chapters` が**明示的に書かれていれば**
1 回だけ案内する。`Common.authored_key?` で「著者が書いたか」を判定する
（既定値のときは黙る。`config-extension-guidelines.md` §4 の機構）。

```
🟡 章番号で指定した設定があります。改番に合わせて見直してください
   metrics.exclude_chapters: [00, 90-98, 99]
   範囲の意味（「付録すべて」なのか特定の章なのか）は機械には判断できないため、
   自動では書き換えていません。
```

### R5: `main:` が実在しない章を指していたら警告する（安全網）

登録簿は `vs rename` / `vs renumber` を通ったときしか効かない。
`git mv` や手作業の改名は取りこぼすので、**ビルド時にも検査する**。

`index-main-reference-spec.md` R1 の妥当性検査（指定章が `contents/` に存在しない →
警告＋近い章名を候補提示）がこれに当たる。**そちらの実装で満たす**ため本仕様では扱わない。

## 4. テスト

| 対象 | 検証 |
|---|---|
| `ChapterRename.follow!` | 全追随先が呼ばれる／1 つが例外を投げても他は続く／例外を外へ投げない |
| 同上 | 失敗した追随先を名指しで警告する（黙って握り潰さない） |
| `UnifiedTermsManager#rename_chapter_in_main!` | 単一値・リストの両方を書き換える／無関係な語に触れない／該当 0 件なら辞書を書き換えない |
| `scanned_chapters` | 同上 |
| `vs rename` 結合 | 改名後に辞書の `main:` が新 basename を指す |
| `vs renumber` 結合 | 複数章の一括改番でも `main:` が正しく追随する（中間状態での取り違えがない） |
| R4 | 番号指定の設定が**明示されていれば**案内し、既定値なら黙る |

**結合テストが要る。** 単体で `follow!` を検証しても、呼び出し側が呼び忘れていれば
意味がない——今回の起票がまさに「呼ばれていなかった」問題である。

## 5. 実装フェーズ

| Phase | 内容 |
|---|---|
| 1 | `ChapterRename` の骨組み ＋ `catalog.yml`・画像ディレクトリの移設（挙動不変・重複解消） |
| 2 | R1・R2（辞書の `main:` と `scanned_chapters`） |
| 3 | R4（番号指定の設定の案内） |

Phase 1 は**挙動を変えない整理**なので、既存テストが通ることが完了条件になる。

## 6. 完了時の作業

- `PLANNED.md` に「改名フックの登録簿」という項目があれば削除する（現時点では無い）
- 本ファイルを `docs/archives/` へ `git mv` し、`STATUS.md` の該当行を削除する
- `config-extension-guidelines.md` に「章名を保持する設定を足すときは `FOLLOWERS` へ登録する」旨を 1 行足す
- `contents/23-chapter-management.md`（`vs rename` / `vs renumber` の解説）に、
  改番で何が追随し何が追随しないかを追記する
