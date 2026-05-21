# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/part_title_generator.rb
# ================================================================
# 責務:
#   catalog.yml の部タイトル（Hash キー）から中扉ページを生成する。
#   中扉は各部の先頭に挿入される見開き右ページで、部タイトルのみを印刷する。
#
# 生成物:
#   - .cache/vs/_part{N}.md: 中扉の Markdown ソース
#   - _part{N}.html: VFM 変換後の HTML（プロジェクトルート直下）
#
# 依存:
#   - CatalogLoader: 部タイトル情報の取得
#   - SectionBuilder: Markdown → HTML 変換
#   - Common: キャッシュディレクトリ・ログ出力
# ================================================================

require 'fileutils'

module VivlioStarter
  module CLI
    module Build
      # 中扉（Part Title Page）の生成モジュール
      #
      # catalog.yml の部タイトルから _part{N}.md を .cache/vs/ に生成し、
      # VFM 変換で _part{N}.html をプロジェクトルートに出力する。
      # 中扉は右ページ（奇数ページ）に部タイトルを印刷し、裏面は白紙となる。
      module PartTitleGenerator
        module_function

        # 中扉ページを一括生成する
        # catalog.yml に部タイトルがなければ何もしない
        # @return [Array<String>] 生成された中扉の basename 配列（例: ["_part1", "_part2"]）
        def generate_all!
          parts = CatalogLoader.load_part_titles
          if parts.empty?
            Common.log_info('[PartTitle] 部タイトルが定義されていません。中扉生成をスキップします。')
            return []
          end

          Common.ensure_cache_dir!
          generated = []

          parts.each do |part|
            basename = "_part#{part[:number]}"
            md_path = File.join(Common::CACHE_DIR, "#{basename}.md")

            # --- Phase: Markdown 生成 ---
            write_part_markdown!(md_path, part[:title])

            # --- Phase: HTML 変換 ---
            convert_to_html!(basename)

            generated << basename
          end

          Common.log_success("[PartTitle] 中扉を #{generated.size} 件生成しました: #{generated.join(', ')}")
          generated
        end

        # 中扉の Markdown を .cache/vs/ に書き出す
        # frontmatter の class: part-title で CSS を適用し、title で PDF アウトラインに反映する
        # @param path [String] 書き込み先パス
        # @param title [String] 部タイトル（例: "歴史篇"）
        def write_part_markdown!(path, title)
          content = <<~MD
            ---
            class: part-title
            title: #{title}
            ---

            # #{title}
          MD

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content, encoding: 'utf-8')
        end

        # 中扉 Markdown を VFM 変換して HTML を生成する
        # SectionBuilder の既存パイプライン（pre_process → convert → post_process）を再利用
        # @param basename [String] 中扉の basename（例: "_part1"）
        def convert_to_html!(basename)
          PreProcessCommands.execute_pre_process({}, [basename])
          ConvertCommands.execute_convert({}, [basename])
          PostProcessCommands.execute_post_process({}, [basename])
        end

        # 生成済みの中扉 HTML ファイルパスを返す
        # entries.js 構築時に、各部の先頭章の直前に挿入するために使用する
        # @param base_dir [String] ベースディレクトリ
        # @return [Array<String>] 中扉 HTML のパス配列（存在するもののみ）
        def existing_part_htmls(base_dir = '.')
          Dir.glob(File.join(base_dir, '_part*.html'))
        end

        # 部タイトル情報と章 HTML リストから、中扉を適切な位置に挿入した HTML リストを返す
        # 各部の先頭章の直前に _part{N}.html を挿入する
        # @param chapter_htmls [Array<String>] 章 HTML のパス配列（ソート済み）
        # @param base_dir [String] ベースディレクトリ
        # @return [Array<String>] 中扉が挿入された HTML パス配列
        def insert_part_titles_into(chapter_htmls, base_dir = '.')
          parts = CatalogLoader.load_part_titles
          return chapter_htmls if parts.empty?

          # 各部の先頭章番号 → 中扉 HTML のマッピングを構築
          insertion_map = {}
          parts.each do |part|
            next unless part[:first_chapter]

            part_html = File.join(base_dir, "_part#{part[:number]}.html")
            next unless File.exist?(part_html)

            # 先頭章番号をゼロ埋め2桁にして、対応する HTML ファイル名のプレフィックスを生成
            prefix = format('%02d-', part[:first_chapter])
            insertion_map[prefix] = part_html
          end

          return chapter_htmls if insertion_map.empty?

          # 章 HTML リストを走査し、各部の先頭章の直前に中扉を挿入
          result = []
          inserted = Set.new

          chapter_htmls.each do |html_path|
            bn = File.basename(html_path)
            insertion_map.each do |prefix, part_html|
              if bn.start_with?(prefix) && !inserted.include?(part_html)
                result << part_html
                inserted << part_html
              end
            end
            result << html_path
          end

          result
        end
      end
    end
  end
end
