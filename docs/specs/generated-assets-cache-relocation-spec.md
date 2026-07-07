# 生成資産の .cache 移設仕様（covers 生成物・テーマ画像バリアント）

作成: 2026-07-07 ／ ステータス: 設計（実装前レビュー待ち）

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
（vivlioverso-p4-investigation.md に相互参照の追記を行う）。

## 1. 対象の棚卸し

### 1.1 covers/（生成物 → 移設）

| ファイル | 生成元 | 消費者 |
|---|---|---|
| `{front,back}cover_{theme}_{size}_rgb.pdf` | cover.rb `execute_for_size` | pdf_merger.rb（通常 PDF へ結合） |
| `{front,back}cover_{theme}_{size}_cmyk.pdf` | 同上 | print_pdf_builder.rb（印刷 PDF へ結合）。**成果品としてルート直下へも複製（§3.4）** |
| `cover_{theme}.jpg` | cover.rb `generate_epub_cover` | epub_builder.rb `resolve_cover_image_path` → `localize_cover_image!` |
| `{front,back}cover_{light,dark}.svg` | create.rb `render_bundled_svg`（bundled テンプレ＋パレット置換） | cover.rb（PDF/JPG 化の中間） |
| `*_rendered.svg` | create.rb（ユーザー SVG へのプレースホルダー適用中間物） | 同上 |

### 1.2 covers/（ソース → 残す）

`frontcover_master.png` / `backcover_master.png` / `*.key` / ユーザー自作 SVG
（`frontcover_floral.svg` 等）/ `covers/bundled/*.svg`（テンプレート本体）/ `_README.md`。

### 1.3 stylesheets/images/（生成物 → 移設）

`**/*_portrait.webp` / `**/*_landscape.webp`（image_generator.rb。waifu2x 2x アップスケール
＋対角線分割クロップ。bundled 画像は `bundled/` 直下に、ユーザー画像はその隣に生成される）。
基画像（`bundled/sakura.webp` 等・ユーザー配置画像）はソースとして残す。

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
`vs cover` 再実行で再生成可能だが毎ビルド再生成は無駄なので同格に置く
（`ensure_cover_files_for_build!` の生成試行メモ化は現行のまま活きる）。

`Common` に定数/ヘルパを追加する:

```ruby
COVER_CACHE_DIR       = "#{CACHE_DIR}/covers"
THEME_IMAGES_CACHE_DIR = "#{CACHE_DIR}/theme-images"
def cover_cache_dir        = File.join(cache_dir, 'covers')
def theme_images_cache_dir = File.join(cache_dir, 'theme-images')
```

`directories.covers` 設定は**「著者マスター置き場」の意味に純化**する（読み取り探索のみに
使い、書き込み先には使わない）。

## 3. 参照経路の変更

### 3.1 PDF ビルド（簡潔化する）

`book-settings.css` は `.cache/vs/` に生成されるため、バリアント参照は現行の
`url("../../stylesheets/images/bundled/sakura_landscape.webp")` から
`url("theme-images/bundled/sakura_landscape.webp")` へ**短くなる**（book_settings_css.rb の
生成ロジックと theme_image_resolver.rb の `theme_relative_path` を変更）。

カバー PDF は pdf_merger.rb / print_pdf_builder.rb の `File.join(covers_dir, …)` を
`Common.cover_cache_dir` 基準へ差し替えるだけ（結合処理はパス非依存）。

### 3.2 EPUB / Kindle

- **表紙 JPG**: `resolve_cover_image_path` の探索先を cache へ変更。
  `localize_cover_image!` はパッケージ内 `covers/` へコピーする現行機構のままで、
  コピー元パスの変更のみ。
- **バリアント webp**: 現行はパッケージへの `copy_asset_tree!(stylesheets_dir)` に
  相乗りしている。移設後は **theme-images のローカライズ経路を 1 本追加**する:
  `.cache/vs/theme-images/**` のうち book-settings.css（EPUB 変種）が url() で参照する
  ファイルをパッケージ `theme-images/` へコピーし、url() をパッケージルート基準へ組み替える
  （`../../stylesheets/` → `stylesheets/` の既存 gsub と同型の決定的置換。
  epub_builder.rb の url 解決機構 `theme_css_url_refs` 系に統合）。
- copyAsset / stylesheets コピーのフィルタから `*_portrait/_landscape` 特例が消える。

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

- **生成**: 従来どおり `.cache/vs/covers/frontcover_{theme}_{size}_cmyk.pdf` 等の内部名で
  生成（ビルド内結合・再生成メモ化はこの内部名のまま）。
- **複製**: 生成直後にルート直下へ**コピー**（move ではない。cache 側はビルド結合と
  再利用のため残す）。命名は `Common.generate_output_filename` の規則に倣い
  `{project.name}_frontcover_v{version}.pdf` / `{project.name}_backcover_v{version}.pdf`
  （`include_version` 準拠。専用ヘルパ `generate_cover_output_filename(side)` を追加）。
- **タイミング**: ①`print_pdf` ターゲットを含むビルドで CMYK カバーを生成/確認した時点、
  ②明示 `vs cover a4` 等の実行時（このとき §5-1 の `log_result` でルート側パスを提示）。
  RGB カバー・EPUB 表紙 JPG・SVG 中間物は複製しない（純粋な中間物）。
- **著者事前準備画像の場合も自動で満たされる**: 塗り足し込み著者画像
  `frontcover_master_bleed.png`（`resolve_print_cover_input` が最優先採用）経由でも、
  CMYK PDF 化は vs 側で行うため同じ複製経路に乗る。著者は covers/ を掘らずに
  ルートで入稿一式（本文 print PDF ＋表紙 PDF）が揃う。
  ※現行の入力規約は PNG のみ（`*_bleed.pdf` の直接入力は未サポート・本仕様のスコープ外）。
- ルートの `*.pdf` はグローバル ignore 済みのため .gitignore 追記は不要。
  final clean は `rm_rf BUILD_DIR` のみでルート成果品には触れない（P4 の原則どおり）。

## 4. 変更ファイル一覧

| ファイル | 変更 |
|---|---|
| common.rb | `COVER_CACHE_DIR` / `THEME_IMAGES_CACHE_DIR` ＋ヘルパ追加、`generate_cover_output_filename(side)` 追加 |
| cover.rb | 全生成物の出力先を `cover_cache_dir` へ。CMYK 生成後にルートへ成果品複製（§3.4）＋ `log_result` でパス明示 |
| create.rb | `render_bundled_svg` / `*_rendered.svg` の出力先を cache へ |
| pdf_merger.rb | カバー PDF 読み取り元変更（§5.1 コメントも更新） |
| print_pdf_builder.rb | 同上（CMYK） |
| epub_builder.rb | `resolve_cover_image_path` 変更＋ theme-images ローカライズ追加 |
| image_generator.rb | `ensure_variant_generated` / `target_path` を cache 基準へ |
| theme_image_resolver.rb | 探索順に cache を追加（`find_existing_theme_variant`）、`theme_relative_path` の返却形変更 |
| book_settings_css.rb | url() 生成を `theme-images/…` 相対へ |
| clean.rb | `clean_cover_files` / `clean_bundled_variant_images` → cache dir の `rm_rf` へ縮退（＋§6 の移行掃除） |
| theme.css | 既定 2 行の削除（§3.3） |
| .gitignore | `/covers/` ＋ `!/covers/*.svg` を撤去（`*.pdf` グローバル無視は既存のまま） |
| copy_to_scaffold.rb | バリアント webp PRUNE・covers PRUNE を撤去 |
| docs/specs/vivlioverso-p4-investigation.md | §1.3/§5.1 に本仕様への参照を追記 |

テスト影響: cover 系・clean 系・theme_image_resolver 系・epub cover 系ユニットのパス期待値
更新、`rake test:layout` / `test:targets` での統合確認。`.git/info/exclude` のローカル除外
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

## 7. 実施順序

`print-pdf-derivation-spec.md`（Phase 0〜）と `cover.rb` / `print_pdf_builder.rb` を共有する。
両仕様書は covers/ のパス自体には依存していないが、同時進行はコンフリクトの元。
**推奨順: ①本移設（機械的パス変更が主・単独で完結）→ ②print_pdf 導出化＋dedup →
③カバー ICC 調整**（②③は移設後の安定したパスを土台にする）。
