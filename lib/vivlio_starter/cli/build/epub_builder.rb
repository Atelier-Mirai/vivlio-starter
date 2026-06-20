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
require_relative 'heading_image_composer'
require_relative '../post_process/html_parser'

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

        # fonts/ 配下を参照する @import を検出する正規表現。
        # page-settings.css は FontManager 生成の `@import url("fonts/google-fonts.css")`
        # を持つ。非埋め込みで fonts/ を除外すると参照切れ（RSC-007）になるため、
        # @font-face とあわせて EPUB 内 CSS から除去する。
        FONT_IMPORT_PATTERN = /@import\s+url\(\s*["']?fonts\/[^"')]+["']?\s*\)\s*;?/

        # `url(....webp)` を含む CSS 宣言を 1 つ検出する正規表現（1 宣言＝1 マッチ）。
        # WebP は EPUB から全除外する（build_copy_asset_excludes_config）ため、CSS の
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

        # EPUB 用 entries.js を生成する
        # PDF 用の構成から目次・裏表紙を除外した EPUB 専用エントリを生成
        #
        # @param base_dir [String] ベースディレクトリ
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @return [Array<String>] EPUB に含める HTML ファイルパスの配列
        def generate_epub_entries!(base_dir, entries)
          Common.log_action('[EPUB] entries.epub.js を生成しています…')

          chapter_htmls = collect_epub_htmls(base_dir, entries)

          if chapter_htmls.empty?
            Common.log_warn('[EPUB] 対象 HTML が見つかりません。スキップします。')
            return []
          end

          # 索引・用語集を EPUB 用に書き換え（空リンクに連番テキストを挿入）
          post_process_index_glossary_for_epub!(chapter_htmls)

          # 段落内脚注 span の重複 id を除去（XHTML の id 重複 ERROR を回避）
          strip_inline_footnote_ids_for_epub!(chapter_htmls)

          # テーブルの align 属性を style へ変換（XHTML5 で廃止された属性の ERROR を回避）
          rewrite_table_align_for_epub!(chapter_htmls)

          # 絵文字画像をプレーン絵文字へ復元（EPUB は Type 3 非該当。twemoji 非同梱で軽量化）
          restore_plain_emoji_for_epub!(chapter_htmls)

          # 扉絵（h1）・節絵（h2）を合成画像として焼き込む（theme.style=image 時のみ）
          inject_heading_images_for_epub!(chapter_htmls)

          # 残った <img> 参照 WebP を Kindle 対応の JPEG/PNG へ変換して src を差し替える。
          # 直前までで <img> の出入りが確定するため最後に置く（絵文字復元・扉絵注入後）。
          transcode_webp_images_for_epub!(chapter_htmls)

          # Kindle のリフローで崩れる箇所を EPUB 専用に是正する（epub-kindle-layout-spec.md）。
          # body.vs-epub マーカー → 画像の幅制約（inline）→ 数式 ex→em → コード行番号のテーブル化。
          # Kindle は外部 CSS の画像サイズ指定を無視するため、画像は inline style で制約する。
          mark_body_for_epub!(chapter_htmls)
          constrain_layout_images_for_epub!(chapter_htmls)
          convert_math_units_for_epub!(chapter_htmls)
          convert_code_blocks_for_epub!(chapter_htmls)
          decorate_admonitions_for_epub!(chapter_htmls)

          write_epub_entries(base_dir, chapter_htmls)
          Common.log_success("[EPUB] entries.epub.js を生成しました（#{chapter_htmls.size} エントリ）")
          chapter_htmls
        end

        # EPUB 専用 vivliostyle.config.js を生成する
        # cover.embed 設定に応じて表紙画像の埋め込みを制御
        #
        # @return [String] 生成されたファイルパス
        def generate_epub_config!
          Common.log_action('[EPUB] vivliostyle.config.epub.js を生成しています…')

          config = Common::CONFIG
          book_config = config.book

          # JS 文字列に安全に埋め込むための簡易エスケープ
          esc = ->(s) { s.to_s.gsub('\\', '\\\\').gsub("'", "\\'") }

          # メタデータを book セクションから取得
          # book.title は存在しない場合がある（main_title + subtitle から合成）
          combined_title = [book_config&.main_title, book_config&.subtitle].compact.join(' ').strip
          title_raw = book_config.respond_to?(:title) ? book_config.title : nil
          title = if title_raw && !title_raw.to_s.strip.empty?
                    title_raw
                  else
                    combined_title.empty? ? '書籍タイトル' : combined_title
                  end
          author   = book_config&.author || '著者名'
          language = book_config&.language || 'ja'

          # ページサイズを解決（vivliostyle.rb から移植）
          page_size = resolve_page_size(config)

          # 表紙画像の埋め込み設定を取得
          cover_line = build_cover_config_line(config, esc)

          # 原稿外ファイルの EPUB 混入を防ぐ copyAsset.excludes
          copy_asset_lines = build_copy_asset_excludes_config

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
            #{cover_line}#{copy_asset_lines}  entry: entries,
              output: [
                './#{EPUB_OUTPUT_FILE}'
              ]
            };

            export default vivliostyleConfig;
          JS

          File.write(EPUB_CONFIG_FILE, config_content)
          Common.log_success("[EPUB] #{EPUB_CONFIG_FILE} を生成しました")
          EPUB_CONFIG_FILE
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

        # EPUB 用 entries.js をファイルに書き出す
        #
        # @param base_dir [String] ベースディレクトリ
        # @param html_files [Array<String>] HTML ファイルパスの配列
        def write_epub_entries(base_dir, html_files)
          entries = html_files.map { CLI::EntriesCommands.build_entry(it) }

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

        def build_cover_config_line(config, esc)
          return "  // cover: 表紙埋め込みなし（epub.embed: false）\n" unless Common.epub_embed?

          cover_image = resolve_cover_image_path(config)
          return "  // cover: 表紙画像が見つかりません\n" unless cover_image && File.exist?(cover_image)

          "  cover: './#{esc.call(cover_image)}',\n"
        end

        # Vivliostyle CLI は EPUB 生成時に CWD 以下のアセット
        # （css/png/jpg 等の DEFAULT_ASSET_EXTENSIONS）を node_modules を除き
        # 丸ごと webpub→EPUB へコピーする。原稿外ファイル（gem 雛形・仕様書・
        # ページ画像など）が混入し肥大化・CSS-008/RSC-007 を生むため、
        # copyAsset.excludes で明示的に除外する。
        #
        # @return [String] config に差し込む copyAsset ブロック（末尾改行付き）
        def build_copy_asset_excludes_config
          patterns = %w[
            lib/**
            docs/**
            test/**
            sources/**
            codes/**
            templates/**
            data/**
            .cache/**
            *_images/**
            covers/bundled/**
            stylesheets/twemoji/*.svg
            images/**/*.webp
            stylesheets/**/*.webp
          ]
          # WebP は Kindle 非対応のため EPUB へ一切同梱しない。<img> 参照分は
          # transcode_webp_images_for_epub! が images/_epub_assets/ の JPEG/PNG へ移すため、
          # 残る WebP（CSS 背景・絵文字マスター・扉絵/節絵の背景）はすべて除外してよい。
          # twemoji 直下（絵文字マスター 7,000+ 個）の SVG も restore_plain_emoji_for_epub! で
          # 参照されなくなるため除外する。

          # フォント非埋め込み時は実体（51MB の TTF/OTF）も同梱しない。
          # @font-face は sanitize_epub_css! が EPUB 内 CSS から除去する。
          patterns << 'stylesheets/fonts/**' unless embed_fonts?

          excludes = patterns.map { "      '#{it}'," }.join("\n")
          <<~JS
              copyAsset: {
                excludes: [
            #{excludes}
                ],
              },
          JS
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
        # 新しい設定構造に対応
        #
        # @param config [Object] Common::CONFIG
        # @return [String, nil] 表紙画像の相対パス
        def resolve_cover_image_path(config)
          covers_dir = config.directories&.covers || 'covers'
          theme = Common.cover_theme
          return nil unless theme

          image_name = "cover_#{theme}.jpg"
          File.join(covers_dir, image_name)
        end

        # book.yml のページ設定から Vivliostyle CLI 用サイズ文字列を解決する
        # vivliostyle.rb の resolve_vivliostyle_size から移植
        #
        # @param config [Object] Common::CONFIG
        # @return [String] 'A5', 'B5', 'A4', または '148mm 210mm' 形式
        def resolve_page_size(config)
          page_cfg = config.respond_to?(:page) ? config.page : config[:page]
          return 'A5' unless page_cfg

          size_name = page_cfg[:size].to_s.strip.upcase
          return size_name unless size_name.empty?

          raw = page_cfg.respond_to?(:to_h) ? page_cfg.to_h : page_cfg
          w, h = Common.resolve_page_size(raw)
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

          html_files.each do |path|
            basename = File.basename(path, '.html')
            case basename
            when '_indexpage'
              rewrite_index_for_epub!(path, chapter_map)
            when '_glossarypage'
              rewrite_glossary_for_epub!(path, chapter_map)
            end
          end
          html_files
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
        def rewrite_index_for_epub!(path, chapter_map)
          html = File.read(path, encoding: 'utf-8')

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
        def rewrite_glossary_for_epub!(path, chapter_map)
          html = File.read(path, encoding: 'utf-8')

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
        # twemoji 画像の同梱を不要にして軽量化する（build_copy_asset_excludes_config で
        # stylesheets/twemoji 直下を除外）。囲み数字（vs-circled-number）は alt が数字で
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
        def inject_heading_images_for_epub!(html_files)
          return html_files unless Common::CONFIG.dig('theme', 'style') == 'image'

          theme = read_theme_heading_assets
          return html_files unless theme

          context = {
            frontispiece: theme[:frontispiece],
            ornament: theme[:ornament],
            font_family: epub_heading_font_family,
            number_color: theme[:number_color]
          }

          html_files.each { |path| inject_heading_images_into_file!(path, context) }
          html_files
        end

        # theme.css から扉絵・節絵の実画像パストと節番号色を読み取る。
        # PDF と同一画像を単一の参照元から使う（二重解決を避ける・§B-4）。
        #
        # @return [Hash, nil] { frontispiece:, ornament:, number_color: }。theme.css 不読時は nil
        def read_theme_heading_assets
          theme_css_path = File.join(Common::STYLESHEETS_DIR, 'theme.css')
          return nil unless File.exist?(theme_css_path)

          css = File.read(theme_css_path, encoding: 'utf-8')
          {
            frontispiece: resolve_theme_image_file(css[/--frontispiece-image:\s*url\(["']?([^"')]+)["']?\)/, 1]),
            ornament: resolve_theme_image_file(css[/--section-bg-image:\s*url\(["']?([^"')]+)["']?\)/, 1]),
            number_color: resolve_css_color(css, css[/--section-number-color:\s*([^;]+);/, 1])
          }
        rescue StandardError => e
          Common.log_warn("[EPUB] theme.css の読み取りに失敗（扉絵の画像化をスキップ）: #{e.message}")
          nil
        end

        # theme.css の url(...) 値（stylesheets からの相対）を実ファイルパスへ解決する。
        #
        # @param rel [String, nil] 例: "images/bundled/sakura_portrait.webp"
        # @return [String, nil] 存在する実ファイルパス、無ければ nil
        def resolve_theme_image_file(rel)
          return nil if rel.nil? || rel.strip.empty?
          return nil if rel.start_with?('data:', 'http://', 'https://')

          path = File.join(Common::STYLESHEETS_DIR, rel)
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
          book_font = Common::CONFIG.dig('typography', 'heading', 'font').to_s.strip
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
        def inject_frontispiece_headings!(doc, context)
          return false unless context[:frontispiece]

          changed = false
          doc.css('h1').each do |h1|
            number = h1['data-chapter-number-display'].to_s.strip
            next if number.empty?

            title = h1['data-chapter-title'].to_s.strip
            src = heading_image_src(
              image_path: context[:frontispiece], number:, title:, kind: :frontispiece, font_family: context[:font_family]
            )
            next unless src

            apply_image_heading!(h1, src, [number, title], doc)
            changed = true
          end
          changed
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
              font_family: context[:font_family], number_color: context[:number_color]
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

        # 合成画像（JPEG）を生成・キャッシュし、HTML から参照する相対パスを返す。
        # 見出し入力（種別・画像・番号・タイトル・フォント・色）のハッシュをファイル名にして
        # 同一見出しを使い回す。ツール不在・合成失敗時は nil（→ simple 縮退）。
        def heading_image_src(image_path:, number:, title:, kind:, font_family:, number_color: '#333333')
          key = Digest::SHA256.hexdigest([kind, image_path, number, title, font_family, number_color].join('|'))[0, 16]
          dir = File.join(Common.images_dir, HEADINGS_REL_SUBDIR)
          filename = "#{kind}-#{key}.jpg"
          abs = File.join(dir, filename)

          unless File.exist?(abs)
            jpg = HeadingImageComposer.render(image_path:, number:, title:, kind:, font_family:, number_color:)
            return nil unless jpg

            FileUtils.mkdir_p(dir)
            File.binwrite(abs, jpg)
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

            staged = cache.fetch(src) { cache[src] = stage_webp_replacement(src) }
            next tag unless staged

            changed = true
            tag.sub(/(\ssrc=")[^"]*(")/i, "\\1#{staged}\\2")
          end
          return unless changed

          File.write(path, updated, encoding: 'utf-8')
          Common.log_info("[EPUB] #{File.basename(path)} の WebP 画像を JPEG/PNG へ差し替えました")
        end

        # src の WebP を変換し、staging の相対パスを返す。変換不能なら nil（src 据え置き）。
        def stage_webp_replacement(src_attr)
          webp_path = decode_html_entities(src_attr)
          return nil unless File.exist?(webp_path)

          source = transcode_source_for(webp_path)
          ext = epub_image_extension_for(source)
          key = Digest::SHA256.hexdigest(
            [File.expand_path(source), File.mtime(source).to_i, ext].join('|')
          )[0, 16]

          dir = File.join(Common.images_dir, EPUB_ASSETS_REL_SUBDIR)
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
        # 是正する。CSS で済むもの（book-card / img-text の画像上限）は body.vs-epub
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

        # 各 EPUB 章 HTML の <body> に vs-epub クラスを付与する。
        # body.vs-epub ガードの CSS（画像上限・コードテーブル体裁等）を効かせるための目印。
        # PDF 用 HTML には付かないため PDF では当該 CSS が不発で無害。
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

        # tip / memo（コラム枠）に見出しラベル要素を実体注入する。
        # PDF では ::before（position:absolute）でラベル帯を描くが、Kindle は absolute を無視して
        # ラベルが消える。実体の <p class="vs-adm-label"> を先頭に挿し、枠線は code/chapter CSS の
        # body.vs-epub ルール（px 枠線）に委ねることで、Kindle でもラベル付きの囲み枠を保証する（§5）。
        ADMONITION_LABELS = { 'tip' => '【TIP】', 'memo' => '【MEMO】', 'column' => '【COLUMN】' }.freeze

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

        # Prism の行番号付きコードブロックを、Kindle が解す 2 列テーブル（番号｜コード）へ変換する。
        # Kindle は .line-numbers-rows の position:absolute ガターを描けないため（§4）。
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
            targets.each { |pre| changed |= convert_code_pre_to_table!(pre, doc) }
            next unless changed

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のコード行番号をテーブル化しました")
          end
          html_files
        end

        # 1 つの pre.line-numbers を table.vs-code-epub へ置換する。失敗時は変更せず false。
        def convert_code_pre_to_table!(pre, doc)
          code = pre.at_css('code')
          return false unless code

          # 絶対配置ガター（.line-numbers-rows）は不要なので取り除く
          code.css('.line-numbers-rows').each(&:remove)

          lines = split_code_into_lines(code)
          return false if lines.empty?

          language_class = code['class'].to_s.split.find { it.start_with?('language-') }

          table = build_code_table(doc, lines, language_class)
          pre.replace(table)
          true
        rescue StandardError => e
          Common.log_warn("[EPUB] コードのテーブル化に失敗（元のまま維持）: #{e.message}")
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

        # 行配列から table.vs-code-epub を構築する。
        def build_code_table(doc, lines, language_class)
          table = Nokogiri::XML::Node.new('table', doc)
          table['class'] = 'vs-code-epub'
          tbody = Nokogiri::XML::Node.new('tbody', doc)
          table.add_child(tbody)

          lines.each_with_index do |line_html, idx|
            tbody.add_child(build_code_row(doc, idx + 1, line_html, language_class))
          end
          table
        end

        # 1 行ぶんの <tr><td 番号><td コード> を組み立てる。
        def build_code_row(doc, number, line_html, language_class)
          tr = Nokogiri::XML::Node.new('tr', doc)

          num_td = Nokogiri::XML::Node.new('td', doc)
          num_td['class'] = 'vs-code-num'
          num_td.content = number.to_s
          tr.add_child(num_td)

          line_td = Nokogiri::XML::Node.new('td', doc)
          line_td['class'] = 'vs-code-line'
          code = Nokogiri::XML::Node.new('code', doc)
          code['class'] = language_class if language_class
          # 空行は &nbsp; で 1 行ぶんの高さを保ち、行高を揃える（空セルの潰れ防止）。
          code.inner_html = line_html.strip.empty? ? "\u00A0" : line_html
          line_td.add_child(code)
          tr.add_child(line_td)

          tr
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
        # - `url(...webp)` を含む宣言は常に除去する（WebP 全除外による参照切れ回避。WEBP_URL_PATTERN）。
        # - フォント非埋め込み時は @font-face も除去する（fonts/ 不同梱による RSC-007 回避）。
        #
        # @param epub_path [String] 対象 EPUB ファイルパス
        # @return [void]
        def sanitize_epub_css!(epub_path)
          abs_epub = File.expand_path(epub_path)
          patterns = [MARGIN_BOX_PATTERN, WEBP_URL_PATTERN]
          patterns.push(FONT_FACE_PATTERN, FONT_IMPORT_PATTERN) unless embed_fonts?

          Dir.mktmpdir('vs-epub-css') do |tmpdir|
            # unzip のグロブは '*' がパス区切りも跨ぐため EPUB/*.css で全 CSS を取り出す
            system('unzip', '-o', abs_epub, 'EPUB/*.css', '-d', tmpdir,
                   out: File::NULL, err: File::NULL)

            changed = Dir.glob(File.join(tmpdir, 'EPUB/**/*.css')).filter_map do |path|
              css = File.read(path, encoding: 'UTF-8')
              sanitized = patterns.inject(css) { |acc, pat| acc.gsub(pat, '') }
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

        # EPUB 中間ファイルをクリーンアップする
        #
        # @return [void]
        def cleanup!
          [EPUB_CONFIG_FILE, EPUB_ENTRIES_FILE, EPUB_OUTPUT_FILE].each do |file|
            next unless File.exist?(file)

            FileUtils.rm_f(file)
            Common.log_info("[EPUB] #{file} を削除しました")
          end
        end
      end
    end
  end
end
