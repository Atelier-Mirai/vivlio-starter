# frozen_string_literal: true

# ================================================================
# Module: Markdown前処理オーケストレーター
# ----------------------------------------------------------------
# 【役割】
# - Markdownファイルの前処理パイプラインを統括
# - 各処理モジュールを読み込み、コマンドとして公開
# - 後方互換性のため、module_functionとして各モジュールのメソッドを再公開
#
# 【処理の流れ】
# 1. 引数からMarkdownファイルを解決
# 2. MarkdownPreprocessor でパイプライン実行
#    - フロントマター生成/更新
#    - 画像パス正規化
#    - コードインクルード
#    - book-card/table-rotate変換
#    - リンク脚注化
#
# 【依存モジュール】
# - FrontmatterGenerator: フロントマター生成・CSS更新
# - CssUpdater: theme.css, appendix.css等の更新
# - ThemeImageResolver: テーマ画像のパス解決
# - ThemeValidator: theme 設定（色・扉絵・飾り画像）の検証と著者向け警告
# - ImageGenerator: waifu2x連携画像生成
# - MarkdownTransformer: Markdown→HTML変換
# - ImagePathNormalizer: 画像パス正規化・プレースホルダー生成
# - MarkdownPreprocessor: 前処理パイプライン実行
# ================================================================

require_relative 'common'
require 'set'
require_relative 'token_resolver'
require_relative 'pre_process/markdown_preprocessor'
require_relative 'pre_process/frontmatter_generator'
require_relative 'pre_process/css_updater'
require_relative 'pre_process/book_settings_css'
require_relative 'pre_process/theme_image_resolver'
require_relative 'pre_process/theme_validator'
require_relative 'pre_process/image_generator'
require_relative 'pre_process/markdown_transformer'
require_relative 'pre_process/image_path_normalizer'
require_relative 'pre_process/link_image_validator'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: PreProcessCommands
    # ----------------------------------------------------------------
    # Markdown前処理のコマンド群とヘルパーメソッドを提供
    # ================================================================
    module PreProcessCommands
      module_function

      # テーマ画像のデフォルトパス定数
      FRONTISPIECE_DEFAULT_PATH = ThemeImageResolver::FRONTISPIECE_DEFAULT_PATH
      ORNAMENT_DEFAULT_PATH = ThemeImageResolver::ORNAMENT_DEFAULT_PATH

      # @param command_or_ctx [Hash, Object] コマンドコンテキスト
      # @param entries [Array<TokenResolver::Entry>] Entry オブジェクトの配列
      def execute_pre_process(command_or_ctx, entries)
        ctx = normalized_context(command_or_ctx)
        enable_verbose(ctx)

        entries = resolve_entries(entries)

        Common.log_action('Markdownファイルの前処理を行っています...')
        entries.each { process_single_markdown_file(it.path, it) }

        Common.log_success('Markdownの前処理が完了しました')
      end
      module_function :execute_pre_process

      # クロスリファレンス処理を実行する。
      # preprocess_sections! で全章の前処理が完了した後に1回だけ呼ぶこと。
      def execute_cross_references(entries)
        entries = resolve_entries(entries)
        output_files = entries.map { File.basename(it.path) }
        Common.log_action("\nクロスリファレンス処理を開始します...")
        result = process_cross_references_for_files(output_files)
        Common.log_error('クロスリファレンス処理でエラーが発生しました') unless result
      end
      module_function :execute_cross_references

      def normalized_context(command_or_ctx)
        return command_or_ctx if command_or_ctx.is_a?(Hash)

        { options: options_of(command_or_ctx) }
      end
      module_function :normalized_context

      def enable_verbose(command_or_ctx)
        opts = options_of(command_or_ctx)
        ENV['VERBOSE'] = '1' if opts[:verbose]
      end
      module_function :enable_verbose

      def options_of(command_or_ctx)
        if command_or_ctx.is_a?(Hash)
          command_or_ctx[:options] || {}
        elsif command_or_ctx.respond_to?(:options)
          command_or_ctx.options || {}
        else
          {}
        end
      end
      module_function :options_of

      # Entry 配列を解決する。空の場合は全ファイルを TokenResolver で解決。
      # @param entries [Array<TokenResolver::Entry>]
      # @return [Array<TokenResolver::Entry>]
      def resolve_entries(entries)
        raw = Array(entries).compact
        return resolve_all_content_entries if raw.empty?

        # Entry オブジェクトならそのまま返す
        return raw if raw.first.respond_to?(:kind)

        # basename/パスの場合は TokenResolver で解決
        resolver = TokenResolver::Resolver.new
        raw.map { resolver.resolve_file(it) }
      end
      module_function :resolve_entries

      # contents/ 内の全 Markdown ファイルを Entry として解決
      def resolve_all_content_entries
        resolver = TokenResolver::Resolver.new
        Dir.glob("#{Common::CONTENTS_DIR}/*.md").map { resolver.resolve_file(it) }
      end
      module_function :resolve_all_content_entries

      # 単一 Markdown ファイルを処理
      # @param md_file [String] Markdown ファイルパス
      # @param entry [TokenResolver::Entry] 章情報を持つ Entry オブジェクト
      def process_single_markdown_file(md_file, entry)
        MarkdownPreprocessor.new(md_file, entry).run
      end
      module_function :process_single_markdown_file

      # ================================================================
      # フロントマター関連メソッド (FrontmatterGenerator への委譲)
      # ================================================================
      def generate_frontmatter(file_type, chapter_num = nil, existing_frontmatter = {})
        FrontmatterGenerator.generate_frontmatter(file_type, chapter_num, existing_frontmatter)
      end
      module_function :generate_frontmatter

      def apply_frontmatter(content, file_type, chapter_num, path: nil)
        FrontmatterGenerator.apply_frontmatter(content, file_type, chapter_num, path: path)
      end
      module_function :apply_frontmatter

      def report_frontmatter_error(error, frontmatter_yaml)
        FrontmatterGenerator.report_frontmatter_error(error, frontmatter_yaml)
      end
      module_function :report_frontmatter_error

      # ================================================================
      # テーマ画像解決関連メソッド (ThemeImageResolver への委譲)
      # ================================================================
      def resolve_frontispiece_path(raw, allow_generation: false)
        ThemeImageResolver.resolve_frontispiece_path(raw, allow_generation: allow_generation)
      end
      module_function :resolve_frontispiece_path

      def resolve_ornament_path(raw, allow_generation: false)
        ThemeImageResolver.resolve_ornament_path(raw, allow_generation: allow_generation)
      end
      module_function :resolve_ornament_path

      def resolve_image_path(raw, default_when_nil:, downcase_if: nil)
        ThemeImageResolver.resolve_image_path(raw, default_when_nil: default_when_nil, downcase_if: downcase_if)
      end
      module_function :resolve_image_path

      # ================================================================
      # 画像パス正規化関連メソッド (ImagePathNormalizer への委譲)
      # ================================================================
      def fix_image_paths(content, filename)
        ImagePathNormalizer.fix_image_paths(content, filename)
      end
      module_function :fix_image_paths

      def resolved_placeholder_or_path(alt_text, normalized_path)
        ImagePathNormalizer.resolved_placeholder_or_path(alt_text, normalized_path)
      end
      module_function :resolved_placeholder_or_path

      def image_exists_for?(normalized_path)
        ImagePathNormalizer.image_exists_for?(normalized_path)
      end
      module_function :image_exists_for?

      def placeholder_image_path(missing_image_path = nil)
        ImagePathNormalizer.placeholder_image_path(missing_image_path)
      end
      module_function :placeholder_image_path

      def sanitize_placeholder_text(filename)
        ImagePathNormalizer.sanitize_placeholder_text(filename)
      end
      module_function :sanitize_placeholder_text

      def svg_to_data_uri(svg_content)
        ImagePathNormalizer.svg_to_data_uri(svg_content)
      end
      module_function :svg_to_data_uri

      # ================================================================
      # Markdown変換関連メソッド (MarkdownTransformer への委譲)
      # ================================================================
      def detect_language(file_path)
        MarkdownTransformer.detect_language(file_path)
      end
      module_function :detect_language

      def render_markdown_to_html(md_text)
        MarkdownTransformer.render_markdown_to_html(md_text)
      end
      module_function :render_markdown_to_html

      def transform_links_to_footnotes(md_text)
        MarkdownTransformer.transform_links_to_footnotes(md_text)
      end
      module_function :transform_links_to_footnotes

      def normalize_book_card_md(md_text)
        MarkdownTransformer.normalize_book_card_md(md_text)
      end
      module_function :normalize_book_card_md

      def convert_book_card_inner_markdown(content)
        MarkdownTransformer.convert_book_card_inner_markdown(content)
      end
      module_function :convert_book_card_inner_markdown

      def pipe_table_to_html(md_text)
        MarkdownTransformer.pipe_table_to_html(md_text)
      end
      module_function :pipe_table_to_html

      def convert_table_rotate_inner_markdown(content)
        MarkdownTransformer.convert_table_rotate_inner_markdown(content)
      end
      module_function :convert_table_rotate_inner_markdown

      def format_book_card_inner_html(inner_html)
        MarkdownTransformer.format_book_card_inner_html(inner_html)
      end
      module_function :format_book_card_inner_html

      def convert_container_blocks(content, class_name:)
        MarkdownTransformer.convert_container_blocks(content, class_name: class_name)
      end
      module_function :convert_container_blocks

      def convert_table_container_inner_markdown(content, class_name)
        MarkdownTransformer.convert_table_container_inner_markdown(content, class_name)
      end
      module_function :convert_table_container_inner_markdown

      def process_code_include(content, source_filename: nil)
        MarkdownTransformer.process_code_include(content, source_filename: source_filename)
      end
      module_function :process_code_include

      # ================================================================
      # 画像生成関連メソッド (ImageGenerator への委譲)
      # ================================================================
      def generate_frontispiece_and_ornament_from(image_spec, **)
        ImageGenerator.generate_frontispiece_and_ornament_from(image_spec, **)
      end
      module_function :generate_frontispiece_and_ornament_from

      def ensure_variant_generated(source_path, variant)
        ImageGenerator.ensure_variant_generated(source_path, variant)
      end
      module_function :ensure_variant_generated

      # ================================================================
      # クロスリファレンス関連メソッド (MarkdownTransformer への委譲)
      # ================================================================
      def process_cross_references(chapters)
        MarkdownTransformer.process_cross_references(chapters)
      end
      module_function :process_cross_references

      # 全章ファイルのクロスリファレンス処理を一括実行
      # @param md_files [Array<String>] 処理対象ファイル（プロジェクトルート直下 .md）の配列
      def process_cross_references_for_files(md_files)
        md_files = md_files.reject { |path| File.basename(path) == '99-colophon.md' }
        return true if md_files.empty?

        Common.log_info('=== クロスリファレンス処理を開始 ===')

        # ------------------------------------------------
        # Phase 1: catalog.yml 登録済みの全章からラベル定義を収集
        # ------------------------------------------------
        all_labels = []
        all_errors = []

        # catalog.yml 登録済みの全章を対象とする（未登録草稿は除外）
        catalog_entries = TokenResolver::Resolver.new.resolve.select(&:in_catalog?)
        contents_files = catalog_entries.map(&:path).select { |p| File.exist?(p) }
        Common.log_info("ラベル収集対象ファイル: #{contents_files.size}件")

        contents_files.each do |md_path|
          filename = File.basename(md_path)
          content = File.read(md_path, encoding: 'utf-8')
          chapter_number = CrossReferenceProcessor.display_chapter_number_for_filename(filename)

          result = CrossReferenceProcessor.collect_labels(content, filename, chapter_number)
          all_labels.concat(result[:labels])
          all_errors.concat(result[:errors])
        end

        # ------------------------------------------------
        # Phase 2: ラベルマップ構築 & 重複チェック
        # ------------------------------------------------
        map_result = CrossReferenceProcessor.build_labels_map_with_duplicates_check(all_labels)
        labels_map = map_result[:labels_map]
        duplicates_by_id = map_result[:duplicates_by_id]

        if duplicates_by_id.any?
          duplicates_by_id.each do |_id, labels|
            first = labels.first
            by_file = labels.group_by(&:source_file)
            detail_lines = by_file.map do |file, file_labels|
              "#{file}: #{file_labels.map(&:line).join(', ')}"
            end
            Common.log_error(
              "#{first.source_file}:#{first.line} - ラベルID '#{first.title} @#{first.id}' は重複しています",
              detail: "重複箇所: #{detail_lines.join("\n          ")}"
            )
            all_errors << "ラベルID '@#{first.id}' 重複"
          end
          # 重複があっても先勝ちのラベルマップで処理を続行する
        end

        # ------------------------------------------------
        # Phase 3: 対象のルート直下 .md に対してのみ変換を適用
        # ------------------------------------------------
        processed_chapters = {}

        md_files.each do |md_file|
          filename = File.basename(md_file)
          next unless File.exist?(filename)

          content = File.read(filename, encoding: 'utf-8')

          # キャプション付きブロックをHTML化
          transformed = CrossReferenceProcessor.transform_captioned_blocks(content, filename, labels_map)

          # 本文中の @id を番号付きテキストに置換
          # - 実際の置換はプロジェクトルート直下の .md に対して実行
          # - 警告用の行番号は contents/ 配下の元Markdownに対して計算してログ出力する

          # 1) contents/ 側で未定義参照を検出（警告・行番号用）
          contents_path = File.join(Common::CONTENTS_DIR, filename)
          logging_errors = []
          if File.exist?(contents_path)
            source_content = File.read(contents_path, encoding: 'utf-8')
            logging_result = CrossReferenceProcessor.replace_references(source_content, labels_map, contents_path)
            logging_errors = logging_result[:errors]
          end

          # 2) ルート直下 .md に対して置換を適用（こちらのエラーは行番号がずれるため無視）
          ref_result = CrossReferenceProcessor.replace_references(transformed, labels_map, nil)
          processed_chapters[filename] = ref_result[:content]

          # 3) エラー集計とログは contents/ 側の行番号に基づく
          all_errors.concat(logging_errors)

          next unless logging_errors.any?

          Common.log_warn(" #{filename}: #{logging_errors.size}個の未定義参照を検出")
          logging_errors.each do |msg|
            Common.log_warn("    - #{msg}")
          end
        end

        # ------------------------------------------------
        # Phase 4: 孤立ID検出（定義されているが一度も参照されていないID）
        # contents/ 全ファイルを対象に使用済みIDを収集し、未参照ラベルを警告する
        # ------------------------------------------------
        all_used_ids = Set.new
        contents_files.each do |md_path|
          source_content = File.read(md_path, encoding: 'utf-8')
          result = CrossReferenceProcessor.replace_references(source_content, labels_map, nil)
          all_used_ids.merge(result[:used_ids])
        end

        orphan_labels = labels_map.values.reject { |label| all_used_ids.include?(label.id) || label.auto }
        orphan_labels.each do |label|
          Common.log_warn(
            "#{label.source_file}:#{label.line} - 孤立ラベル '#{label.title} @#{label.id}' は未参照です"
          )
        end

        # 処理済みのファイルを書き戻す（プロジェクトルート直下の .md）
        processed_chapters.each do |filename, content|
          File.write(filename, content, encoding: 'utf-8')
          Common.log_success("更新: #{filename}")
        end

        Common.log_success("\n=== クロスリファレンス処理が完了しました ===")
        Common.log_info("検出ラベル数: #{all_labels.size}個")
        Common.log_info("エラー数: #{all_errors.size}個")

        true
      end
      module_function :process_cross_references_for_files
    end
  end
end
