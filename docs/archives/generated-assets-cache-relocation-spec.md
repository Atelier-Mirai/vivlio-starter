# 生成資産の .cache 移設仕様（covers 生成物・テーマ画像バリアント）

作成: 2026-07-07 ／ 改稿: 2026-07-10（①print_pdf 導出・②dedup 高速化＝5f7406cf 実装後の
現行コードと突合し全面改稿） ／ ステータス: 確定仕様・実装待ち

## 0. 目的と結論

P4/P4b で中間生成物は `.cache/vs/` へ集約されたが、**著者ディレクトリへ書き込む生成物が
2 系統だけ残っている**。これらも `.cache/vs/` へ移設し、「著者ディレクトリ＝ソースのみ、
生成物＝.cache」という一貫性を完成させる。

1. `covers/` — `vs cover`（およびビルド内自動生成）が出力する PDF / JPG / SVG
2. `stylesheets/images/**` — `ImageGenerator` が生成する `*_portrait.webp` / `*_landscape.webp`

なお「章扉・節絵の合成 JPEG（HeadingImageComposer）」は P4b 済みで、既に
`.cache/vs/build/{epub,kindle}/images/headings/` に出ており本仕様の対象外。

この移設は単なる整理ではなく、次の**実害**を構造的に解消する:

- **著者マスター画像がデフォルトで git 管理されない**: scaffold の `.gitignore` は
  `/covers/` を丸ごと無視し `!/covers/*.svg` で SVG だけ復活させるハック構成。
  このため著者が置いた `frontcover_master.png` は無視される（生成物と著者資産が
  同居しているせいで粗い除外しか書けない）。移設後は `covers/` が全部ソースになり、
  ignore 行そのものを撤去できる。
- **clean.rb の分類ヒューリスティクス**: 「`*_light.svg` は生成物、他の SVG は著者の物、
  PDF/JPG は全部生成物」というパターン推測（`clean_cover_files` /
  `clean_bundled_variant_images`）が不要になる。
- **copy_to_scaffold.rb の PRUNE**: バリアント webp・covers 内生成物の除去ロジックが不要になる。
- **著者プロジェクトの untracked 汚染**: ビルドすると `stylesheets/images/bundled/` に
  生成 webp が湧き、git status を汚す（本 repo では `.git/info/exclude` で局所回避している
  ＝共有されない回避策で恒久解でない）。

P4 調査書 §1.3/§5.1 は「covers/ は著者資産・不変」としたが、これは
**マスターと生成物を区別しない粗い括り**であり技術的制約ではない。本仕様は
「マスター＝covers/ に残す ／ 生成物＝.cache へ」の区別を導入して同判断を更新する
（`docs/archives/vivlioverso-p4-investigation.md` に相互参照の追記を行う）。

## 1. 対象の棚卸し

### 1.1 covers/（生成物 → 移設）

| ファイル | 生成元 | 消費者 |
|---|---|---|
| `{front,back}cover_{theme}_{size}_rgb.pdf` | cover.rb `generate_rgb_pdf`（master/カスタム）／ create.rb `generate_cover_outputs_from_svg`（light/dark） | pdf_merger.rb `cover_enhanced_files`（閲覧用 PDF へ結合） |
| `{front,back}cover_{theme}_{size}_cmyk.pdf` | cover.rb `generate_cmyk_pdf`（master/カスタム）／ create.rb 同上（light/dark・crop_marks 付き） | **結合しない**（①導出化で print_pdf は本文と別ファイル入稿。print_pdf_builder.rb は `ensure_cover_files_for_build!` で生成をトリガするのみ）。**成果品としてルート直下へ複製（§3.4）** |
| `cover_{theme}.jpg` | cover.rb `generate_epub_cover`（master/カスタム）／ create.rb 同上（light/dark） | epub_builder.rb `resolve_cover_image_path` → `localize_cover_image!` |
| `{front,back}cover_{light,dark}.svg` | create.rb `render_bundled_svg`（bundled テンプレ＋パレット置換） | create.rb（PDF/JPG 化の中間） |
| `*_rendered.svg` | create.rb `apply_text_placeholders_to_svg`（ユーザー SVG へのプレースホルダー適用中間物） | 同上 |

※初版は CMYK カバーの消費者を「print_pdf_builder.rb（印刷 PDF へ結合）」としていたが、
①（print-pdf-derivation-spec・2026-07-10 実装）で print_pdf 本文は閲覧用 PDF から導出する
方式になり、**カバーは結合せず別ファイル入稿**へ変わった。print_pdf_builder.rb には
covers パスへの参照が存在しない（`build!` 冒頭で `CoverCommands.ensure_cover_files_for_build!`
を呼ぶだけ）。

### 1.2 covers/（ソース → 残す）

`frontcover_master.png` / `backcover_master.png` / `*.key` / ユーザー自作 SVG
（`frontcover_floral.svg` 等）/ ユーザー自作 PNG（`frontcover_{theme}.png`・カスタムテーマ）/
`covers/bundled/*.svg`（テンプレート本体）/ `_README.md`。

**同名パターンの帰属に注意**: `frontcover_{theme}.svg` は、light/dark テーマでは
create.rb が生成する**生成物**（→ cache へ）だが、カスタムテーマではユーザーが置く
**ソース**（→ covers/ に残る）。移設後の探索規則は §3.5 で定める。

### 1.3 stylesheets/images/（生成物 → 移設）

`**/*_portrait.webp` / `**/*_landscape.webp`（image_generator.rb。waifu2x 2x アップスケール
＋対角線分割クロップ。現行は `base_dir = File.dirname(source_path)`＝**ソース画像の隣**に
生成される）。基画像（`bundled/sakura.webp` 等・ユーザー配置画像）はソースとして残す。
生成途中の中間ファイル（`*_alpha*` / `*_color*` / `*_merged*`）は tmpdir 隔離済みで
本仕様の対象外（clean.rb / copy_to_scaffold.rb の保険掃除だけが言及している）。

## 2. 移設先レイアウト

```
.cache/vs/
├── build/              # 既存（final clean = rm_rf BUILD_DIR の対象）
├── covers/             # ★新設: 1.1 の生成物すべて（内部構造はフラット・現行ファイル名を維持）
└── theme-images/       # ★新設: バリアント webp（stylesheets/images/ からの相対サブパスを維持）
    ├── bundled/sakura_portrait.webp
    └── myphoto_landscape.webp        # ユーザー画像由来はルート直下（現行の「隣に生成」と同型）
```

**`build/` の外に置く理由**: final clean は `rm_rf BUILD_DIR` のみ（P4b）。バリアント生成は
waifu2x を伴い高コストなので、通常 clean を生き延びるキャッシュとして扱う。covers も
`vs cover` 再実行で再生成可能だが毎ビルド再生成は無駄なので同格に置く。

**生成メモ化の現行実態**（初版の記述を訂正）: メモ化は cover.rb 側ではなく
pdf_merger.rb の `ensure_cover_assets_for_page_size!`（`@cover_generation_attempts`）に
ある（Step 10 内の重複起動防止）。print_pdf_builder.rb は `build!` ごとに
`ensure_cover_files_for_build!` を直接 1 回呼ぶ。いずれも移設の影響を受けず現行のまま。
バリアント webp は `ensure_variant_generated` の存在チェック（生成済みならスキップ）が
実質のメモ化で、チェック先パスが cache に変わるだけ。

`Common` に定数/ヘルパを追加する:

```ruby
COVER_CACHE_DIR        = "#{CACHE_DIR}/covers"
THEME_IMAGES_CACHE_DIR = "#{CACHE_DIR}/theme-images"
def cover_cache_dir        = File.join(cache_dir, 'covers')
def theme_images_cache_dir = File.join(cache_dir, 'theme-images')
```

`directories.covers` 設定は**「著者マスター置き場」の意味に純化**する（読み取り探索のみに
使い、書き込み先には使わない）。なお create.rb は現行 `File.join(Dir.pwd, 'covers')` の
直書きで `directories.covers` を見ていない（`execute_cover` / `bundled_template_path`）。
本移設の実装時に読み取り側を `Common.covers_dir` へ正規化する（挙動は既定値なら不変）。

## 3. 参照経路の変更

### 3.1 PDF ビルド

**RGB カバー PDF（閲覧用へ結合）**: pdf_merger.rb `cover_enhanced_files` の
`File.join(covers_dir, "…_rgb.pdf")` を `Common.cover_cache_dir` 基準へ差し替える
（結合処理はパス非依存。同 16 行目の P4 §5.1 引用コメントも本仕様参照へ更新）。
**print_pdf_builder.rb は変更不要**（§1.1 のとおり covers パスを参照していない）。

**バリアント webp の url()**: book-settings.css は `.cache/vs/` 直下に生成されるため、
バリアント参照は現行の `url("../../stylesheets/images/bundled/sakura_landscape.webp")` から
`url("theme-images/bundled/sakura_landscape.webp")` へ**短くなる**。ただし著者が
stylesheets/images/ に直接置いた画像（バリアントでないもの）は従来どおり
`../../stylesheets/images/…` を維持する必要があり、**URL は 2 系統になる**:

- theme_image_resolver.rb `theme_relative_path` の返却形を 2 形に変更する:
  cache 内バリアント → `theme-images/<サブパス>`、stylesheets 内実体 → `images/<サブパス>`
  （従来形）。
- book_settings_css.rb `rebase_relative` は「`theme-images/` で始まるパスは既に生成位置
  基準なので素通し、それ以外は従来どおり `CACHE_TO_STYLESHEETS` を前置」とする
  （既存の冪等ガードと同型の分岐を 1 つ足すだけ）。

### 3.2 EPUB / Kindle

- **表紙 JPG**: `resolve_cover_image_path` の探索先を `Common.cover_cache_dir` へ変更。
  **現行実装はソース相対パスとパッケージ内パスが偶然一致している**ことに依存している
  （`epub_cover_config_line` が `cover: './covers/cover_x.jpg'` を書き、
  `localize_cover_image!` が `File.join(dir, cover)` へコピー＝同じ相対が両用）。
  移設後はソースが `.cache/vs/covers/…` になるため両者を分離する:
  config の cover: 行は**パッケージ内固定パス** `./covers/cover_{theme}.jpg` を書き、
  `localize_cover_image!` は cache のソース → `dir/covers/cover_{theme}.jpg` へコピーする。
- **バリアント webp**: 現行は「特例フィルタ」ではなく、stylesheets/ 全体の再帰コピー
  `copy_asset_tree!(Common.stylesheets_dir)` に**相乗り**して同梱されている
  （`localized_stylesheet?` にバリアント特例は存在しない。kindle フレーバのみ
  `.webp` 全除外）。移設後は相乗りが消えるため、**theme-images のローカライズ経路を
  1 本追加**する: `.cache/vs/theme-images/**` のうち book-settings.css（EPUB 変種）が
  url() で参照するファイルをパッケージ `theme-images/` へコピーする。
  **url() の組替は不要**（`theme-images/…` は CSS からの相対として cache 内でも
  パッケージ内でも同一に解決する。`../../stylesheets/` → `stylesheets/` の既存 gsub は
  著者直置き画像用にそのまま残る）。kindle フレーバは現行の `.webp` 除外と整合させ、
  このローカライズをスキップする（webp url() は `sanitize_epub_css!` が除去する）。
- **扉絵/節絵合成（heading composer）**: `resolve_theme_image_file` は url() の相対値を
  `Common::STYLESHEETS_DIR` 基準でしか実ファイル解決していない。移設後はバリアントの
  解決値が `theme-images/…` になるため、**`theme-images/` 始まりは
  `Common.theme_images_cache_dir` 基準で解決する分岐を追加**する（初版で漏れていた変更点）。

### 3.3 theme.css の既定値 2 行（要判断・推奨あり）

`stylesheets/theme.css:74,79` は生成物を直接参照している:

```css
--section-bg-image:   url("images/bundled/sakura_landscape.webp");
--frontispiece-image: url("images/bundled/sakura_portrait.webp");
```

book-settings.css が同変数を**毎ビルド必ず**上書きするため、この既定値は実質デッドコード。
**推奨: 2 行を削除し「book-settings.css が設定する」旨のコメントに置き換える**
（theme.css は著者編集ファイルなので、scaffold 更新＋CHANGELOG 記載）。
なお著者が theme.css で**自分の画像**を `url("images/mypic.webp")` と直書きする経路は
生成物参照ではないため従来どおり動く。

### 3.4 印刷カバー PDF は成果品としてルート直下へ複製する（決定済み）

CMYK カバー PDF は入稿物（成果品）であり、最終 print PDF（`書名_print_v1.0.0.pdf`）と
同格にプロジェクトルート直下へ置く。中間物と成果品の二面性は
「**生成は cache・納品はルート複製**」で扱い分ける:

- **生成**: `.cache/vs/covers/frontcover_{theme}_{size}_cmyk.pdf` 等の内部名で生成
  （再生成の判定・`vs cover` 再実行はこの内部名のまま）。
- **複製**: 生成直後にルート直下へ**コピー**（move ではない。cache 側は再生成判定と
  `vs cover` 単独実行の生成場所として残す。※初版の「ビルド結合のため残す」は
  ①導出化で結合が消えたため理由から削除）。命名は `Common.generate_output_filename` の
  規則に倣い `{project.name}_frontcover_v{version}.pdf` /
  `{project.name}_backcover_v{version}.pdf`（`include_version` 準拠。専用ヘルパ
  `generate_cover_output_filename(side)` を Common に追加）。
- **複製の実装位置**: CMYK 生成は **2 経路**ある——cover.rb `generate_cmyk_pdf`
  （master/カスタムテーマ・PNG 経由）と create.rb `generate_cover_outputs_from_svg`
  （light/dark テーマ・SVG 経由・crop_marks 付き）。ルート複製は共通ヘルパ
  （例: `CoverCommands.publish_print_cover!(side, cache_pdf_path)`）に切り出し、
  **両経路から呼ぶ**（初版は cover.rb 側しか挙げていなかった）。
- **タイミング**: ①`print_pdf` ターゲットを含むビルドで CMYK カバーを生成した時点、
  ②明示 `vs cover a4` 等の実行時（このとき §5-1 の `log_result` でルート側パスを提示）。
  RGB カバー・EPUB 表紙 JPG・SVG 中間物は複製しない（純粋な中間物）。
- **著者事前準備画像の場合も自動で満たされる**: 塗り足し込み著者画像
  `frontcover_master_bleed.png`（`resolve_print_cover_input` が最優先採用）経由でも、
  CMYK PDF 化は vs 側で行うため同じ複製経路に乗る。著者は covers/ を掘らずに
  ルートで入稿一式（本文 print PDF ＋表紙 PDF）が揃う。
  ※現行の入力規約は PNG のみ（`*_bleed.pdf` の直接入力は未サポート・本仕様のスコープ外）。
- ルートの `*.pdf` はグローバル ignore 済みのため .gitignore 追記は不要。
  final clean は `rm_rf BUILD_DIR` のみでルート成果品には触れない（P4 の原則どおり）。

### 3.5 移設後の探索規則（ソース vs 生成物の同名衝突）

§1.2 の帰属注意に対応する規則を明文化する:

- **ソース探索**（ユーザー上書きの検出）は従来どおり **covers/ のみ**を見る:
  create.rb `resolve_cover_source`（ユーザー PNG → ユーザー SVG → bundled テンプレ）、
  cover.rb `resolve_epub_cover_input` / `check_master_files` / `resolve_print_cover_input`。
  これらは移設後も探索先を変えない（cache を見てはいけない——生成物をソースと
  誤認するため）。
- **生成物の読み取り**（変換の中間・結合・同梱）は **cache のみ**を見る:
  pdf_merger（RGB PDF）、epub_builder（cover JPG）、create.rb 内の SVG→PDF/JPG 変換
  （render_bundled_svg / apply_text_placeholders_to_svg の出力 SVG を後段が読む箇所）。
- light/dark テーマの生成 SVG（`frontcover_light.svg` 等）が covers/ から消えることで、
  `resolve_cover_source` の優先順位 2（ユーザー SVG）が生成 SVG を誤って拾う余地も
  構造的になくなる（現行は同名のため、生成後の再実行でユーザー SVG 扱いになり得た）。

## 4. 変更ファイル一覧（2026-07-10 現行コードと突合済み）

| ファイル | 変更 |
|---|---|
| common.rb | `COVER_CACHE_DIR` / `THEME_IMAGES_CACHE_DIR` ＋ヘルパ追加、`generate_cover_output_filename(side)` 追加（`generate_output_filename` の include_version 規則に準拠） |
| cover.rb | 生成物出力（`generate_rgb_pdf` / `generate_cmyk_pdf` / `generate_epub_cover`）を `cover_cache_dir` へ。ソース探索（マスター・`resolve_print_cover_input` / `resolve_epub_cover_input`）は covers/ のまま（§3.5）。CMYK 複製ヘルパ `publish_print_cover!` 追加＋ `log_result` でルート側パス明示 |
| create.rb | `render_bundled_svg` / `apply_text_placeholders_to_svg` の出力 SVG と `generate_cover_outputs_from_{svg,png}` の全出力を cache へ。CMYK 生成後に `publish_print_cover!` を呼ぶ（§3.4・SVG 経路）。`Dir.pwd + 'covers'` 直書きを `Common.covers_dir` へ正規化（読み取りのみ） |
| pdf_merger.rb | `cover_enhanced_files` の RGB PDF 読み取り元を `cover_cache_dir` へ（16 行目の P4 §5.1 コメントも更新） |
| ~~print_pdf_builder.rb~~ | **変更不要**（①導出化でカバー結合が消滅。covers パス参照なし） |
| epub_builder.rb | `resolve_cover_image_path` → cache 探索。`epub_cover_config_line` をパッケージ内固定パスへ・`localize_cover_image!` の dest をソース由来から分離（§3.2）。theme-images ローカライズ追加（:epub のみ・kindle はスキップ）。`resolve_theme_image_file` に `theme-images/` → cache 解決の分岐追加 |
| image_generator.rb | `ensure_variant_generated` / `target_path` を `theme_images_cache_dir`＋（images root からの相対サブパス）基準へ。ソース解決 `resolve_image_reference` は stylesheets/images のまま |
| theme_image_resolver.rb | `find_existing_theme_variant` の探索先を cache へ、`theme_relative_path` を 2 形返却へ（§3.1）。`theme_image_available?` も同基準 |
| book_settings_css.rb | `rebase_relative` に `theme-images/` 素通しガード追加（§3.1） |
| clean.rb | `clean_cover_files` / `clean_bundled_variant_images` → cache dir の `rm_rf` へ縮退（＋§6 の移行掃除） |
| theme.css | 既定 2 行の削除（§3.3）。**scaffold 同期対象**（copy_to_scaffold.rb 実行） |
| .gitignore | `/covers/` ＋ `!/covers/*.svg` を撤去（`*.pdf` グローバル無視は既存のまま）。**scaffold 同期対象** |
| copy_to_scaffold.rb | バリアント webp PRUNE・covers PRUNE を撤去（`*_alpha*` 等の保険掃除は残してよい） |
| docs/archives/vivlioverso-p4-investigation.md | §1.3/§5.1 に本仕様への参照を追記（※docs/specs/ ではなく archives/ にある） |

テスト影響: cover 系・clean 系・theme_image_resolver 系・epub cover 系ユニットのパス期待値
更新、`rake test:layout` / `test:targets` での統合確認（特に test:targets は epub/kindle の
theme-images 同梱と print_pdf のカバー複製を通す）。`.git/info/exclude` のローカル除外
（バリアント webp / cover.jpg）は移設後に削除してよい。

## 5. 決定事項

1. **印刷カバー PDF の成果品化（決定済み・2026-07-07）**: CMYK カバー PDF は
   ルート直下へ `{project.name}_{front,back}cover_v{version}.pdf` として複製する（§3.4）。
   `vs cover` 明示実行時は `log_result` でルート側パスを一覧表示する。
2. **theme.css 既定値**: §3.3 のとおり削除を推奨。
3. **`directories.covers`**: マスター探索専用に純化（§2）。

## 6. 既存プロジェクトの移行

既存プロジェクト（著者の原稿 repo 含む）には旧位置の生成物が残留する。
**1 リリースの間だけ** clean.rb に「旧位置の生成物掃除」（現行 `clean_cover_files` /
`clean_bundled_variant_images` の判定ロジックをそのまま流用）を残し、`vs clean` 実行時に
`旧配置の生成物を削除しました（.cache へ移設済み）` と案内する。次のリリースで撤去。
CHANGELOG にも手動削除手順（削除対象パターン）を記載する。

## 7. 実施順序（改訂）

初版は「①本移設 → ②print_pdf 導出化 → ③カバー ICC」を推奨したが、実際は
**②print_pdf 導出化＋dedup が先に実装された**（2026-07-10・5f7406cf）。結果として
print_pdf 側のカバー結合が消え、本移設の PDF 経路の変更は pdf_merger.rb 1 箇所に減った
（むしろ簡単になった）。残る順序は:

**本移設（§4 一覧に沿って実装）→ cover-cmyk-color-management-spec（ICC 調整）**

②③間の依存は「移設後の安定したパスを土台にする」のみで、コード共有面の衝突はない。
