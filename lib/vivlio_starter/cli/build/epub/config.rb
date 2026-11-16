# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/epub/config.rb
# ================================================================
# 責務:
#   EPUB 用の entries.epub.js と vivliostyle.config.epub.js
# ================================================================

require_relative 'workspace'
require_relative '../vivliostyle_config_writer'

module VivlioStarter
  module CLI
    module Build
      # EPUB 用の entries.epub.js と vivliostyle.config.epub.js
      module Epub::Config
        module_function

        # EPUB 専用設定ファイル名
        EPUB_CONFIG_FILE  = 'vivliostyle.config.epub.js'
        # EPUB 専用 entries ファイル名
        EPUB_ENTRIES_FILE = 'entries.epub.js'
        # EPUB デフォルト出力ファイル名
        EPUB_OUTPUT_FILE  = 'output.epub'

        # 題を持たない HTML の、目次に出す題。奥付は <title> が無く、そのままではファイル名が出る。
        EPUB_ENTRY_TITLES = { '_colophon' => '奥付' }.freeze

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
        #   - workspaceDir はワークスペース内を指定し、ルートへの一時 .vivliostyle/ 生成を
        #     なくす（P4 §5.6・段階 5）。消費者 dir 内に置くと copyAsset がパッケージへ
        #     巻き込むため dir の外へ置く。PDF 用生成 config（VivliostyleConfigWriter）とは
        #     **別の兄弟 dir** を使い、枝を並列に走らせても踏み合わないようにする
        #     （build-target-parallelization-spec.md §3.1）。
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
          # title は main_title + subtitle 合成 → プレースホルダ、
          # author / language は空文字もプレースホルダへ寄せる（vivliostyle 11 の
          # config スキーマが 1 文字以上を要求するため）。規則の二重管理を避け、
          # ルート config・パイプライン config・EPUB config で同一値を保証する。
          title    = VivliostyleConfigWriter.resolve_title
          author   = VivliostyleConfigWriter.resolve_author
          language = VivliostyleConfigWriter.resolve_language

          # ページサイズを解決
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
              workspaceDir: '#{Common::BUILD_VIVLIOSTYLE_EPUB_DIR}',
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
          # 前書き（PDF と同じく組む章で絞らない）
          preface_html = Build::ChapterConfig.htmls_for_kind(base_dir, :preface)

          # 本文章 HTML（中扉を挿入）
          main_htmls = Build::ChapterConfig.htmls_for_kind(base_dir, :chapter, entries)
          main_htmls_with_parts = Build::PartTitleGenerator.insert_part_titles_into(main_htmls, base_dir)

          # 付録
          appx_htmls = Build::ChapterConfig.htmls_for_kind(base_dir, :appendix, entries)

          # 用語集・索引（リフロー型ではページ番号は無意味だがリンクは有効）
          glossary_html = if IndexCommands.index_enabled?
                            [File.join(base_dir, '_glossarypage.html')].select { File.exist?(it) }
                          else
                            []
                          end

          # 後書き
          post_htmls = Build::ChapterConfig.htmls_for_kind(base_dir, :postface, entries)

          # 索引
          index_html = if IndexCommands.index_enabled?
                         [File.join(base_dir, '_indexpage.html')].select { File.exist?(it) }
                       else
                         []
                       end

          # 奥付（書籍の最後尾に置く）。PDF と異なり EPUB ではカバーのみ埋め込むため、
          # 奥付は本文 HTML として明示的に収録しないと EPUB に含まれない。
          colophon_html = [File.join(base_dir, '_colophon.html')].select { File.exist?(it) }

          # 書籍構成順序: 前書き → [全巻目次] → [中扉+本文] → 付録 → 用語集 → 後書き → 索引 → 奥付
          # ※ 目次（_toc）と裏表紙は除外。全巻目次は分冊の巻にだけある（multivolume-spec.md §9）
          [
            preface_html,
            Build::WholeTocGenerator.htmls(base_dir),
            main_htmls_with_parts,
            appx_htmls,
            glossary_html,
            post_htmls,
            index_html,
            colophon_html
          ].flatten.reject { Epub::Workspace.excluded_basename?(it) }
        end

        # EPUB 用 entries.js をファイルに書き出す。
        # path は entryContext（= base_dir）基準の './xx.html' で書く（E2 の確定案。
        # 全エントリは base_dir 直下にあるため basename がそのまま entryContext 相対になる）。
        #
        # @param base_dir [String] ベースディレクトリ（= 消費者 dir）
        # @param html_files [Array<String>] HTML ファイルパスの配列
        def write_epub_entries(base_dir, html_files)
          entries = html_files.map do |html|
            entry = CLI::EntriesCommands.build_entry(html).merge(path: "./#{File.basename(html)}")
            title = EPUB_ENTRY_TITLES.fetch(File.basename(html, '.html'), entry[:title])
            entry.merge(title: [chapter_number_display(html), title].compact.join(' '))
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

# 章の見出しに付いた番号（「第1章」「付録 A」）。前書き・部扉・用語集など番号の無い文書と、
# heading_numbering: none の本では nil。
#
# 読書アプリの目次（EPUB の nav・Kindle の Table of Contents）は entries の title から作られ、
# title は各章の <title>（章題だけ）なので、「執筆ワークフローとクイックスタート」と番号無しで
# 並んでいた。本文中の参照は「第1章「…」」と番号で指すので、目次にも添える。
def chapter_number_display(html)
  File.read(html, encoding: 'utf-8')[/<h1\b[^>]*\bdata-chapter-number-display="([^"]+)"/, 1]&.strip
rescue StandardError
  nil
end

        # cover 設定行を生成する
        # 新しい設定構造に対応
        #
        # @param config [Object] Common::CONFIG
        # @param esc [Proc] JS エスケープ用 Proc
        # @return [String] cover 設定行（末尾改行付き）
        def build_cover_config_line(config, esc, flavor: :epub)
          # 表紙埋め込みはフレーバごとの設定（book.yml: output.epub.embed / output.kindle.embed）に従う。
          # kindle は二重表紙回避のため既定 false（§1-6）。
          embed = flavor == :kindle ? Common.kindle_embed? : Common.epub_embed?
          unless embed
            key = flavor == :kindle ? 'kindle.embed: false' : 'epub.embed: false'
            return "  // cover: 表紙埋め込みなし（#{key}）\n"
          end

          cover_image = Epub::Workspace.resolve_cover_image_path
          return "  // cover: 表紙画像が見つかりません\n" unless cover_image && File.exist?(cover_image)

          # パッケージ内の固定パスを書く。ソースは生成キャッシュにあり、
          # localize_cover_image! が dir/covers/ 配下の同じ basename へコピーする
          # （ソース相対＝パッケージ相対の偶然一致に依存しない・移設仕様 §3.2）
          "  cover: './covers/#{esc.call(File.basename(cover_image))}',\n"
        end

        # book.yml のページ設定から Vivliostyle CLI 用サイズ文字列を解決する
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
      end
    end
  end
end
