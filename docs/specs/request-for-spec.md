PLANNED.md:17
- [High] **設定ファイルを経由しない直接ビルドコマンド**: `vs build myawesome.md --theme:blue` や `vs build contents/00-preface.md --theme:sakura`のように、`book.yml` / `catalog.yml` を介さず単一 Markdown を直接ビルドできる軽量経路を提供する。 マークダウン単体に画像やソースコードのincludeを含まず、また、喩え、contents/以下の原稿ファイルが指定されたとしても、章名解決は行なわず、本章(01-89 chapter扱い)とする。出力はpdfのみに限定する(--print_pdf, --epub, --kindleのようなオプションは設けない）

PLANNED.md:19
- [Low] **既存プロジェクトのアップグレード専用コマンド（`vs sync` / `vs upgrade`）**: 現状は `vs new <既存> --add-missing` が「不足ファイルの非破壊バックフィル」を兼ねているが、(1) 新規作成コマンドへの相乗りで意味が紛らわしい、(2) 既存ファイルが新しい雛形で**更新された**場合（CSS 改良など）は反映できない、という弱点がある。gem 更新時に新規追加ファイルの補完だけでなく更新差分の取り込み（diff 提示・選択適用）まで行う専用コマンドへ切り出し、`vs new` から `--add-missing` を外す。
徒にコマンド名を増やすのではなく、vs doctor に統合しても良いが、既存プロジェクトのアップグレードであるため、別コマンドが良いと思われる。（vs new --add-missing も廃止できる）

PLANNED.md:43
- [Medium] **会話文（対話）記法の刷新と `config/characters.yml` 化**: かつての会話文は `先生`/`生徒` の 2 トリガーをハードコード置換し、`.kaiwa.sensei` / `.kaiwa.seito` の隠れクラスで色付けする方式だったが、(1) 著者が `教授`/`学生A` 等を増やすには編集の敷居が高い、(2) `【先生A】` の `A` がクラスとしてしか残らず表示名は `::before` で固定、と分かりにくかったため**廃止済み**（後継の記法を本項目で刷新する）。著者が **CSS を書かずに**キャラクターを定義できるよう `config/characters.yml`（仮）へ切り出す。検討要素が多いため記法・データモデルを練ってから着手する。
  - **設定の表現**: 簡易形（`山田: "#1565c0"` ＝色だけ）と詳細形（`表示名` / `色` / `アイコン画像` / `吹き出しの左右` など）の両対応。
  - **記法候補（要検討）**: ブロック型 `:::{.talk}` 内に `yamada: …`（ローマ字キー＋コロン）または `【山田】…`（全角に切替えず書ける）を行で並べる案。話者を左右に振り分けるチャットアプリ風レイアウト、`山田：「…」` / `「…」：花子` のような左右対話表示も視野に。
  - **アイコン対応**: キャラクターアイコン画像を置く標準ディレクトリ（例 `images/characters/`）の取り決めが要る。
  - **マルチターゲット**: クラス CSS は PDF/EPUB で効くが、**Kindle は `::before content` を無視**するため、column/notice と同様に表示名（`山田: `）の**実体ラベル注入**による劣化が必要。吹き出し等の凝ったレイアウトは Kindle で簡易表示へ落とす方針も決める。
  - **現状**: 記法が未確定のため、`contents/22-extentions.md` の「会話文」節はいったん HTML コメントで本文から外してある（仕様確定後に書き直す）。`先生`/`生徒` のハードコード置換経路は**廃止済み**、`.kaiwa.sensei` / `.kaiwa.seito` の CSS も**削除済み**。刷新時はゼロから設計する。

PLANNED.md:94
- [High] **`vs doctor` にツールのバージョンアップ機能**: 各種ツールを最新版へ更新する機能を付与する。

PLANNED.md:98
- [Medium] **`vs preflight` の章別エラー・警告サマリー**: 現状はファイル処理中にリアルタイム出力され章をまたいで混在する。章ごとに「21 章: 警告 N 件、エラー N 件」とまとめて表示するには、`LinkImageValidator` にコードインクルード・クロスリファレンス・QueryStream のエラーも蓄積する汎用メカニズムが必要（影響 4〜5 ファイル）。
  - **付随して直したい非対称**: 最終行のサマリー（`print_preflight_summary`）は `LinkImageValidator.any_issues?` だけを見るため、**Guard 系の `:warn` がサマリーに反映されない**。`ContainerClassCheck` が未知クラスを警告しても最終行は「✅ Preflight 完了: 良好な状態です」になる（終了コード 0 は設計どおりだが、文言は警告件数を拾う方が親切）。一方 `LinkImageValidator` の裸 URL 警告は `link_issues` に積まれるため「課題あり」に転ぶ。

PLANNED.md:103
- **コマンド実行時の応答メッセージ**: `vs clean` などで処理結果の応答があると親切。(現状は、コマンド実行後に応答があるコマンドとないコマンドが混在している)

PLANNED.md:104
- **CLI スピナー（ビルド進捗表示）**: ビルドは時間がかかるため、止まって見えないよう進捗アニメーションを表示したい。定番ライブラリ（`ora` / `cli-spinners`）か、以下のような簡易自作で実装できる。

---

## 仕様書 作成状況（2026-07-12）

全 6 項目の仕様書を作成済み（効果度の高い順）:

| PLANNED 項目 | 仕様書 |
|---|---|
| PLANNED.md:17 [High] 直接ビルドコマンド | [direct-build-spec.md](direct-build-spec.md) |
| PLANNED.md:94 [High] doctor ツールバージョンアップ | [doctor-tool-upgrade-spec.md](doctor-tool-upgrade-spec.md) |
| PLANNED.md:43 [Medium] 会話文記法・characters.yml | [characters-dialogue-spec.md](characters-dialogue-spec.md) |
| PLANNED.md:98 [Medium] preflight 章別サマリー | [preflight-chapter-summary-spec.md](preflight-chapter-summary-spec.md) |
| PLANNED.md:103–104 応答メッセージ＋スピナー（統合） | [command-feedback-spinner-spec.md](command-feedback-spinner-spec.md) |
| PLANNED.md:19 [Low] vs sync / vs upgrade | [project-upgrade-command-spec.md](project-upgrade-command-spec.md) |
