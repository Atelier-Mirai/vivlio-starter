# 設定キーを廃止するときの指針

対象: `config/book.yml` から設定キーを取り除く開発者
策定日: 2026-08-08 ／ 改訂: 2026-08-08（`CONFIG_KEYS` 導入に追随）

---

## 0. この文書の位置づけ

`config-extension-guidelines.md` はキーを**足す**ときの指針で、主題は
「各コマンドが独自に `book.yml` を読むのをやめ、`Common::CONFIG` に一本化する」ことである。
本書はその裏返し——キーを**やめる**ときの指針を扱う。

分けたのは、やめるときだけ「**著者が古い `book.yml` を持っている**」という時間軸の
問題が入るためである。足すときには無い関心事で、`retired:` 宣言と `authored_keys` という
別の仕掛けが要る。

**その前に**: そもそもやめてよいキーかは `config-key-criteria-guidelines.md` で問う。
本書は「やめると決めた後、どう畳むか」だけを扱う。

---

## 1. 廃止の手順

宣言は `ConfigKeys::KEYS`（現役）と `ConfigKeys::RETIRED`（廃止）の 2 つだけ。
**キーを前者から後者へ移すのが廃止である。**

```ruby
# lib/vivlio_starter/cli/config_keys.rb
KEYS = {
  %i[metrics mattr_window] => Spec[default: 100],      # ← ここから
}

RETIRED = {
  %i[metrics mattr_window] =>                           # ← ここへ移す
    Spec[retired: '語彙多様度を測る窓幅は算出方法そのもので、変えると章どうしを比べられなくなるため固定しました'],
}
```

手順は 3 つ。

1. `ConfigKeys::KEYS` から**キーを削除**し、`ConfigKeys::RETIRED` へ移す
2. ルートの `config/book.yml` からキーを削除し、`ruby copy_to_scaffold.rb` で雛形へ同期する
3. 読み出し側のコードを撤去する（値が来なくなるので必ず壊れる）

検出も案内も表が担うので、各コマンドは何も書かない。既定値スキーマ・
`RETIRED_CONFIG_KEYS`・`REQUIRED_BOOK_KEYS` はすべて表からの導出である。

### 案内文の書き方

値は**「代わりにどうするか」**を書く。著者が読んで行動できる文言にすること
（警告は具体的な修正案とセットにする、が本プロジェクトの流儀）。

```
🟡 config/book.yml の metrics.mattr_window は廃止されました
        語彙多様度を測る窓幅は算出方法そのもので、変えると章どうしを比べられなくなるため固定しました
🟡 上記のキーは読み込まれません。book.yml から削除してください
```

**実装の内情は書かない。** 「コードの半分が定数を直接見ており」のような説明は、
著者が読んで行動できることを 1 つも含まない。

### テストが手順を強制する

`config_keys_test.rb` が次を検査するので、手順を飛ばすと落ちる。

| 検査 | 飛ばした手順 |
| :--- | :--- |
| 廃止キーが `book.yml` に残っていないか | 手順 2 |
| `book.yml` の全キーが `KEYS` に宣言されているか | 手順 1 の消し忘れ |
| `authored:` と `retired:` が排他か | 状態の取り違え |
| 廃止キーが `default:` を持たないか | 「読まないのに値がある」矛盾 |

---

## 2. いつ案内が出るか

`Common.ensure_configured!` の入口で 1 度だけ発火する。ここはプロジェクトを必要と
する全コマンドが通る関門（`root_command.rb#ensure_project_context!`）なので、
著者はどのコマンドを叩いても気付ける。同じ実行で何度呼ばれても案内は 1 度だけ。

---

## 3. `authored_key?` とは何か

```ruby
@authored_keys = collect_key_paths(raw_config)   # YAML を読んだ直後・既定値マージ前
def authored_key?(*path) = authored_keys.include?(path)
private_class_method :authored_keys, :authored_key?
```

答えているのは **「`book.yml` というテキストに、そのキーが書かれているか」だけ**である。
ファイルについての構文的な事実であって、設定についての意味的な事実ではない。

**言えないこと**（重要）:

- どんな値が入っているか
- その値が既定値と違うか
- **著者がそれを考えて選んだか**

### 現役キーには使えない

`book.yml` は設定ファイルであると同時に**設定の一覧カタログ**でもあり、現役のキーは
既定値のまま全部載せてある（`config-key-criteria-guidelines.md` §1）。
したがって現役キーに対する `authored_key?` は**全プロジェクトで常に真**になり、
情報量がゼロである。

| 対象 | 使えるか | 理由 |
| :--- | :--- | :--- |
| 廃止キー | ◯ | `book.yml` から消してあるので、書いてあれば旧プロジェクトの置き土産と分かる |
| 現役キー | ✗ | 初めから書いてあるので常に真。何も判定できない |

**そこで `private_class_method` にしてある。** 呼び出し元は
`warn_retired_config_keys` の 1 箇所だけで、外から呼ぼうとすると `NoMethodError` になる
（`retired_config_keys_test.rb` がそれ自体を固定している）。文書で線を引くだけでは
同じ誤用が再発するため、機械的に塞いだ。

### 失敗例（2026-08-08 に撤去）

`vs rename` / `vs renumber` が、改番のたびにこう言っていた。

```
🟡 章番号で指定した設定があります。改番に合わせて見直してください
          metrics.exclude_chapters: [0, "90-98", 99]
```

`authored_key?(:metrics, :exclude_chapters)` が真だから出していたが、このキーは
`book.yml` に初めから書いてあるので**常に真**であり、改番の中身は一切見ていなかった。
見直す対象が無いのに毎回出るノイズだった（コミット `ee615cea`）。

**現役キーについて「効かない組み合わせ」を案内したいなら、記述の有無ではなく
値そのものを見ること。** 実例は `missing_book_config_keys`——`authored_key?` ではなく
`blank?(cfg.dig(*path))` で「著者が埋めたか」を判定している。

---

## 4. なぜ CONFIG では判定できないか

`CONFIG` は既定値スキーマとマージした「実効値」の view であって、著者が何を書いたかを
答えるものではない。

スキーマ外のキーは**自由拡張のために素通しする**（`test_should_pass_through_unknown_sections_and_keys`）。
つまり廃止キーも書けば `CONFIG` に載るので、今は `CONFIG` の形からでも記述の有無を
言い当てられてしまう。それでも `authored_keys` を見るのは、`CONFIG` での判定が
「そのキーが宣言表に無い」ことに寄りかかっており、**同名のキーが既定値付きで復活した
途端、誰も書いていないのに警告が出る**ようになるためである。

`authored_keys` は `load_config` が YAML を読んだ直後（既定値マージ前）に記録する。
**各コマンドが `book.yml` を読み直してはいけない**——設定アクセスを `CONFIG` に
集約した意図が損なわれるうえ、読み込みのタイミングと解釈が分散する。

---

## 5. 廃止キーを表から消してよいか

**消さない。** `RETIRED` は増える一方の表である。

古い `book.yml` を持つプロジェクトは、著者が `vs upgrade` を回すまで残り続ける。
案内を消すと、そのキーは「書いてあるのに黙って無視される」という最悪の形に戻る。

表 1 行のコストは小さく、失うものが大きい。**判断に迷ったら残す。**

---

## 6. 関連

- `config-key-criteria-guidelines.md` — そのキーは設定であるべきか（判断軸 5 本）
- `config-extension-guidelines.md` — キーの足し方（`CONFIG` アクセスの型）
- `config-defaults-design-spec.md`（archives）— `CONFIG_KEYS` を作った仕様と実装記録
