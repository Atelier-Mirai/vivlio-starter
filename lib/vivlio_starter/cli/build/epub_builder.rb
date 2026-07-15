# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/epub_builder.rb
# ================================================================
# 責務:
#   EPUB 出力に必要な中間ファイルを生成する。
#   - EPUB 専用 entries.js（目次・裏表紙を除外）
#   - EPUB 専用 vivliostyle.config.js（cover / output を EPUB 用に調整）
#
# 仕様書: docs/specs/epub_output_spec.md
#
# 設計方針:
#   - PDF 用の vivliostyle.config.js を直接書き換えず、
#     EPUB 専用の設定ファイル vivliostyle.config.epub.js を生成する。
#   - これにより PDF ビルドへの副作用を完全に排除する。
# ================================================================

require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../entries'
require_relative 'vivliostyle_config_writer'
require_relative 'heading_image_composer'
require_relative '../post_process/html_parser'
require_relative '../pre_process/frontmatter_generator'
require_relative '../pre_process/book_settings_css'

module VivlioStarter
  module CLI
    module Build
      # EPUB ビルド用の中間ファイル生成モジュール
      module EpubBuilder
        # EPUB 専用設定ファイル名
        EPUB_CONFIG_FILE  = 'vivliostyle.config.epub.js'
        # EPUB 専用 entries ファイル名
        EPUB_ENTRIES_FILE = 'entries.epub.js'
        # EPUB デフォルト出力ファイル名
        EPUB_OUTPUT_FILE  = 'output.epub'
        # EPUB へ同梱する book-settings.css の配置先（消費者 dir 直下）。
        # 生成物の正規の置き場は .cache/vs/ だが、EPUB パッケージルート（= 消費者 dir）の
        # 外にあるため、dir 直下へ url() を組み替えた変種をコピーして同梱する（§7.2 → P4 §5.4）。
        EPUB_BOOK_SETTINGS_FILE = 'book-settings.css'

        # EPUB で除外する特殊ページ
        # 目次は EPUB リーダーが自動生成するため不要
        EXCLUDED_BASENAMES = %w[_toc].freeze

        # @page マージンボックス（@bottom-center 等）と @footnote at-rule を検出する正規表現。
        # epubcheck はこれらの構文そのものを CSS-008 ERROR として拒否する
        # （@footnote は Vivliostyle が float: footnote 要素を収めるマージン at-rule）。
        # いずれも 1 段ネスト（`@bottom-center { content: ...; }`）を前提に非貪欲で本体を捕捉する。
        # `margin-bottom` 等のプロパティ名（先頭 @ 無し）には誤マッチしない。
        MARGIN_BOX_PATTERN = /@(?:(?:top|bottom|left|right)-[a-z-]+|footnote)\s*\{[^{}]*\}/

        # @font-face ブロックを検出する正規表現（1 段ネスト前提）。
        # フォント非埋め込み時、EPUB から fonts/ を除外すると src の参照が切れて
        # RSC-007 になるため、EPUB パッケージ内 CSS から @font-face ごと除去する。
        FONT_FACE_PATTERN = /@font-face\s*\{[^{}]*\}/

        # 非埋め込みでも保持する @font-face（keyfont・keyfont_asset? で実体も同梱される）。
        KEYFONT_FACE_PATTERN = /font-family:\s*["']?keyfont\b/i

        # fonts/ 配下を参照する @import を検出する正規表現。
        # page-settings.css は FontManager 生成の `@import url("fonts/google-fonts.css")`
        # を持つ。非埋め込みで fonts/ を除外すると参照切れ（RSC-007）になるため、
        # @font-face とあわせて EPUB 内 CSS から除去する。
        FONT_IMPORT_PATTERN = /@import\s+url\(\s*["']?fonts\/[^"')]+["']?\s*\)\s*;?/

        # インライン <style> 内の `--xxx: url(...webp)...;` 宣言を 1 つ検出する正規表現。
        # WEBP_URL_PATTERN の `[a-zA-Z-]+` はカスタムプロパティ名の数字（例 --h3-marker）で
        # 途中切れし `--h3` 断片を残して CSS-008 を生むため、プロパティ名を `[\w-]+`（数字込み）で
        # 丸ごと拾う専用パターンを用いる（strip_webp_inline_styles_for_kindle! で使用）。
        INLINE_WEBP_DECL_PATTERN = /[\w-]+\s*:\s*[^;{}]*url\([^)]*\.webp[^)]*\)[^;}]*;?/i

        # `url(....webp)` を含む CSS 宣言を 1 つ検出する正規表現（1 宣言＝1 マッチ）。
        # WebP は Kindle の EPUB へ同梱しない（localize_assets! が除外）ため、CSS の
        # `background-image: url(...webp)` や `--frontispiece-image: url(...webp)` が参照切れ
        # （RSC-007 / Kindle W14010）になる。これらの背景はリフロー EPUB で元々描画されない
        # （扉絵/節絵は合成画像へ置換済み）ので、宣言ごと EPUB 内 CSS から除去する。
        # `[^;{}]*` で宣言境界を跨がず、`url(...)` 内は `[^)]*` で 1 つの url に限定する。
        WEBP_URL_PATTERN = /[a-zA-Z-]+\s*:\s*[^;{}]*url\([^)]*\.webp[^)]*\)[^;}]*;?/i

        # techbook の絵文字画像 <img class="... vs-emoji ...">  を検出する正規表現。
        # 絵文字画像化（twemoji SVG 差し替え）は Chromium が PDF で絵文字を Type 3 化する
        # 障害への対策で、PDF 専用。EPUB はリフロー型で Type 3 が存在せず、リーダーの
        # カラー絵文字で描画されるため、EPUB 経路では alt の元絵文字へ戻す（Fix-8）。
        # 囲み数字（vs-circled-number）は alt が数字でアクセント色付き画像のため除外する。
        EMOJI_IMG_PATTERN = /<img\b[^>]*\bclass="[^"]*\bvs-emoji\b[^"]*"[^>]*>/

        module_function

        # ================================================================
        # ワークスペース消費者 dir（P4 段階 4・実験 E2 の確定案）
        # ================================================================
        # EPUB/Kindle はそれぞれ .cache/vs/build/{epub,kindle}/ で完結する。
        # html/ の原本から asset_prefix を剥がしてステージし、参照資産を dir 内へ
        # ローカライズ（選択コピー）することで、entryContext = dir がそのまま
        # EPUB パッケージルートになる（dot-dir 混入が構造的に起こらない・§4-1）。
        # ================================================================

        # html/ の全 HTML を消費者 dir へ展開する（asset_prefix 剥がし）。
        # 剥がした後の参照（stylesheets/… ・images/…）は dir 基準の相対となり、
        # ローカライズされた資産と対応する。章間リンクは同一 dir 内のため不変。
        #
        # @param dir [String] 消費者 dir（BUILD_EPUB_DIR / BUILD_KINDLE_DIR）
        def stage_consumer_htmls!(dir)
          FileUtils.mkdir_p(dir)
          Dir.glob(File.join(Common::BUILD_HTML_DIR, '*.html')).each do |src|
            content = File.read(src, encoding: 'utf-8').gsub(Common::ASSET_PREFIX, '')
            File.write(File.join(dir, File.basename(src)), content, encoding: 'utf-8')
          end
        end

        # EPUB が参照する資産を消費者 dir 内へローカライズする（E2: 選択コピーが必須。
        # copyAsset は entryContext 配下を全同梱するため、「必要物だけを dir に置く」ことが
        # そのままパッケージ内容の選択になる。旧 copyAsset.excludes の知識はここへ移した）。
        # - images/**: _epub_assets/ と headings/ は除外（消費者 dir 内へ直接生成されるため、
        #   ルートの stale な残骸を拾わない）。kindle は WebP も除外（transcode 済み・非対応）。
        # - stylesheets/**: twemoji 直下 svg（絵文字マスター・プレーン復元で未参照）と
        #   フォント実体（非埋め込み時）を除外。kindle は WebP も除外（CSS 参照は sanitize が除去）。
        # - theme-images/**: 生成バリアント webp（生成キャッシュ）のうち book-settings.css が
        #   参照する分を同梱（:epub のみ・移設仕様 §3.2）。
        # - カバー画像: embed 有効時のみ dir/covers/ へコピー（cover は entryContext 基準で解決）。
        #
        # @param dir [String] 消費者 dir
        # @param flavor [Symbol] :epub / :kindle
        def localize_assets!(dir, flavor:)
          copy_asset_tree!(Common.images_dir, dir) { localized_image?(it, flavor) }
          # ビルド生成画像（数式 SVG）は workspace の html/images/ 配下から同梱する（P4b §2.3）。
          # EPUB 内の最終パスは images/math/… でルートの著者画像と同一階層に収まる。
          copy_asset_tree!(File.join(Common::BUILD_HTML_DIR, 'images'), dir, dest_root: 'images') do
            localized_image?(it, flavor)
          end
          copy_asset_tree!(Common.stylesheets_dir, dir) { localized_stylesheet?(it, flavor) }
          localize_theme_variant_images!(dir, flavor)
          localize_cover_image!(dir, flavor)
          Common.log_info("[EPUB] 参照資産を #{dir} 内へローカライズしました（flavor: #{flavor}）")
        end

        # 生成バリアント webp（.cache/vs/theme-images/）を dir/theme-images/ へ同梱する。
        # 旧配置（stylesheets/images/**）では stylesheets コピーへの相乗りで同梱されていたが、
        # 生成キャッシュへの移設で相乗りが消えたため、book-settings.css が url() で参照する
        # 分だけを選択コピーする（キャッシュに溜まった他テーマの変種を運ばない）。
        # url は CSS 位置からの相対のため組替不要（cache 内でもパッケージ内でも
        # 'theme-images/…' のまま解決する・移設仕様 §3.2）。
        # kindle は WebP 非対応で url() ごと sanitize_epub_css! が除去するためスキップする。
        def localize_theme_variant_images!(dir, flavor)
          return if flavor == :kindle

          source = PreProcessCommands::BookSettingsCss.output_path
          return unless File.exist?(source)

          css = File.read(source, encoding: 'utf-8')
          css.scan(%r{url\(\s*["']?(theme-images/[^"')\s]+)["']?\s*\)}).flatten.uniq.each do |rel|
            src = File.join(Common.cache_dir, rel)
            next unless File.exist?(src)

            dest = File.join(dir, rel)
            FileUtils.mkdir_p(File.dirname(dest))
            FileUtils.cp(src, dest)
          end
        end

        # src_root 配下のファイルを、フィルタ（root からの相対パスを yield）を通して
        # dir/dest_root/ へミラーコピーする。dest_root 既定は src_root（cwd 相対の著者資産は
        # そのままの相対階層で dir 下へ接がる）。ワークスペース配下の生成物は src_root が
        # 深い絶対的相対になるため dest_root: 'images' 等で置き場を明示する（P4b §2.3）。
        def copy_asset_tree!(src_root, dir, dest_root: src_root)
          return unless Dir.exist?(src_root)

          Dir.glob(File.join(src_root, '**', '*')).each do |src|
            next unless File.file?(src)

            rel = src.delete_prefix("#{src_root}/")
            next unless yield(rel)

            dest = File.join(dir, dest_root, rel)
            FileUtils.mkdir_p(File.dirname(dest))
            FileUtils.cp(src, dest)
          end
        end

        # images/ 配下でローカライズ対象とするか（rel は images/ からの相対パス）。
        # 図解注釈（showcase）の合成 SVG は元画像を base64 で内包しており Kindle が非対応。
        # localize_showcase_images! が参照を対の PNG へ差し替え済みで未参照になるため、
        # 両フレーバとも同梱しない（パッケージ肥大の防止・explanatory-diagram-spec §7.9）。
        def localized_image?(rel, flavor)
          return false if rel.start_with?("#{EPUB_ASSETS_REL_SUBDIR}/", "#{HEADINGS_REL_SUBDIR}/")
          return false if rel.start_with?("#{SHOWCASE_REL_SUBDIR}/") && rel.match?(/\.svg\z/i)
          return false if flavor == :kindle && rel.match?(/\.webp\z/i)

          true
        end

        # stylesheets/ 配下でローカライズ対象とするか（rel は stylesheets/ からの相対パス）。
        # twemoji 直下 svg は restore_plain_emoji_for_epub! で参照されなくなるため両フレーバで
        # 除外する（vs-techbook/ サブツリーの囲み数字等は同梱維持）。クリーン EPUB（:epub）は
        # WebP を高画質のまま同梱維持する ── EPUB 3.3 では image/webp がコアメディアタイプ（§4）。
        def localized_stylesheet?(rel, flavor)
          return false if rel.match?(%r{\Atwemoji/[^/]+\.svg\z})
          return keyfont_asset?(rel) if rel.start_with?('fonts/') && !embed_fonts?
          return false if flavor == :kindle && rel.match?(/\.webp\z/i)

          true
        end

        # フォント非埋め込みの既定でも同梱する keyfont 資産（kbd キーキャップ描画用 TTF・約 90KB）。
        # 本文フォントと違いリーダー側に代替が存在せず、非同梱だと 〘Ctrl〙 が素の等幅文字へ
        # 落ちるため、この 1 書体だけ実体を運ぶ（sanitize_epub_css! も対の @font-face を保持する）。
        # OTF は PDF の Type 3 回避で TTF へ変換する前の原本なので運ばない（ライセンス表記は
        # gem 同梱の stylesheets/fonts/Keyboard_font/LICENSE* を正とする）。
        def keyfont_asset?(rel)
          rel.start_with?('fonts/Keyboard_font/') && rel.end_with?('.ttf')
        end

        # 表紙埋め込みが有効なフレーバに限り、カバー画像を dir/covers/ へコピーする。
        # config の cover: './covers/…' は entryContext 基準で解決されるため（CLI 実装確認済み）、
        # パッケージに必要なのは埋め込み対象の 1 枚のみ（frontcover/backcover PNG は同梱しない）。
        # コピー元は生成キャッシュ・コピー先は config が指すパッケージ内 covers/ 固定
        # （ソース相対を dest に流用しない・移設仕様 §3.2）。
        def localize_cover_image!(dir, flavor)
          embed = flavor == :kindle ? Common.kindle_embed? : Common.epub_embed?
          return unless embed

          cover = resolve_cover_image_path
          return unless cover && File.exist?(cover)

          dest = File.join(dir, 'covers', File.basename(cover))
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(cover, dest)
        end

        # EPUB 用 entries.js を生成する
        # PDF 用の構成から目次・裏表紙を除外した EPUB 専用エントリを生成
        #
        # @param base_dir [String] ベースディレクトリ
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param flavor [Symbol] :epub（Kobo/Apple Books 向けクリーン）/ :kindle（Amazon 向け劣化）
        # @return [Array<String>] EPUB に含める HTML ファイルパスの配列
        def generate_epub_entries!(base_dir, entries, flavor: :epub)
          Common.log_action("[EPUB] entries.epub.js を生成しています…（flavor: #{flavor}）")

          chapter_htmls = collect_epub_htmls(base_dir, entries)

          if chapter_htmls.empty?
            Common.log_warn('[EPUB] 対象 HTML が見つかりません。スキップします。')
            return []
          end

          # --- Phase: 両フレーバ共通（XHTML 妥当性に必要な最小処理・§1-2）---
          # EPUB リフロー文脈の目印 vs-epub を全 body に付与（クリーン・Kindle 共通）。
          # クリーン EPUB のコード折返し等、PDF を壊さず EPUB だけに効かせる体裁の足場（§6 A 案）。
          mark_body_for_epub!(chapter_htmls)
          # 生成物 book-settings.css を消費者 dir 直下へ同梱（パッケージルート内へ・§7.2 → P4 §5.4）
          bundle_book_settings_for_epub!(chapter_htmls, base_dir)
          # 索引・用語集を EPUB 用に書き換え（空リンクに連番テキストを挿入）
          post_process_index_glossary_for_epub!(chapter_htmls)
          # 段落内脚注 span の重複 id を除去（XHTML の id 重複 ERROR を回避）
          strip_inline_footnote_ids_for_epub!(chapter_htmls)
          # テーブルの align 属性を style へ変換（XHTML5 で廃止された属性の ERROR を回避）
          rewrite_table_align_for_epub!(chapter_htmls)
          # 絵文字画像をプレーン絵文字へ復元（EPUB は Type 3 非該当。twemoji 非同梱で軽量化）
          restore_plain_emoji_for_epub!(chapter_htmls)
          # 扉絵（h1）・節絵（h2）の合成画像を注入。クリーンは高画質 SVG、Kindle は JPEG（§1-2）。
          inject_heading_images_for_epub!(chapter_htmls, flavor:)
          # 図解注釈（showcase）の参照を SVG→PNG へ差し替え（EPUB は SVG 内 base64 を運べない）
          localize_showcase_images!(chapter_htmls)
          # Prism の行番号付き pre を「1 論理行 = 1 ブロック＋ぶら下げインデント」へ変換（F 案・
          # epub-code-line-numbers-spec §2.1）。長行折返しでの番号ずれ（クリーン EPUB）と
          # テーブルセル起因の崩れ（Kindle）を同じ構造で解消するため、両フレーバ共通で行う。
          convert_code_blocks_for_epub!(chapter_htmls)

          # --- Phase: Kindle 専用 rewrite（クリーン EPUB は無改変のまま・§1-2）---
          # Kindle(KFX) は WebP・CSS Grid・position:absolute・var()・外部 CSS の画像サイズを解さない。
          # そこで body.vs-kindle マーカー配下で WebP→JPEG・画像 inline 制約・数式 px 化・
          # コード行番号の実テキスト注入・admonition ラベル注入を行う。クリーン EPUB（:epub）はこれを
          # 一切適用せず、::before 角タブ・var() テーマ色・WebP を維持した高品質 EPUB のままにする。
          if flavor == :kindle
            # 残った <img> 参照 WebP を JPEG/PNG へ変換（<img> の出入り確定後＝扉絵/絵文字処理の後）。
            transcode_webp_images_for_epub!(chapter_htmls)
            # インライン <style> 内の webp url()（Techbook の Type3 対策マーカー）を除去（RSC-007 回避）。
            strip_webp_inline_styles_for_kindle!(chapter_htmls)
            mark_body_for_kindle!(chapter_htmls)
            constrain_layout_images_for_epub!(chapter_htmls)
            convert_math_units_for_epub!(chapter_htmls)
            inject_code_line_numbers_for_kindle!(chapter_htmls)
            decorate_admonitions_for_epub!(chapter_htmls)
          end

          write_epub_entries(base_dir, chapter_htmls)
          Common.log_success("[EPUB] entries.epub.js を生成しました（#{chapter_htmls.size} エントリ・flavor: #{flavor}）")
          chapter_htmls
        end

        # EPUB 専用 vivliostyle.config.js を生成する
        # cover.embed 設定に応じて表紙画像の埋め込みを制御
        #
        # パス表記の規則（実験 E1/E2 で確定・P4 §6.1）:
        #   - entryContext / output / workspaceDir は cwd（プロジェクトルート）相対で書く。
        #     実行 cwd はルート固定。
        #   - entries の path は entryContext 基準（'./xx.html'）。
        #   - cover は entryContext 基準で解決される → ローカライズ済みの 'covers/…' がそのまま通る。
        #   - copyAsset の選択は「dir 内に必要資産だけを置く」ローカライズ（localize_assets!）が担う
        #     ため excludes は不要（E2: copyAsset 既定は entryContext 配下を全同梱）。
        #   - workspaceDir は PDF 用生成 config（VivliostyleConfigWriter）と同じワークスペース内を
        #     指定し、ルートへの一時 .vivliostyle/ 生成をなくす（P4 §5.6・段階 5）。
        #     消費者 dir 内に置くと copyAsset がパッケージへ巻き込むため dir の外へ置く。
        #
        # @param flavor [Symbol] :epub（表紙は book.yml の embed 設定に従う）/ :kindle（embed:false 固定・§1-6）
        # @param dir [String] 消費者 dir（= entryContext・生成先。既定 '.' は単体テスト用）
        # @return [String] 生成されたファイルパス
        def generate_epub_config!(flavor: :epub, dir: '.')
          Common.log_action("[EPUB] vivliostyle.config.epub.js を生成しています…（flavor: #{flavor}）")

          config = Common::CONFIG
          validate_epub_layout_setting!(config, flavor:)

          # JS 文字列に安全に埋め込むための簡易エスケープ
          esc = ->(s) { s.to_s.gsub('\\', '\\\\').gsub("'", "\\'") }

          # メタデータ解決は VivliostyleConfigWriter へ一本化する（P3-4 §2.6）。
          # title は book.title 明示 → main_title + subtitle 合成 → プレースホルダ、
          # author / language は空文字もプレースホルダへ寄せる（vivliostyle 11 の
          # config スキーマが 1 文字以上を要求するため）。規則の二重管理を避け、
          # ルート config・パイプライン config・EPUB config で同一値を保証する。
          title    = VivliostyleConfigWriter.resolve_title
          author   = VivliostyleConfigWriter.resolve_author
          language = VivliostyleConfigWriter.resolve_language

          # ページサイズを解決（vivliostyle.rb から移植）
          page_size = resolve_page_size(config)

          # 表紙画像の埋め込み設定を取得（kindle は二重表紙回避のため embed:false 固定・§1-6）
          cover_line = build_cover_config_line(config, esc, flavor:)

          # 横書き固定（将来の縦書き対応に備えてハードコーディング）
          reading_progression = 'ltr'

          config_content = <<~JS
            import entries from './#{EPUB_ENTRIES_FILE}';

            // @ts-check
            // EPUB 専用設定ファイル（自動生成・編集不要）
            /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
            const vivliostyleConfig = {
              title: '#{esc.call(title)}',
              author: '#{esc.call(author)}',
              language: '#{esc.call(language)}',
              size: '#{esc.call(page_size)}',
              readingProgression: '#{esc.call(reading_progression)}',
              workspaceDir: '#{Common::BUILD_DIR}/.vivliostyle',
              entryContext: '#{esc.call(dir)}',
            #{cover_line}  entry: entries,
              output: [
                '#{esc.call(File.join(dir, EPUB_OUTPUT_FILE))}'
              ]
            };

            export default vivliostyleConfig;
          JS

          config_path = File.join(dir, EPUB_CONFIG_FILE)
          File.write(config_path, config_content)
          Common.log_success("[EPUB] #{config_path} を生成しました")
          config_path
        end

        # book.yml の output.epub.layout / output.kindle.layout を検証する。
        # 現在サポートするのは reflowable（リフロー型）のみ。fixed（固定レイアウト型）は
        # 将来対応の予約値のため、指定されていたら警告して reflowable として続行する
        # （黙って無視すると「設定したのに効かない」事故になるため）。
        def validate_epub_layout_setting!(config, flavor:)
          layout = config.output[flavor]&.layout.to_s.strip.downcase
          return if layout.empty? || layout == 'reflowable'

          Common.log_warn(
            "output.#{flavor}.layout: #{layout} は未対応です。reflowable として出力します",
            detail: "対応: config/book.yml の output.#{flavor}.layout を reflowable に変更してください（fixed は将来対応予定）"
          )
        end

        # EPUB に含める HTML ファイルを収集する
        # PDF 向けの構成から目次・裏表紙を除外
        #
        # @param base_dir [String] ベースディレクトリ
        # @param entries [Array<TokenResolver::Entry>] Entry 配列
        # @return [Array<String>] HTML ファイルパスの配列
        def collect_epub_htmls(base_dir, entries)
          keep_numbers_main = Build::Utilities.chapter_numbers_for_book(entries)
          keep_numbers_appx = nil
          keep_numbers_post = nil

          if entries&.any?
            chapter_numbers = PdfBuilder.send(:extract_chapter_numbers, entries)
            keep_numbers_appx = chapter_numbers.select { |n| PdfBuilder::APPX_RANGE.include?(n) }
            keep_numbers_post = chapter_numbers.select { |n| PdfBuilder::POSTFACE_RANGE.include?(n) }
          end

          # 前書き（00-preface）
          preface_html = [File.join(base_dir, '00-preface.html')].select { File.exist?(it) }

          # 本文章 HTML（中扉を挿入）
          main_htmls = Build::ChapterConfig.htmls_for_range(base_dir, PdfBuilder::MAIN_RANGE, keep_numbers_main)
          main_htmls_with_parts = Build::PartTitleGenerator.insert_part_titles_into(main_htmls, base_dir)

          # 付録
          appx_htmls = Build::ChapterConfig.htmls_for_range(base_dir, PdfBuilder::APPX_RANGE, keep_numbers_appx)

          # 用語集・索引（リフロー型ではページ番号は無意味だがリンクは有効）
          glossary_html = if IndexCommands.index_enabled?
                            [File.join(base_dir, '_glossarypage.html')].select { File.exist?(it) }
                          else
                            []
                          end

          # 後書き
          post_htmls = Build::ChapterConfig.htmls_for_range(base_dir, PdfBuilder::POSTFACE_RANGE, keep_numbers_post)

          # 索引
          index_html = if IndexCommands.index_enabled?
                         [File.join(base_dir, '_indexpage.html')].select { File.exist?(it) }
                       else
                         []
                       end

          # 奥付（書籍の最後尾に置く）。PDF と異なり EPUB ではカバーのみ埋め込むため、
          # 奥付は本文 HTML として明示的に収録しないと EPUB に含まれない。
          colophon_html = [File.join(base_dir, '_colophon.html')].select { File.exist?(it) }

          # 書籍構成順序: 前書き → [中扉+本文] → 付録 → 用語集 → 後書き → 索引 → 奥付
          # ※ 目次（_toc）と裏表紙は除外
          [
            preface_html,
            main_htmls_with_parts,
            appx_htmls,
            glossary_html,
            post_htmls,
            index_html,
            colophon_html
          ].flatten.reject { excluded_basename?(it) }
        end

        # EPUB 用 entries.js をファイルに書き出す。
        # path は entryContext（= base_dir）基準の './xx.html' で書く（E2 の確定案。
        # 全エントリは base_dir 直下にあるため basename がそのまま entryContext 相対になる）。
        #
        # @param base_dir [String] ベースディレクトリ（= 消費者 dir）
        # @param html_files [Array<String>] HTML ファイルパスの配列
        def write_epub_entries(base_dir, html_files)
          entries = html_files.map do |html|
            CLI::EntriesCommands.build_entry(html).merge(path: "./#{File.basename(html)}")
          end

          File.open(File.join(base_dir, EPUB_ENTRIES_FILE), 'w') do |f|
            f.puts 'export default ['
            entries.each_with_index do |entry, i|
              f.puts '  {'
              f.puts %(    "path": "#{entry[:path]}",)
              f.puts %(    "title": "#{entry[:title]}")
              f.puts "  }#{',' if i < entries.length - 1}"
            end
            f.puts ']'
          end
        end

        # 除外対象の basename かどうかを判定する
        #
        # @param html_path [String] HTML ファイルパス
        # @return [Boolean]
        def excluded_basename?(html_path)
          basename = File.basename(html_path, '.html')
          EXCLUDED_BASENAMES.include?(basename)
        end

        # cover 設定行を生成する
        # 新しい設定構造に対応
        #
        # @param config [Object] Common::CONFIG
        # @param esc [Proc] JS エスケープ用 Proc
        # @return [String] cover 設定行（末尾改行付き）
        # EPUB 表紙埋め込みが有効かどうかを判定
        # @param epub_cfg [Object] epub設定オブジェクト（cover.embed を持つ）
        # @return [Boolean]
        def embed_cover?(epub_cfg)
          epub_cfg&.cover&.embed != false
        end

        def build_cover_config_line(config, esc, flavor: :epub)
          # 表紙埋め込みはフレーバごとの設定（book.yml: output.epub.embed / output.kindle.embed）に従う。
          # kindle は二重表紙回避のため既定 false（§1-6）。
          embed = flavor == :kindle ? Common.kindle_embed? : Common.epub_embed?
          unless embed
            key = flavor == :kindle ? 'kindle.embed: false' : 'epub.embed: false'
            return "  // cover: 表紙埋め込みなし（#{key}）\n"
          end

          cover_image = resolve_cover_image_path
          return "  // cover: 表紙画像が見つかりません\n" unless cover_image && File.exist?(cover_image)

          # パッケージ内の固定パスを書く。ソースは生成キャッシュにあり、
          # localize_cover_image! が dir/covers/ 配下の同じ basename へコピーする
          # （ソース相対＝パッケージ相対の偶然一致に依存しない・移設仕様 §3.2）
          "  cover: './covers/#{esc.call(File.basename(cover_image))}',\n"
        end

        # EPUB にフォント実体を埋め込むかどうか。
        # 既定は false（非埋め込み = リーダーのフォントに委ねる）。技術書では
        # 明朝/ゴシック/等幅の generic フォールバック（page-settings.css の --font-*）で
        # 十分なため、サイズ最適化を優先する。
        #
        # NOTE: v2.0 で小説等の執筆に対応する際、book.yml の設定
        # （例: output.epub.embed_fonts）でこの判定を切り替える拡張点。
        # true を返せば fonts/ の同梱と @font-face の保持が復活し、埋め込み EPUB を
        # 生成できる（コード経路は両対応のまま維持してある）。
        #
        # @return [Boolean]
        def embed_fonts?
          false
        end

        # 表紙画像のパスを解決する
        # 生成物 cover JPG は生成資産キャッシュ .cache/vs/covers/ に出る（移設仕様 §3.2）
        #
        # @return [String, nil] 表紙画像の相対パス
        def resolve_cover_image_path
          theme = Common.cover_theme
          return nil unless theme

          # 拡張子は .jpg / .jpeg のどちらでも表紙として受け付ける（.jpg 優先）。
          # 実在する方を返し、いずれも無ければ既定の .jpg パスを返して
          # 呼び出し側に「見つかりません」と判定させる。
          candidates = %w[jpg jpeg].map { File.join(Common.cover_cache_dir, "cover_#{theme}.#{it}") }
          candidates.find { File.exist?(it) } || candidates.first
        end

        # book.yml のページ設定から Vivliostyle CLI 用サイズ文字列を解決する
        # vivliostyle.rb の resolve_vivliostyle_size から移植
        #
        # @param config [Object] Common::CONFIG
        # @return [String] 'A5', 'B5', 'A4', または '148mm 210mm' 形式
        def resolve_page_size(config)
          page_cfg = config.page
          return 'A5' unless page_cfg

          # 版面キーはプリセット由来で存在保証がないため [] で参照する
          size_name = page_cfg[:size].to_s.strip.upcase
          return size_name unless size_name.empty?

          w, h = Common.resolve_page_size(page_cfg.to_h)
          "#{w} #{h}"
        end

        # ================================================================
        # EPUB 用 索引・用語集 後処理
        # ================================================================
        # CSS target-counter() は EPUB リーダーで非対応のため、
        # 空の <a> タグにテキストを挿入して可視化する。
        # PDF ビルド完了後に元ファイルを直接修正する方式。
        # （コピーを作ると本文中の †リンクが _glossarypage.html を参照して切れるため）
        # ================================================================

        # 索引・用語集 HTML を EPUB 用に直接修正する
        # ファイル名プレフィックス（00, 08, 11 等）を書籍構成順の連番（0, 1, 2 等）に変換
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列（書籍構成順）
        # @return [Array<String>] そのままの配列（パス変更なし）
        def post_process_index_glossary_for_epub!(html_files)
          chapter_map = build_sequential_chapter_map(html_files)
          # 索引・用語集の参照先 id が EPUB 内に実在するか照合するための id 集合（RSC-012 恒常対策）
          existing_ids = collect_existing_fragment_ids(html_files)

          html_files.each do |path|
            basename = File.basename(path, '.html')
            case basename
            when '_indexpage'
              rewrite_index_for_epub!(path, chapter_map, existing_ids)
            when '_glossarypage'
              rewrite_glossary_for_epub!(path, chapter_map, existing_ids)
            end
          end
          html_files
        end

        # EPUB に含まれる全 HTML から id 属性値を収集する（RSC-012 恒常対策）。
        # 索引（#idx-…）・用語集バックリンク（#gls-src-…）の参照先が実在するかの照合に使う。
        # epubcheck は当該 EPUB に存在しないフラグメントを指すリンクを RSC-012 ERROR とするため、
        # ここで集めた集合に無い id を指すリンクは rewrite 時に素のテキストへフォールバックする。
        #
        # 重要: 正規表現で `id="…"` を拾うと、コード例として本文に載った
        # `&lt;span id="idx-…"&gt;`（エスケープ済みテキスト）まで実在 id と誤カウントし、
        # 実 DOM には無い id を「実在」と判定して死リンクを温存してしまう（RSC-012 残存）。
        # epubcheck と同じく **実 DOM の要素 id だけ**を数えるため Nokogiri でパースする。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Set<String>] EPUB 内に実在する（要素として存在する）id 値の集合
        def collect_existing_fragment_ids(html_files)
          ids = Set.new
          html_files.each do |path|
            next unless File.exist?(path)

            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            doc.xpath('//*[@id]').each { |node| ids << node['id'] }
          end
          ids
        end

        # 索引・用語集 HTML 内で、参照先フラグメント id が EPUB に実在しないリンクを
        # 素のテキスト（内側の中身）へフォールバックして解除する（RSC-012 恒常対策・付録 A-2）。
        # 索引リンク・用語集バックリンクは中身が空の <a> のため、解除されたリンクは消える。
        # ハッシュ（#）を含まない外部・絶対 URL や、実在 id を指すリンクはそのまま残す。
        #
        # @param html [String] 対象 HTML
        # @param existing_ids [Set<String>] EPUB 内に実在する id 値の集合
        # @return [Array(String, Integer)] [解除後の HTML, 解除したリンク数]
        def unlink_missing_fragment_links(html, existing_ids)
          removed = 0
          updated = html.gsub(%r{<a\b[^>]*\shref="([^"]*)"[^>]*>(.*?)</a>}m) do
            whole = ::Regexp.last_match(0)
            href = ::Regexp.last_match(1)
            inner = ::Regexp.last_match(2)

            fragment = href.split('#', 2)[1]
            # フラグメントを持たないリンク・実在 id へのリンクは温存する
            next whole if fragment.nil? || fragment.empty? || existing_ids.include?(fragment)

            removed += 1
            inner
          end
          [updated, removed]
        end

        # HTML ファイルの構成順から、ファイル名プレフィックス → 連番 のマッピングを構築
        # 例: { "00" => 0, "08" => 1, "11" => 2, "21" => 3, "91" => 4, "99" => 5 }
        #
        # @param html_files [Array<String>] 書籍構成順の HTML ファイルパス
        # @return [Hash{String => Integer}] プレフィックス → 連番
        def build_sequential_chapter_map(html_files)
          mapping = {}
          seq = 0
          html_files.each do |path|
            basename = File.basename(path, '.html')
            next unless basename.match?(/\A\d{2}-/)

            prefix = basename[0, 2]
            unless mapping.key?(prefix)
              mapping[prefix] = seq
              seq += 1
            end
          end
          Common.log_info("[EPUB] 章番号マッピング: #{mapping.map { |k, v| "#{k}→#{v}" }.join(', ')}")
          mapping
        end

        # 索引 HTML を EPUB 用に書き換える
        # - 空リンクに連番の章番号を挿入
        # - 連続するリンク間に ", " 区切りを追加
        #
        # @param path [String] _indexpage.html のパス
        # @param chapter_map [Hash{String => Integer}] プレフィックス → 連番
        # @param existing_ids [Set<String>] EPUB 内に実在する id 値の集合（RSC-012 恒常対策）
        def rewrite_index_for_epub!(path, chapter_map, existing_ids)
          html = File.read(path, encoding: 'utf-8')

          # Step 0: 参照先 id が EPUB に実在しない索引リンクを解除（RSC-012 恒常対策）。
          # 連番挿入・併合より前に行い、死リンクを空 <a> のうちに取り除く。
          html, removed = unlink_missing_fragment_links(html, existing_ids)
          Common.log_info("[EPUB] #{File.basename(path)} の未定義フラグメント索引リンクを #{removed} 件解除しました") if removed.positive?

          # Step 1: 空の <a> タグに連番の章番号を挿入
          html = html.gsub(%r{(<a\s+href="(\d{2})[^"]*"[^>]*)>\s*</a>}) do
            tag_open = ::Regexp.last_match(1)
            prefix = ::Regexp.last_match(2)
            chapter_num = chapter_map[prefix] || prefix.to_i
            "#{tag_open}>#{chapter_num}</a>"
          end

          # Step 2: 同一番号（同一章＝EPUB 上の同一ページ）を指す連続リンクを併合
          html = dedup_sequential_number_links(html)

          # Step 3: 連続する </a><a を </a>, <a に変換（カンマ区切り）
          html = html.gsub(%r{</a>\s*(<a\s+href=")}, '</a>, \1')

          File.write(path, html, encoding: 'utf-8')
          Common.log_info("[EPUB] #{File.basename(path)} を書き換えました（連番リンク＋併合＋区切り挿入）")
        end

        # 用語集 HTML を EPUB 用に書き換える
        # - 空バックリンクに連番の章番号を挿入
        #   CSS の ::before が "→ p." を付加するため記号は不要
        #
        # @param path [String] _glossarypage.html のパス
        # @param chapter_map [Hash{String => Integer}] プレフィックス → 連番
        # @param existing_ids [Set<String>] EPUB 内に実在する id 値の集合（RSC-012 恒常対策）
        def rewrite_glossary_for_epub!(path, chapter_map, existing_ids)
          html = File.read(path, encoding: 'utf-8')

          # RSC-005 是正（§1-8）: <dl class="glossary-list"> 直下のグループ見出し <div> は
          # XHTML5 の dl 内容モデル違反。見出しを <dl> の外（兄弟 <p role=heading>）へ出し、
          # 頭文字ごとに <dl> を分割する。PDF は生成元 HTML をそのまま使うため無影響（EPUB 専用後処理）。
          html = split_glossary_groups_for_epub(html)

          # 参照先 id が EPUB に実在しない用語集バックリンク（#gls-src-…）を解除（RSC-012 恒常対策）。
          # 連番挿入・併合より前に行い、死リンクを空 <a> のうちに取り除く。
          html, removed = unlink_missing_fragment_links(html, existing_ids)
          Common.log_info("[EPUB] #{File.basename(path)} の未定義フラグメントバックリンクを #{removed} 件解除しました") if removed.positive?

          # 空の <a> タグに連番の章番号を挿入
          html = html.gsub(%r{(<a\s+href="(\d{2})[^"]*"[^>]*)>\s*</a>}) do
            tag_open = ::Regexp.last_match(1)
            prefix = ::Regexp.last_match(2)
            chapter_num = chapter_map[prefix] || prefix.to_i
            "#{tag_open}>#{chapter_num}</a>"
          end

          # 同一番号（同一章＝EPUB 上の同一ページ）を指す連続バックリンクを併合
          html = dedup_sequential_number_links(html)

          File.write(path, html, encoding: 'utf-8')
          Common.log_info("[EPUB] #{File.basename(path)} を書き換えました（連番バックリンク＋併合）")
        end

        # 用語集の <dl> 直下のグループ見出し <div> を <dl> の外へ出し、頭文字ごとに <dl> を分割する。
        # 例: <dl><div class="glossary-group-header">A-Z</div><dt>..</dt><dd>..</dd>..</dl>
        #  → <p class="glossary-group-header">A-Z</p><dl><dt>..</dt><dd>..</dd>..</dl>
        # 各見出しで「dl を閉じ → p 見出し → dl を開く」に置換し、先頭に生じる空の <dl> を除去する。
        # 見出しの role/aria-level 属性はそのまま <p> へ引き継ぐ（見た目はクラスセレクタで不変）。
        #
        # @param html [String] 用語集 HTML
        # @return [String] dl を分割した HTML（RSC-005 解消）
        def split_glossary_groups_for_epub(html)
          split = html.gsub(%r{<div class="glossary-group-header"([^>]*)>([^<]*)</div>}) do
            attrs = ::Regexp.last_match(1)
            label = ::Regexp.last_match(2)
            %(</dl>\n<p class="glossary-group-header"#{attrs}>#{label}</p>\n<dl class="glossary-list">)
          end
          # 先頭の見出し置換で生じる空の <dl></dl> を取り除く
          split.gsub(%r{<dl class="glossary-list">\s*</dl>\s*}, '')
        end

        # 索引・用語集の連番リンクのうち、同一番号（= 同一章 = EPUB 上の同一ページ扱い）を
        # 指す連続リンクを最初の 1 つに併合する。PDF のページ番号併合（Step 8 の backlink
        # dedup）に相当する処理を、EPUB の章連番に対して文字列処理で行う。
        # 番号挿入後・カンマ区切り挿入前に適用する想定。空白区切りで隣接する
        # <a ...>N</a> の連なりを対象とし、各連なり内で番号が初出のリンクだけを残す。
        #
        # @param html [String] 番号挿入済みの索引/用語集 HTML
        # @return [String] 同番号リンクを併合した HTML
        def dedup_sequential_number_links(html)
          html.gsub(%r{(?:<a\s[^>]*>\d+</a>\s*){2,}}) do |run|
            links = run.scan(%r{<a\s[^>]*>\d+</a>})
            # 番号（章連番）が初出のリンクだけを順序保持で残す
            links.uniq { |link| link[%r{>(\d+)</a>\z}, 1] }.join(' ')
          end
        end

        # ================================================================
        # EPUB 用 脚注 id 重複の解消
        # ================================================================
        # footnote_converter は段落内脚注に対し span（画面用）と aside（印刷用）へ
        # 同一 id を意図的に付与する（PDF の脚注二重描画回避。PDF 経路では変更禁止）。
        # XHTML では同一文書内の id 重複が ERROR になるため、EPUB 経路でのみ
        # span 側の id を除去して aside 側に一意化する。
        # 画面メディアでは span は display:none のため表示への影響はない。
        # ================================================================

        # 段落内脚注 span（page-footnote-inline）の id 属性のみを除去する
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def strip_inline_footnote_ids_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            stripped = html.gsub(
              %r{(<span\b[^>]*\bpage-footnote-inline\b[^>]*?)\s+id="[^"]*"},
              '\1'
            )
            next if stripped == html

            File.write(path, stripped, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} の脚注 span id を除去しました")
          end
          html_files
        end

        # ================================================================
        # EPUB 用 テーブル align 属性の変換
        # ================================================================
        # VFM はテーブル列の整列（|:--| 等）を <th align="left"> という
        # 廃止済みプレゼンテーション属性で出力する。XHTML5 では align 属性は
        # 不許可で epubcheck の RSC-005 ERROR になるため、EPUB 経路でのみ
        # style="text-align:..." へ変換する。PDF（Vivliostyle）は align を
        # 許容するため PDF 経路は従来どおり（共有 HTML の書き換えは Step E =
        # PDF 完成後のため安全）。
        # ================================================================

        # th/td の align 属性を style の text-align へ変換する
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def rewrite_table_align_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            rewritten = html.gsub(/<t[hd]\b[^>]*\salign="(?:left|center|right|justify)"[^>]*>/) do
              convert_cell_align_to_style(it)
            end
            next if rewritten == html

            File.write(path, rewritten, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} のテーブル align 属性を style へ変換しました")
          end
          html_files
        end

        # 1 つの th/td 開始タグ内で align 属性を除去し、text-align を style に統合する。
        # align と style の属性順序に依存しないようタグ全体を受け取って組み立て直す
        # （部分捕捉だと捕捉範囲外に style が残り、style 属性が二重になるため）。
        #
        # @param tag [String] '<th align="left">' のような開始タグ全体
        # @return [String] 変換後のタグ
        def convert_cell_align_to_style(tag)
          value = tag[/\salign="(left|center|right|justify)"/, 1]
          stripped = tag.sub(/\salign="(?:left|center|right|justify)"/, '')

          if stripped.match?(/\sstyle="/)
            stripped.sub(/\sstyle="/, %( style="text-align:#{value};))
          else
            stripped.sub(/\A(<t[hd]\b)/, %(\\1 style="text-align:#{value}"))
          end
        end

        # ================================================================
        # EPUB 用 絵文字プレーン復元
        # ================================================================
        # techbook の絵文字画像化（EmojiReplacer）は PDF の Type 3 障害対策で、
        # EPUB には不要（EPUB に Type 3 は存在せずリーダーのカラー絵文字で描画される）。
        # EPUB 経路でのみ <img class="... vs-emoji ...">  を alt の元絵文字へ戻し、
        # twemoji 画像の同梱を不要にして軽量化する（localize_assets! が
        # stylesheets/twemoji 直下 svg を除外）。囲み数字（vs-circled-number）は alt が数字で
        # 字形・アクセント色を保てないため画像のまま残す。
        # ================================================================

        # 絵文字 <img> を alt の絵文字テキストへ復元する（vs-circled-number は除く）
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def restore_plain_emoji_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            restored = html.gsub(EMOJI_IMG_PATTERN) do |tag|
              # 囲み数字は数字 alt・アクセント色付き画像のため画像のまま維持する
              next tag if tag.include?('vs-circled-number')

              tag[/\salt="([^"]*)"/, 1] || tag
            end
            next if restored == html

            File.write(path, restored, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} の絵文字をプレーン文字へ復元しました")
          end
          html_files
        end

        # ================================================================
        # EPUB 用 扉絵（h1）・節絵（h2）の合成画像注入（③-a）
        # ================================================================
        # PDF は @page 背景＋固定寸法で扉絵を全面描画するが、リフロー型 EPUB は
        # 背景・固定寸法・重ね合わせが（特に Kindle で）描画されない。そこで EPUB
        # 経路でのみ、飾り画像＋見出しを 1 枚に焼き込んだ合成画像（HeadingImageComposer
        # が SVG を組み JPEG にラスタライズ）を <img> として見出しに差し込む。
        # Kindle は SVG 内 base64 を非対応のため SVG ではなくフラット JPEG を配る。
        # 目次（nav）は各章の <title> から生成され h1 テキストに依存しないため、見出しを
        # 画像へ置換しても目次は壊れない（見出しテキストは <img alt> に保持）。
        # PDF 完成後に共有 HTML を書き換えるため PDF 経路へ副作用はない（Step E）。
        # ================================================================

        # 合成画像の出力先（images/headings/）。クリーン対象（clean.rb）。
        HEADINGS_REL_SUBDIR = 'headings'

        # 扉絵・節絵を合成画像として見出しに焼き込む（theme.style=image のときのみ）。
        # 画像解決や合成に失敗したファイルは注入をスキップし simple 相当へ縮退する（§B-5）。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def inject_heading_images_for_epub!(html_files, flavor: :epub)
          return html_files unless Common::CONFIG.theme.style == 'image'

          theme = read_theme_heading_assets
          return html_files unless theme

          context = {
            frontispiece: theme[:frontispiece],
            ornament: theme[:ornament],
            font_family: epub_heading_font_family,
            number_color: theme[:number_color],
            flavor:
          }

          html_files.each { |path| inject_heading_images_into_file!(path, context) }
          html_files
        end

        # 図解注釈（showcase）の生成物サブディレクトリ（images/showcase/）。
        SHOWCASE_REL_SUBDIR = 'showcase'

        # 図解注釈の <img> 参照を合成 SVG からラスターへ差し替える（explanatory-diagram-spec §7.9）。
        # 合成 SVG は元画像を base64 data URI で内包しており、Kindle はこれを非対応
        # （変換時ブロッキングエラー）。前処理が SVG とラスターを必ず対で焼き、参照先を
        # data-vs-raster に明示しているため、ここは参照の書き換えだけで済む（形式は元画像が
        # 写真か否かで png / jpg に分かれるので、拡張子は推測せず属性の値をそのまま使う）。
        # 同梱側は localized_image? が showcase の .svg を弾くので、未参照 SVG がパッケージへ
        # 紛れ込むこともない（クリーン EPUB も同じラスターを使い、両フレーバで見た目を揃える）。
        # ラスター実体が無い場合（通常起きない）は参照を変えず警告に留める。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def localize_showcase_images!(html_files)
          html_files.each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            images = doc.css('img.vs-showcase[data-vs-raster]')
            next if images.empty?

            images.each { |img| localize_showcase_image!(img, path) }
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の図解注釈 #{images.size} 件をラスター参照へ差し替えました")
          end
          html_files
        end

        # <img> 1 つを data-vs-raster の参照へ差し替え、EPUB に不要な同属性を取り除く。
        # 実体確認は消費者 dir ではなく生成元（html/images/showcase/）に対して行う——
        # 資産のローカライズ（localize_assets!）はこの書き換えより後に走るため、
        # この時点の消費者 dir にはまだ画像が置かれていない。
        def localize_showcase_image!(img, html_path)
          raster = img['data-vs-raster'].to_s
          img.remove_attribute('data-vs-raster')

          if raster.empty? || !File.exist?(File.join(Common::BUILD_HTML_DIR, raster))
            Common.log_warn(
              "[EPUB] 図解注釈のラスター画像が見つかりません: #{raster}",
              detail: "→ #{File.basename(html_path)} は SVG 参照のまま出力します（Kindle では表示されない可能性があります）"
            )
            return
          end

          img['src'] = raster
        end

        # 扉絵・節絵の実画像パスと節番号色を取得する。
        # PDF と同一画像を単一の参照元から使う（二重解決を避ける・§B-4）。
        #
        # P3 以降、theme.css は読み取り専用のテーマ資産となり book.yml の設定は
        # book-settings.css へ書き出されるため、theme.css の正規表現読みでは設定変更を
        # 拾えず既定値に化ける（調査報告 §7.1）。そこで生成器と同じ参照元
        # （parse_theme_settings の計算値）を直接使う。節番号色（--section-number-color）は
        # in-place 版でも書換対象外で常に var(--theme-accent) だったため、book.yml で選ばれた
        # theme accent を、パレット定義（theme.css の --accent-* は P3 でも不変）で具体色へ解決する。
        #
        # @return [Hash, nil] { frontispiece:, ornament:, number_color: }。解決不能時は nil
        def read_theme_heading_assets
          settings = PreProcessCommands::FrontmatterGenerator.parse_theme_settings
          theme_css_path = File.join(Common::STYLESHEETS_DIR, 'theme.css')
          palette_css = File.exist?(theme_css_path) ? File.read(theme_css_path, encoding: 'utf-8') : ''

          {
            frontispiece: resolve_theme_image_file(theme_image_rel(settings[:frontispiece_path])),
            ornament: resolve_theme_image_file(theme_image_rel(settings[:ornament_path])),
            number_color: resolve_css_color(palette_css, settings[:theme_accent_value])
          }
        rescue StandardError => e
          Common.log_warn("[EPUB] テーマ設定の読み取りに失敗（扉絵の画像化をスキップ）: #{e.message}")
          nil
        end

        # テーマ画像の解決結果（素の相対パス or url(...) or 外部 URL）から
        # stylesheets/ 基準の相対パスを取り出す。url(...) 形式ならその内側を返す。
        def theme_image_rel(value)
          v = value.to_s.strip
          return v unless v.start_with?('url(')

          v[/\Aurl\(\s*["']?(.*?)["']?\s*\)\z/i, 1].to_s
        end

        # 生成物 book-settings.css を EPUB へ同梱する（調査報告 §7.2 → P4 §5.4）。
        # 正規の置き場 .cache/vs/ はパッケージルート（= 消費者 dir）の外のため、link を
        # そのままにすると RSC-007（参照切れ）になる。消費者 dir 直下へ変種をコピーし、
        # 章 HTML の link href をその相対（book-settings.css）へ書き換える。dir 直下 CSS からは
        # 画像相対が stylesheets/ 基準へ変わるため url() も組み替える。Kindle の webp url() 除去や
        # マージンボックス除去は sanitize_epub_css! が同梱後の CSS へ自動適用する。
        #
        # @param html_files [Array<String>] 章 HTML パスの配列
        # @param base_dir [String] 消費者 dir（変種 CSS の配置先）
        # @return [Array<String>] そのままの配列
        def bundle_book_settings_for_epub!(html_files, base_dir)
          source = PreProcessCommands::BookSettingsCss.output_path
          # ステージ済み HTML の link href は asset_prefix 剥がし後の cwd 相対（= source と同値）
          src_href = source

          unless File.exist?(source)
            Common.log_warn("[EPUB] #{source} が見つかりません。book-settings.css の link を除去します。")
            strip_book_settings_link!(html_files, src_href)
            return html_files
          end

          # .cache/vs/ 基準（../../stylesheets/）→ パッケージルート基準（stylesheets/）へ url() を組替
          css = File.read(source, encoding: 'utf-8').gsub('../../stylesheets/', 'stylesheets/')
          File.write(File.join(base_dir, EPUB_BOOK_SETTINGS_FILE), css, encoding: 'utf-8')

          rewrote = html_files.count do |path|
            html = File.read(path, encoding: 'utf-8')
            updated = html.gsub(src_href, EPUB_BOOK_SETTINGS_FILE)
            next false if updated == html

            File.write(path, updated, encoding: 'utf-8')
            true
          end
          Common.log_success("[EPUB] book-settings.css を同梱しました（#{rewrote} エントリの link を書換）")
          html_files
        end

        # book-settings.css が無い異常時に、参照切れを避けるため link 要素を除去する。
        def strip_book_settings_link!(html_files, href)
          pattern = /[ \t]*<link\b[^>]*href="#{Regexp.escape(href)}"[^>]*>\s*\n?/
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            updated = html.gsub(pattern, '')
            File.write(path, updated, encoding: 'utf-8') unless updated == html
          end
        end

        # テーマ画像の url(...) 値を実ファイルパスへ解決する。
        # 生成バリアント（theme-images/…）は生成キャッシュ基準、それ以外（images/…）は
        # stylesheets/ 基準で解決する（返却 2 形・移設仕様 §3.1/§3.2）。
        #
        # @param rel [String, nil] 例: "theme-images/bundled/sakura_portrait.webp" / "images/mypic.webp"
        # @return [String, nil] 存在する実ファイルパス、無ければ nil
        def resolve_theme_image_file(rel)
          return nil if rel.nil? || rel.strip.empty?
          return nil if rel.start_with?('data:', 'http://', 'https://')

          path = if rel.start_with?('theme-images/')
                   File.join(Common.cache_dir, rel)
                 else
                   File.join(Common::STYLESHEETS_DIR, rel)
                 end
          File.exist?(path) ? path : nil
        end

        # CSS 色値を具体色へ解決する。var(--theme-accent) → var(--accent-yellow) → #f0a000 の
        # 連鎖を theme.css 内の定義から辿る。解決できなければ既定のダークを返す。
        #
        # @param css [String] theme.css 全文
        # @param value [String, nil] --section-number-color の値
        # @return [String] 具体的な CSS 色
        def resolve_css_color(css, value, depth = 0)
          v = value.to_s.strip
          return '#333333' if v.empty? || depth > 5

          if (m = v.match(/\Avar\(\s*(--[a-z0-9-]+)\s*\)\z/i))
            referenced = css[/#{Regexp.escape(m[1])}:\s*([^;]+);/, 1]
            return resolve_css_color(css, referenced, depth + 1)
          end

          v
        end

        # EPUB の見出し <text> 用フォントスタック（フォント非埋め込み・§B-3）。
        # book の見出しフォントを先頭に、リーダー標準の和文 sans フォールバックを併記する。
        # SVG 属性内に直接入れるため各名は単一引用符で囲む（属性は二重引用符）。
        #
        # @return [String]
        def epub_heading_font_family
          book_font = Common::CONFIG.typography.heading.font.to_s.strip
          stack = []
          stack << "'#{book_font}'" unless book_font.empty?
          stack.concat(["'Hiragino Sans'", "'Hiragino Kaku Gothic ProN'", "'Noto Sans JP'",
                        "'Noto Sans CJK JP'", 'sans-serif'])
          stack.join(', ')
        end

        # 1 ファイルの h1（扉絵）・h2（節絵）へ合成画像を注入する。
        # 本文章（番号 1..89）のみが対象。付録・前付・後付は simple 版とする（§B-4・PDF と整合）。
        def inject_heading_images_into_file!(path, context)
          return unless main_chapter_file?(path)

          # 合成画像は HTML と同じ消費者 dir 配下（images/headings/）へ生成する（P4 §5.2-b）
          context = context.merge(base_dir: File.dirname(path))

          html = File.read(path, encoding: 'utf-8')
          doc = PostProcessCommands::HtmlParser.parse_html_document(html)

          changed = false
          changed |= inject_frontispiece_headings!(doc, context)
          changed |= inject_ornament_headings!(doc, context)
          return unless changed

          PostProcessCommands::HtmlParser.save_html_document(path, doc)
          Common.log_info("[EPUB] #{File.basename(path)} に扉絵/節絵の合成画像を注入しました")
        rescue StandardError => e
          Common.log_warn("[EPUB] #{File.basename(path)} の扉絵注入に失敗（simple 縮退）: #{e.message}")
        end

        # 本文章（ファイル名の番号が 1..89）か。付録(90-98)・前付(00)・後付(99)・
        # 特殊ページ（_toc 等）は対象外として simple 版にする。
        def main_chapter_file?(path)
          base = File.basename(path)
          (m = base.match(/\A(\d{2})-/)) ? PdfBuilder::MAIN_RANGE.include?(m[1].to_i) : false
        end

        # 章扉（data-chapter-number-display を持つ h1）に扉絵画像を注入する。
        # 扉絵は上下 2 分割で運ぶ（FRONTISPIECE_SPLIT）: h1 には「飾り上部＋番号＋タイトル」の
        # 上側を、直後の chapter-lead の後ろには文字なしの裾飾りを置き、PDF の
        # 「見出し → リード → 裾の飾り」という読み順をリフローでも再現する（epub_chapter5 実測）。
        def inject_frontispiece_headings!(doc, context)
          return false unless context[:frontispiece]

          changed = false
          doc.css('h1').each do |h1|
            number = h1['data-chapter-number-display'].to_s.strip
            next if number.empty?

            title = h1['data-chapter-title'].to_s.strip
            src = heading_image_src(
              image_path: context[:frontispiece], number:, title:, kind: :frontispiece,
              font_family: context[:font_family], flavor: context[:flavor], base_dir: context[:base_dir]
            )
            next unless src

            apply_image_heading!(h1, src, [number, title], doc)
            inject_frontispiece_tail!(h1, doc, context)
            changed = true
          end
          changed
        end

        # 扉絵の裾飾り（文字なし）を chapter-lead の直後へ注入する。
        # リードが無い章は h1 の直後に置く。合成失敗時は注入しない（上側だけでも成立する）。
        def inject_frontispiece_tail!(h1, doc, context)
          src = heading_image_src(
            image_path: context[:frontispiece], number: '', title: '', kind: :frontispiece_tail,
            font_family: context[:font_family], flavor: context[:flavor], base_dir: context[:base_dir]
          )
          return unless src

          anchor = h1.next_element&.[]('class').to_s.split.include?('chapter-lead') ? h1.next_element : h1
          return if anchor.next_element&.[]('class').to_s.split.include?('vs-frontispiece-tail') # 冪等

          img = Nokogiri::XML::Node.new('img', doc)
          img['class'] = 'vs-frontispiece-tail'
          img['src'] = src
          img['alt'] = '' # 純装飾（読み上げ対象にしない）
          anchor.add_next_sibling(img)
        end

        # 節扉（article.section-topic 直下の h2）に節絵画像を注入する。
        def inject_ornament_headings!(doc, context)
          return false unless context[:ornament]

          changed = false
          doc.css('article.section-topic > h2').each do |h2|
            number = h2['data-section-number-display'].to_s.strip
            title  = h2['data-section-title'].to_s.strip
            next if number.empty? && title.empty?

            src = heading_image_src(
              image_path: context[:ornament], number:, title:, kind: :ornament,
              font_family: context[:font_family], number_color: context[:number_color],
              flavor: context[:flavor], base_dir: context[:base_dir]
            )
            next unless src

            apply_image_heading!(h2, src, [number, title], doc)
            mark_section_topic_for_epub!(h2)
            changed = true
          end
          changed
        end

        # 見出し要素の中身を合成画像 <img> へ置換する。
        # 目次（nav）は各章 HTML の <title> から生成され h1 テキストに依存しないため、
        # 見出しテキストは <img alt> に格納する（読み上げ・検索・画像非表示時のフォールバック）。
        def apply_image_heading!(heading, src, segments, doc)
          label = segments.reject(&:empty?).join(' ')

          heading.children.remove
          add_class(heading, 'vs-image-heading-epub')

          img = Nokogiri::XML::Node.new('img', doc)
          img['class'] = 'vs-image-heading-img'
          img['src'] = src
          img['alt'] = label
          heading.add_child(img)
        end

        # 節絵を入れた h2 の親 article.section-topic に EPUB 用クラスを付け、
        # PDF 用の固定寸法グリッド（150px 行など）を components.css で解除できるようにする。
        def mark_section_topic_for_epub!(h2)
          article = h2.parent
          add_class(article, 'vs-section-topic-epub') if article && article['class'].to_s.split.include?('section-topic')
        end

        # 合成画像を生成・キャッシュし、HTML から参照する相対パスを返す。
        # クリーン EPUB（:epub）は高画質の合成 SVG（base64 画像を内包）をそのまま配り、
        # Kindle（:kindle）は SVG 内 base64 を非対応のため平坦 JPEG へラスタライズして配る（§1-2）。
        # 入力（フレーバ・種別・画像・番号・タイトル・フォント・色）のハッシュをファイル名にして
        # 同一見出しを使い回す。フレーバを鍵に含め SVG/JPEG のキャッシュ衝突を避ける。
        # 出力先は base_dir（消費者 dir）配下の images/headings/（著者 dir を汚さない・P4 §5.2-b）。
        # ツール不在・合成失敗時は nil（→ simple 縮退）。
        def heading_image_src(image_path:, number:, title:, kind:, font_family:,
                              number_color: '#333333', flavor: :epub, base_dir: '.')
          key = Digest::SHA256.hexdigest([flavor, kind, image_path, number, title, font_family, number_color].join('|'))[0, 16]
          dir = File.join(base_dir, Common.images_dir, HEADINGS_REL_SUBDIR)
          filename = "#{kind}-#{key}.#{flavor == :kindle ? 'jpg' : 'svg'}"
          abs = File.join(dir, filename)

          unless File.exist?(abs)
            data = if flavor == :kindle
                     HeadingImageComposer.render(image_path:, number:, title:, kind:, font_family:, number_color:)
                   else
                     HeadingImageComposer.compose(image_path:, number:, title:, kind:, font_family:, number_color:)
                   end
            return nil unless data

            FileUtils.mkdir_p(dir)
            File.binwrite(abs, data)
          end

          "#{Common.images_dir}/#{HEADINGS_REL_SUBDIR}/#{filename}"
        end

        # 要素へ CSS クラスを追加（重複は付けない）。
        def add_class(node, klass)
          classes = node['class'].to_s.split
          return if classes.include?(klass)

          node['class'] = (classes << klass).join(' ')
        end

        # ================================================================
        # EPUB 用 WebP → JPEG/PNG トランスコード（§5-1）
        # ================================================================
        # Kindle は WebP 非対応のため、EPUB の <img> 参照 WebP を JPEG/PNG へ変換し
        # src を差し替える（docs/specs/epub-kindle-webp-transcode-spec.md）。PDF 経路は
        # WebP のまま（無影響）。出力は images/_epub_assets/<hash>.{jpg,png} に集約し、
        # 元の png/jpg ソースの上書き・問題のあるファイル名（アポストロフィ等）の同梱を
        # 同時に避ける。CSS 背景の WebP は EPUB で描画されないため対象外（除外する）。
        # 劣化方針: 元画像が残っていれば WebP を経由せず元から変換（二重劣化回避）。
        # 出力形式: 透過/可逆は PNG（無劣化）、不透過写真は JPEG(q90)。
        # ================================================================

        # EPUB 用トランスコード出力の集約サブディレクトリ（images/ 配下）。クリーン対象（clean.rb）。
        EPUB_ASSETS_REL_SUBDIR = '_epub_assets'

        # EPUB 用画像の長辺上限（px）。WebP は既に最適化済みだが、元画像から変換する場合の
        # 肥大化を防ぐためここでも上限を掛ける（medium プリセット既定相当）。
        EPUB_IMAGE_MAX_EDGE = 1600

        # 各 HTML の <img src="*.webp"> を JPEG/PNG へ変換し src を差し替える。
        # 変換結果はソース src 文字列でメモ化し、同一画像の重複変換を避ける。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def transcode_webp_images_for_epub!(html_files)
          cache = {}
          html_files.each { |path| transcode_webp_in_file!(path, cache) }
          html_files
        end

        # 1 ファイル分の <img> WebP 参照を変換・差し替える。
        def transcode_webp_in_file!(path, cache)
          html = File.read(path, encoding: 'utf-8')
          changed = false

          updated = html.gsub(/<img\b[^>]*>/i) do |tag|
            src = tag[/\ssrc="([^"]*)"/i, 1]
            next tag unless src&.match?(/\.webp\z/i)

            staged = cache.fetch(src) { cache[src] = stage_webp_replacement(src, File.dirname(path)) }
            next tag unless staged

            changed = true
            tag.sub(/(\ssrc=")[^"]*(")/i, "\\1#{staged}\\2")
          end
          return unless changed

          File.write(path, updated, encoding: 'utf-8')
          Common.log_info("[EPUB] #{File.basename(path)} の WebP 画像を JPEG/PNG へ差し替えました")
        end

        # src の WebP を変換し、staging の相対パスを返す。変換不能なら nil（src 据え置き）。
        # 変換元は cwd（ルート）の著者資産を読み、出力は base_dir（消費者 dir）配下の
        # images/_epub_assets/ に置く（著者 dir を汚さない・P4 §5.3）。
        def stage_webp_replacement(src_attr, base_dir)
          webp_path = decode_html_entities(src_attr)
          # 著者資産（cwd 相対）で見つからない場合はワークスペース生成物（html/images/data/ 等）を
          # フォールバックで探す。DataImageResolver が置いた data 画像は cwd に実体が無い（spec §3.5）。
          unless File.exist?(webp_path)
            candidate = File.join(Common::BUILD_HTML_DIR, webp_path)
            webp_path = candidate if File.exist?(candidate)
          end
          return nil unless File.exist?(webp_path)

          source = transcode_source_for(webp_path)
          ext = epub_image_extension_for(source)
          key = Digest::SHA256.hexdigest(
            [File.expand_path(source), File.mtime(source).to_i, ext].join('|')
          )[0, 16]

          dir = File.join(base_dir, Common.images_dir, EPUB_ASSETS_REL_SUBDIR)
          abs = File.join(dir, "#{key}.#{ext}")
          rel = "#{Common.images_dir}/#{EPUB_ASSETS_REL_SUBDIR}/#{key}.#{ext}"
          return rel if File.exist?(abs)

          FileUtils.mkdir_p(dir)
          convert_image_for_epub(source, abs, ext) ? rel : nil
        rescue StandardError => e
          Common.log_warn("[EPUB] WebP 変換に失敗（#{src_attr}）: #{e.message}")
          nil
        end

        # 変換元を決める。同名の元画像（png/jpg）が残っていれば二重劣化回避のため優先する。
        def transcode_source_for(webp_path)
          base = webp_path.sub(/\.webp\z/i, '')
          %w[.png .jpg .jpeg].each do |ext|
            candidate = "#{base}#{ext}"
            return candidate if File.exist?(candidate)
          end
          webp_path
        end

        # EPUB 用の出力拡張子を決める。透過/PNG/可逆 WebP は PNG（無劣化）、それ以外は JPEG。
        def epub_image_extension_for(source)
          return 'png' if File.extname(source).casecmp?('.png')
          return 'png' if image_has_alpha?(source)
          return 'png' if webp_lossless?(source)

          'jpg'
        end

        # 画像がアルファチャンネルを持つか（magick identify %A）。判定不能時は false。
        def image_has_alpha?(path)
          out, status = Open3.capture2('magick', 'identify', '-format', '%A', path)
          status.success? && %w[true blend].include?(out.strip.downcase)
        rescue StandardError
          false
        end

        # WebP が可逆圧縮か（magick identify -verbose の Compression 行）。webp 以外は false。
        def webp_lossless?(path)
          return false unless File.extname(path).casecmp?('.webp')

          out, status = Open3.capture2('magick', 'identify', '-verbose', path)
          status.success? && out.match?(/Compression:\s*Lossless/i)
        rescue StandardError
          false
        end

        # 変換元 → 出力（JPEG は白フラット化、PNG は透過保持）。成否を返す。
        def convert_image_for_epub(source, dest, ext)
          cmd = if ext == 'png'
                  ['magick', source, '-resize', "#{EPUB_IMAGE_MAX_EDGE}x#{EPUB_IMAGE_MAX_EDGE}>", '-strip', dest]
                else
                  ['magick', source, '-background', 'white', '-flatten',
                   '-resize', "#{EPUB_IMAGE_MAX_EDGE}x#{EPUB_IMAGE_MAX_EDGE}>", '-strip', '-quality', '90', dest]
                end
          system(*cmd, out: File::NULL, err: File::NULL)
        rescue StandardError
          false
        end

        # HTML 実体参照をデコードしてディスク上のパスへ戻す（&apos; を含む src の解決・§5-4）。
        # &amp; は最後に展開し二重デコードを避ける。
        def decode_html_entities(str)
          str.gsub('&apos;', "'").gsub('&quot;', '"').gsub('&lt;', '<').gsub('&gt;', '>').gsub('&amp;', '&')
        end

        # ================================================================
        # EPUB 用 Kindle レイアウト是正（epub-kindle-layout-spec.md）
        # ================================================================
        # Kindle のリフローは CSS Grid / position:absolute / ex 単位を解さないため、
        # PDF 向け CSS のままだと画像・数式・コード行番号が崩れる。EPUB 経路でのみ
        # 是正する。CSS で済むもの（book-card / img-text の画像上限）は body.vs-kindle
        # ガードの CSS（components.css / layout-utils.css / code.css）に置き、ここでは
        # マークアップ変更が要る 3 件（body マーカー付与・数式 ex→em・コードのテーブル化）を
        # 行う。PDF 完成後の共有 HTML を書き換えるため PDF へ副作用はない。
        # ================================================================

        # ex→em の換算係数。CSS 慣用の 1ex ≈ 0.5em（MathJax SVG の ex/em 比の近似）。
        # 端末フォント非依存の近似で、EPUB の本文サイズに収めるには十分（§3-2）。
        EX_TO_EM = 0.5

        # 表セル内の数式（単位記号など）の最低高さ（em）。Kindle は多列の表を縮小しがちで、
        # ×0.5 だと単位記号が読めなくなるため、表内に限り最低この高さを確保し等比拡大する。
        MIN_TABLE_MATH_EM = 1.0

        # EPUB の基準フォント px（1em の近似）。数式 SVG は固有寸法を持たないため、Kindle が
        # inline の em/ex を無視すると img 既定の 300×150px で巨大表示される。これを防ぐため
        # em 値 × この係数を width/height の HTML 属性（px）として与え、Kindle でも本文相当に固定する。
        EPUB_BASE_FONT_PX = 16

        # 各 EPUB 章 HTML の <body> に vs-kindle クラスを付与する。
        # body.vs-kindle ガードの CSS（画像上限・コードテーブル体裁等）を効かせるための目印。
        # PDF 用 HTML には付かないため PDF では当該 CSS が不発で無害。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def mark_body_for_kindle!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)
            body = doc.at_css('body')
            next unless body

            add_class(body, 'vs-kindle')
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
          end
          html_files
        end

        # Kindle 専用: 章 HTML のインライン <style> 内の webp url() 宣言を除去する（RSC-007 回避）。
        # Techbook が PDF の Type3 対策で head に注入する :root{ --h3-marker: url(...webp) } 等は、
        # Kindle では WebP を同梱しない（localize_assets! が除外）ため参照切れになる。
        # Kindle は var() も解さずこのマーカーを描画しないので、宣言ごと除去して無害化する。
        # sanitize_epub_css! は EPUB 内の .css ファイルが対象でインライン <style> は拾わないため、
        # ここで章 HTML の <style> ブロックを処理する。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def strip_webp_inline_styles_for_kindle!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            updated = html.gsub(%r{<style\b[^>]*>.*?</style>}m) { it.gsub(INLINE_WEBP_DECL_PATTERN, '') }
            next if updated == html

            File.write(path, updated, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} のインライン style から webp 参照を除去しました")
          end
          html_files
        end

        # 各 EPUB 章 HTML の <body> に vs-epub クラスを付与する（クリーン・Kindle 両フレーバ共通）。
        # body.vs-epub は「EPUB リフロー文脈」の目印で、PDF を壊さず EPUB だけに効かせたい
        # 体裁調整（例: コードブロックの折返し・改ページ許容）の足場にする。劣化用途ではない
        # （Kindle 専用の劣化は別途 vs-kindle で行う）。PDF 用 HTML には付かないため PDF では無害。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def mark_body_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)
            body = doc.at_css('body')
            next unless body

            add_class(body, 'vs-epub')
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
          end
          html_files
        end

        # 横並びレイアウト（book-card / sideimage / img-text 系）のコンテナ画像に、幅と回り込みを
        # inline style で課す。Kindle は外部 CSS の画像サイズ指定を無視するが inline は尊重するため、
        # grid 崩壊時の全幅化を inline で確実に防ぐ。container クラス → 幅(%)・float 側の対応表で制御。
        LAYOUT_IMAGE_RULES = {
          'book-card' => { width: 40, float: 'left' },
          # sideimage 系は text 3 : image 1（画像 1/4 ＝ 25%）。本文を主役にし画像は脇に小さく添える。
          'sideimage' => { width: 25, float: 'left' },
          'sideimage-left' => { width: 25, float: 'left' },
          'sideimage-right' => { width: 25, float: 'right' },
          'img-text' => { width: 45, float: 'left' },
          'img-text2' => { width: 45, float: 'left' },
          'img-text3' => { width: 45, float: 'left' },
          'text-img' => { width: 45, float: 'right' },
          'text2-img' => { width: 45, float: 'right' },
          'text3-img' => { width: 45, float: 'right' }
        }.freeze

        # 横並びコンテナ内の画像に inline で幅・float を付与する。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def constrain_layout_images_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            changed = false
            LAYOUT_IMAGE_RULES.each do |klass, rule|
              doc.css(".#{klass}").each do |container|
                target = layout_image_target(container)
                next unless target

                apply_inline_image_constraint!(target, rule)
                changed = true
              end
            end
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の横並び画像を inline で制約しました")
          end
          html_files
        end

        # コンテナ直下の画像要素（figure 優先・無ければ img、無ければ子孫 img）を返す。
        def layout_image_target(container)
          direct = container.element_children.find { %w[figure img].include?(it.name) }
          direct || container.at_css('img')
        end

        # 画像要素（img/figure）へ幅・float を inline で付与する。figure の場合は内側 img も 100% に。
        def apply_inline_image_constraint!(node, rule)
          add_inline_style(node, "max-width: #{rule[:width]}%; width: #{rule[:width]}%; height: auto; float: #{rule[:float]};")
          return unless node.name == 'figure'

          inner = node.at_css('img')
          add_inline_style(inner, 'width: 100%; height: auto;') if inner
        end

        # 既存 style を保ったまま CSS 宣言を追記する。
        def add_inline_style(node, css)
          existing = node['style'].to_s.strip
          existing += ';' unless existing.empty? || existing.end_with?(';')
          node['style'] = "#{existing}#{css}"
        end

        # inline 数式（img.vs-math-inline）・display 数式画像の inline style の ex 値を em へ変換し、
        # さらに px の width/height 属性をフォールバックとして付与する。
        # CSS を解す閲覧アプリは em（style）で本文連動、Kindle は em を無視して px 属性で本文相当に固定する。
        # 固有寸法のない数式 SVG は px 属性が無いと 300px 既定で巨大表示されるため（§3）。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def convert_math_units_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            nodes = doc.css('img.vs-math-inline, figure.vs-math-display img')
            next if nodes.empty?

            nodes.each do |img|
              style = img['style']
              next if style.nil? || style.empty?

              converted = convert_math_style(style, in_table: math_in_table?(img))
              img['style'] = converted unless converted == style
              apply_math_px_fallback!(img, converted)
            end

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の数式寸法を em＋px 属性へ整えました")
          end
          html_files
        end

        # style の em 値から px を算出し、width/height の HTML 属性へ反映する（Kindle 用フォールバック）。
        def apply_math_px_fallback!(img, style)
          w = style[/width:\s*(-?\d*\.?\d+)em/, 1]&.to_f
          h = style[/height:\s*(-?\d*\.?\d+)em/, 1]&.to_f
          img['width'] = (w * EPUB_BASE_FONT_PX).round.to_s if w&.positive?
          img['height'] = (h * EPUB_BASE_FONT_PX).round.to_s if h&.positive?
        end

        # 数式画像が表セル（td/th）内にあるか。
        def math_in_table?(img) = img.ancestors('td, th').any?

        # style 文字列の `<数値>ex` を em へ換算する。基本は ×0.5。表セル内で換算後の
        # height が MIN_TABLE_MATH_EM 未満になる場合は、height がその値になるよう全寸法を
        # 等比拡大する（縦横比・ベースラインを保ったまま単位記号を読める大きさにする）。
        def convert_math_style(style, in_table:)
          factor = EX_TO_EM
          if in_table
            height_ex = style[/height:\s*(-?\d*\.?\d+)ex/, 1]&.to_f
            if height_ex&.positive? && height_ex * EX_TO_EM < MIN_TABLE_MATH_EM
              factor = MIN_TABLE_MATH_EM / height_ex
            end
          end

          style.gsub(/(-?\d*\.?\d+)ex\b/) do
            "#{(::Regexp.last_match(1).to_f * factor).round(4)}em"
          end
        end

        # tip / memo / column / notice / note（コラム・注記枠）に見出しラベル要素を実体注入する。
        # PDF では ::before（position:absolute）でラベル帯を描くが、Kindle は absolute を無視して
        # ラベルが消える。実体の <p class="vs-adm-label"> を先頭に挿し、枠線は code/chapter CSS の
        # body.vs-kindle ルール（px 枠線）に委ねることで、Kindle でもラベル付きの囲み枠を保証する（§5）。
        # notice / note は PDF では ::before ラベルを持たないが、Kindle では囲み枠＋ラベルへ劣化させる。
        ADMONITION_LABELS = {
          'tip' => '【TIP】', 'memo' => '【MEMO】', 'column' => '【COLUMN】',
          'notice' => '【NOTICE】', 'note' => '【NOTE】',
          'output' => '【OUTPUT】', 'terminal' => '【TERMINAL】'
        }.freeze

        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def decorate_admonitions_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            changed = false
            ADMONITION_LABELS.each do |klass, label|
              doc.css("div.#{klass}").each do |box|
                next if box.at_css('.vs-adm-label') # 二重注入を防ぐ

                node = Nokogiri::XML::Node.new('p', doc)
                node['class'] = 'vs-adm-label'
                node.content = label
                box.prepend_child(node)
                changed = true
              end
            end
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のコラム枠にラベルを注入しました")
          end
          html_files
        end

        # Prism の行番号付きコードブロックを、リフローで崩れない行ブロック構造へ変換する
        # （F 案・epub-code-line-numbers-spec §1）。1 論理行 = 1 ブロック要素とし、折返しは
        # ぶら下げインデント（code.css）で番号の右＝コード開始位置へ揃える。行番号はクリーン
        # EPUB では CSS カウンタ（::before）、Kindle では inject_code_line_numbers_for_kindle!
        # の実テキスト注入が担うため、ここでは番号を持たない構造だけを作る（両フレーバ共通）。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def convert_code_blocks_for_epub!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            targets = doc.css('pre.line-numbers')
            next if targets.empty?

            changed = false
            targets.each { |pre| changed |= convert_code_pre_to_lines!(pre, doc) }
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のコードを行ブロック化しました")
          end
          html_files
        end

        # 1 つの pre.line-numbers を div.vs-code-epub（行ブロック容器）へ置換する。失敗時は変更せず false。
        def convert_code_pre_to_lines!(pre, doc)
          code = pre.at_css('code')
          return false unless code

          # 絶対配置ガター（.line-numbers-rows）は不要なので取り除く
          code.css('.line-numbers-rows').each(&:remove)

          lines = split_code_into_lines(code)
          return false if lines.empty?

          language_class = code['class'].to_s.split.find { it.start_with?('language-') }

          container = build_code_lines(doc, lines, language_class)
          # 範囲 include の開始行番号（code-include-line-number-spec）を容器へ引き継ぐ。
          # クリーン EPUB はインライン counter-reset がカウンタ開始値として消費し、
          # Kindle は注入時に data-start を採番開始値として消費する。
          if (start = pre['data-start']&.to_i) && start >= 1
            container['data-start'] = start.to_s
            container['style'] = "counter-reset: vs-code-ln #{start - 1}"
          end
          pre.replace(container)
          true
        rescue StandardError => e
          Common.log_warn("[EPUB] コードの行ブロック化に失敗（元のまま維持）: #{e.message}")
          false
        end

        # <code> の中身を論理行（\n 区切り）へ分割する。各行は Prism のトークン span を
        # 保持した HTML 断片。複数行に跨るトークンは行ごとに閉じ／開き直す（行スプリットの定石）。
        #
        # @return [Array<String>] 各論理行の内部 HTML（末尾の空行は捨てる）
        def split_code_into_lines(code)
          lines = [+'']
          collect_code_line_fragments(code, lines, [])
          lines.pop if lines.size > 1 && lines.last.empty? # 末尾改行由来の空行を除く
          lines
        end

        # ノードを再帰走査し、テキストの改行で行を分割しながら、祖先のトークン span を
        # 各行で開き直して HTML 断片を組み立てる。
        #
        # @param node [Nokogiri::XML::Node] 走査中のノード
        # @param lines [Array<String>] 構築中の行配列（破壊的に追記）
        # @param open_tags [Array<String>] 現在開いている span 開始タグ（行跨ぎ復元用）
        def collect_code_line_fragments(node, lines, open_tags)
          node.children.each do |child|
            if child.text?
              append_text_with_newlines(child.content, lines, open_tags)
            elsif child.element? && child.name == 'span'
              open_tag = span_open_tag(child)
              lines[-1] << open_tag
              open_tags.push(open_tag)
              collect_code_line_fragments(child, lines, open_tags)
              open_tags.pop
              lines[-1] << '</span>'
            else
              lines[-1] << child.to_html
            end
          end
        end

        # テキストを改行で分割して各行へ積む。改行ごとに、開いている span を閉じてから
        # 改行し、次行の冒頭で同じ span を開き直す（トークンの行跨ぎを保つ）。
        def append_text_with_newlines(text, lines, open_tags)
          segments = text.split("\n", -1)
          segments.each_with_index do |segment, idx|
            lines[-1] << escape_html_text(segment)
            next if idx == segments.length - 1

            open_tags.reverse_each { lines[-1] << '</span>' }
            lines.push(+open_tags.join)
          end
        end

        # span 要素の開始タグ（属性つき）を組み立てる。
        def span_open_tag(span)
          attrs = span.attribute_nodes.map { %( #{it.name}="#{escape_attr(it.value)}") }.join
          "<span#{attrs}>"
        end

        # 行配列から div.vs-code-epub（1 論理行 = 1 div.vs-code-line）を構築する。
        # language-* クラスは容器と各行 <code> の両方に付け、Prism トークン色 CSS と
        # 既存の [class*="language-"] 系セレクタの適用を保つ。
        def build_code_lines(doc, lines, language_class)
          container = Nokogiri::XML::Node.new('div', doc)
          container['class'] = ['vs-code-epub', language_class].compact.join(' ')

          lines.each do |line_html|
            line = Nokogiri::XML::Node.new('div', doc)
            line['class'] = 'vs-code-line'
            code = Nokogiri::XML::Node.new('code', doc)
            code['class'] = language_class if language_class
            # 空行は &nbsp; で 1 行ぶんの高さを保ち、行高を揃える（空ブロックの潰れ防止）。
            code.inner_html = line_html.strip.empty? ? "\u00A0" : line_html
            line.add_child(code)
            container.add_child(line)
          end
          container
        end

        # Kindle 向けに各コード行の先頭へ実テキストの行番号 span を注入する（F 案 §2.2）。
        # KFX は ::before と var() を解さないため、vs-adm-label と同じ実体注入パターンで
        # 番号を持たせる。番号は nbsp で最大桁数へ右詰めパディングし、等幅フォントで桁を
        # 揃える（CSS の幅指定に依存せず、nbsp＋数字には分割機会が無いため縦折返しも起きない）。
        # クリーン EPUB はこのフェーズを通らないため span は混入しない。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def inject_code_line_numbers_for_kindle!(html_files)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)

            changed = false
            doc.css('div.vs-code-epub').each do |container|
              lines = container.css('> div.vs-code-line')
              next if lines.empty?

              start = (container['data-start'] || 1).to_i
              width = (start + lines.size - 1).to_s.length
              lines.each_with_index do |line, idx|
                next if line.at_css('.vs-code-ln') # 二重注入を防ぐ（冪等）

                span = Nokogiri::XML::Node.new('span', doc)
                span['class'] = 'vs-code-ln'
                span.content = "#{(start + idx).to_s.rjust(width, "\u00A0")} "
                line.prepend_child(span)
                changed = true
              end
            end
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のコード行番号を注入しました")
          end
          html_files
        end

        # コード行テキストの HTML エスケープ（行スプリットでテキスト断片を再構成するため）。
        def escape_html_text(str) = str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')

        # span 属性値の HTML エスケープ（開始タグ再構成用）。
        def escape_attr(str) = escape_html_text(str).gsub('"', '&quot;')

        # ================================================================
        # EPUB 用 CSS サニタイズ
        # ================================================================
        # PDF 用 CSS（ノンブル・柱の @page マージンボックス）をソースから消すと
        # PDF が壊れるため、生成後の EPUB パッケージ内 CSS でのみマージンボックスを
        # 物理的に除去して epubcheck の CSS-008 ERROR を解消する。
        # stabilize_epub_identifier! と同型の unzip → 修正 → zip 差し替え方式
        # （mimetype 無圧縮制約に触れず、追加依存も不要）。
        # ================================================================

        # 生成後 EPUB 内の CSS をサニタイズする。
        # - @page マージンボックス / @footnote（CSS-008）は常に除去する。
        # - `url(...webp)` を含む宣言は **kindle のみ**除去する（kindle は WebP 全除外による参照切れ回避。
        #   クリーン EPUB は WebP を同梱維持するため CSS の webp url() も残す・§4。WEBP_URL_PATTERN）。
        # - フォント非埋め込み時は @font-face も除去する（fonts/ 不同梱による RSC-007 回避）。
        #
        # @param epub_path [String] 対象 EPUB ファイルパス
        # @param flavor [Symbol] :epub（WebP 維持）/ :kindle（webp url() 除去）
        # @return [void]
        def sanitize_epub_css!(epub_path, flavor: :epub)
          abs_epub = File.expand_path(epub_path)
          patterns = [MARGIN_BOX_PATTERN]
          patterns << WEBP_URL_PATTERN if flavor == :kindle
          patterns << FONT_IMPORT_PATTERN unless embed_fonts?

          Dir.mktmpdir('vs-epub-css') do |tmpdir|
            # unzip のグロブは '*' がパス区切りも跨ぐため EPUB/*.css で全 CSS を取り出す
            system('unzip', '-o', abs_epub, 'EPUB/*.css', '-d', tmpdir,
                   out: File::NULL, err: File::NULL)

            changed = Dir.glob(File.join(tmpdir, 'EPUB/**/*.css')).filter_map do |path|
              css = File.read(path, encoding: 'UTF-8')
              sanitized = patterns.inject(css) { |acc, pat| acc.gsub(pat, '') }
              sanitized = strip_font_faces_except_keyfont(sanitized) unless embed_fonts?
              next if sanitized == css

              File.write(path, sanitized)
              path.delete_prefix("#{tmpdir}/")
            end

            if changed.empty?
              Common.log_info('[EPUB] CSS に除去対象（マージンボックス/@font-face）はありませんでした')
              return
            end

            Dir.chdir(tmpdir) do
              system('zip', '-q', abs_epub, *changed, out: File::NULL, err: File::NULL)
            end
            Common.log_info("[EPUB] CSS をサニタイズしました（#{changed.size} ファイル）")
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] CSS サニタイズに失敗: #{e.message}")
        end

        # 非埋め込み時の @font-face 除去。keyfont（kbd キーキャップ描画）だけは実体を
        # 同梱する（keyfont_asset?）ため対の @font-face を保持し、他はすべて除去する。
        def strip_font_faces_except_keyfont(css)
          css.gsub(FONT_FACE_PATTERN) { |block| block.match?(KEYFONT_FACE_PATTERN) ? block : '' }
        end

        # ================================================================
        # content.opf zip 手術（unzip → 書き換え → zip 差し替え）
        # ================================================================
        # 生成済み EPUB の content.opf を後段で修正する 2 種の手術。P2 で pipeline から移設。

        # EPUB の dc:identifier を書籍固有の決定的な UUID に置換する。
        # プロジェクト名（config.project.name）が同一である限り、バージョンが変わっても
        # UUID が変化しないため、電子書籍ストアでの差し替えが容易になる。
        def stabilize_epub_identifier!(epub_path)
          stable_id = stable_project_uuid
          return unless stable_id

          abs_epub = File.expand_path(epub_path)

          Dir.mktmpdir('vs-epub-id') do |tmpdir|
            system('unzip', '-o', abs_epub, 'EPUB/content.opf', '-d', tmpdir,
                   out: File::NULL, err: File::NULL)
            opf_path = File.join(tmpdir, 'EPUB', 'content.opf')
            return unless File.exist?(opf_path)

            content = File.read(opf_path, encoding: 'UTF-8')
            replaced = content.sub(
              %r{(<dc:identifier\s+id="bookid">)urn:uuid:[0-9a-f-]+(</dc:identifier>)},
              "\\1#{stable_id}\\2"
            )

            if replaced == content
              Common.log_info('[EPUB] identifier は既に安定化済みです')
              return
            end

            File.write(opf_path, replaced)

            Dir.chdir(tmpdir) do
              system('zip', '-q', abs_epub, 'EPUB/content.opf',
                     out: File::NULL, err: File::NULL)
            end

            Common.log_info("[EPUB] identifier を安定化しました: #{stable_id}")
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] identifier 安定化に失敗: #{e.message}")
        end

        # content.opf の数字始まり id / idref に接頭辞を付与して NCName 違反を解消する。
        # vivliostyle CLI はファイル名（例: 00-preface）から manifest item の id を
        # 機械生成するため、数字始まりの id が XML の NCName 規則（先頭は英字または _）に
        # 違反し epubcheck の RSC-005 ERROR になる。spine の idref も同値を参照するため、
        # id と idref を同一規則（固定接頭辞 id-）で書き換えて整合を保つ。
        # stabilize_epub_identifier! と同型の unzip → 修正 → zip 差し替え方式。
        def sanitize_epub_opf_ids!(epub_path)
          abs_epub = File.expand_path(epub_path)

          Dir.mktmpdir('vs-epub-opf') do |tmpdir|
            system('unzip', '-o', abs_epub, 'EPUB/content.opf', '-d', tmpdir,
                   out: File::NULL, err: File::NULL)
            opf_path = File.join(tmpdir, 'EPUB', 'content.opf')
            return unless File.exist?(opf_path)

            content = File.read(opf_path, encoding: 'UTF-8')
            replaced = content.gsub(/\b(id|idref)="(\d[^"]*)"/) do
              %(#{::Regexp.last_match(1)}="id-#{::Regexp.last_match(2)}")
            end

            return if replaced == content

            File.write(opf_path, replaced)

            Dir.chdir(tmpdir) do
              system('zip', '-q', abs_epub, 'EPUB/content.opf',
                     out: File::NULL, err: File::NULL)
            end

            Common.log_info('[EPUB] content.opf の数字始まり id を NCName 準拠に修正しました')
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] content.opf id 修正に失敗: #{e.message}")
        end

        # プロジェクト名から決定的に算出した UUID を urn:uuid: に載せて返す。
        # プロジェクト名が未設定の場合は book.main_title を fallback とし、
        # それでも空なら nil を返す。
        def stable_project_uuid
          book = Common::CONFIG.book

          # 著者が独自 ISBN を取得している場合は urn:isbn を dc:identifier に使う
          # （EPUB の標準作法。未設定ならプロジェクト名由来の安定 UUID を使用）
          isbn = book.isbn.to_s.delete('- ').strip
          return "urn:isbn:#{isbn}" unless isbn.empty?

          project = Common::CONFIG.project
          raw     = project&.name.to_s.strip
          fallback = [book&.main_title, book&.subtitle].compact.join(' ').strip
          base = raw.empty? ? fallback : raw
          base = base.to_s.strip
          return if base.empty?

          normalized = base.downcase
          hex = Digest::SHA1.hexdigest(normalized)
          uuid = [
            hex[0, 8],
            hex[8, 4],
            hex[12, 4],
            hex[16, 4],
            hex[20, 12]
          ].join('-')
          "urn:uuid:#{uuid}"
        end

        # ================================================================
        # Kindle KPF 変換（§1-7）
        # ================================================================

        # Kindle Previewer 3 CLI（kindlepreviewer）コマンド名と既定ロケール。
        KINDLEPREVIEWER_COMMAND = 'kindlepreviewer'
        # -locale は当面 en 固定（言語設定との連動は残 TODO・§4）。
        KPF_LOCALE = 'en'

        # kindlepreviewer が PATH 上に存在するかを返す。テストでは本メソッドをスタブして
        # 「未導入時はスキップして継続」する経路を検証する（DI・§5-1）。
        #
        # @param command [String] チェックするコマンド名
        # @return [Boolean]
        def kindlepreviewer_available?(command = KINDLEPREVIEWER_COMMAND)
          system('which', command, out: File::NULL, err: File::NULL) || false
        end

        # Kindle 用中間 EPUB を kindlepreviewer で KPF へ変換し、kpf_path へ回収する（§1-7）。
        # 変換ログ（Summary_Log.csv / Logs/*_log.csv）の Error/Quality 件数を log_summary で要約する。
        # 未導入・変換失敗時は false を返し（中間 EPUB は残す）、ビルド全体は止めない。
        #
        # @param epub_path [String] 入力 Kindle EPUB（…-kindle.epub）
        # @param kpf_path [String] 出力 KPF（ルート直下）
        # @param locale [String] kindlepreviewer の -locale
        # @param command [String] kindlepreviewer コマンド名（DI 用）
        # @return [Boolean] KPF を生成できたか
        def convert_epub_to_kpf!(epub_path, kpf_path, locale: KPF_LOCALE, command: KINDLEPREVIEWER_COMMAND)
          return false unless File.exist?(epub_path)

          unless kindlepreviewer_available?(command)
            Common.log_warn("[KPF] #{command} が見つかりません。KPF 変換をスキップし、中間 EPUB を残します: #{epub_path}")
            Common.log_warn('  → Kindle Previewer 3 を導入するか、中間 EPUB を手動で変換してください。')
            return false
          end

          Common.log_action("[KPF] #{File.basename(epub_path)} を KPF へ変換しています…")
          Dir.mktmpdir('vs-kpf') do |outdir|
            ok = system(command, File.expand_path(epub_path), '-convert', '-output', outdir, '-locale', locale,
                        out: File::NULL, err: File::NULL)
            summarize_kpf_logs(outdir)

            kpf = Dir.glob(File.join(outdir, '**', '*.kpf')).max_by { File.mtime(it) }
            unless ok && kpf
              Common.log_error("[KPF] Kindle 変換に失敗しました。中間 EPUB を残します: #{epub_path}")
              return false
            end

            FileUtils.rm_f(kpf_path)
            FileUtils.mv(kpf, kpf_path)
            Common.log_success("[KPF] KPF を生成しました: #{kpf_path}")
            true
          end
        end

        # kindlepreviewer のログ CSV から Kindle のエラー/警告コード件数を集計して要約表示する。
        # ヘッダ列名（"Error" 等の語）を誤カウントしないよう、実データである E#####/W##### 形式の
        # コード出現数で数える。版差でファイル名が変わっても拾えるよう出力配下の全 CSV を走査する。
        # 内訳（どのコードが何件か）も併記して、著者が原因を追えるようにする。
        def summarize_kpf_logs(outdir)
          csvs = Dir.glob(File.join(outdir, '**', '*.csv'))
          return if csvs.empty?

          codes = csvs.flat_map do |csv|
            File.read(csv, encoding: 'UTF-8').scan(/\b[EW]\d{4,5}\b/)
          rescue StandardError
            []
          end
          errors   = codes.count { it.start_with?('E') }
          warnings = codes.count { it.start_with?('W') }
          breakdown = codes.tally.sort.map { |code, n| "#{code}×#{n}" }.join(', ')
          detail = breakdown.empty? ? nil : "内訳: #{breakdown}"
          Common.log_summary("[KPF] 変換ログ: Error=#{errors} / Warning=#{warnings}（#{csvs.size} CSV）", detail:)
        rescue StandardError => e
          Common.log_warn("[KPF] 変換ログの解析に失敗: #{e.message}")
        end
      end
    end
  end
end
