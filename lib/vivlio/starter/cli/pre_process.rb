# frozen_string_literal: true

# ================================================================
# Module: Markdown前処理オーケストレーター
# ----------------------------------------------------------------
# 【役割】
# - Markdownファイルの前処理パイプラインを統括
# - 各処理モジュールを読み込み、Thorコマンドとして公開
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
# - ImageGenerator: waifu2x連携画像生成
# - MarkdownTransformer: Markdown→HTML変換
# - ImagePathNormalizer: 画像パス正規化・プレースホルダー生成
# - MarkdownPreprocessor: 前処理パイプライン実行
# ================================================================

require_relative 'common'
require_relative 'pre_process/markdown_preprocessor'
require_relative 'pre_process/frontmatter_generator'
require_relative 'pre_process/css_updater'
require_relative 'pre_process/theme_image_resolver'
require_relative 'pre_process/image_generator'
require_relative 'pre_process/markdown_transformer'
require_relative 'pre_process/image_path_normalizer'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: PreProcessCommands
      # ----------------------------------------------------------------
      # Markdown前処理のThorコマンド群とヘルパーメソッドを提供
      # ================================================================
      module PreProcessCommands
        module_function

        # テーマ画像のデフォルトパス定数
        FRONTISPIECE_DEFAULT_PATH = ThemeImageResolver::FRONTISPIECE_DEFAULT_PATH
        ORNAMENT_DEFAULT_PATH = ThemeImageResolver::ORNAMENT_DEFAULT_PATH

        PRE_PROCESS_DESC = {
          short: 'Markdownファイルの前処理を行います',
          long: <<~DESC
            指定した Markdown ファイルの前処理を行います。指定が無い場合は contents/ 配下の全 .md を対象にします。

            処理内容:
            - フロントマターの生成/更新
            - 画像パスの修正
            - ソースコードインクルード
            - book-card/table-rotate ブロックの変換
            - リンクの脚注化

            例:
              vs pre_process 11-install
              vs pre_process 11-install.md 12-tutorial
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'pre_process [TOKENS...]', PRE_PROCESS_DESC[:short]
            long_desc PRE_PROCESS_DESC[:long]
            
            def pre_process(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]

              # 引数を正規化
              files = Common.normalize_tokens(tokens)

              # 処理対象のファイルを決定
              md_files = if files.any?
                           # 存在しないファイルをチェック
                           missing_files = files.reject { |f| File.exist?("#{Common::CONTENTS_DIR}/#{f}.md") }
                           if missing_files.any?
                             Common.log_error("エラー: 次のファイルが存在しません: #{missing_files.join(', ')}")
                             Common.log_warn('前処理を中止します')
                             exit(1)
                           end
                           files.map { |f| "#{Common::CONTENTS_DIR}/#{f}.md" }
                         else
                           # 引数がない場合は全Markdownファイルを処理
                           Dir.glob("#{Common::CONTENTS_DIR}/*.md")
                         end

              # 各Markdownファイルを処理
              Common.log_action('Markdownファイルの前処理を行っています...')
              md_files.each do |md_file|
                process_single_markdown_file(md_file)
              end

              Common.log_success('Markdownの前処理が完了しました')
            end
          end
        end

        # ================================================================
        # 単一Markdownファイルを処理
        # ----------------------------------------------------------------
        # MarkdownPreprocessorを使って、1つのMarkdownファイルに対して
        # 前処理パイプラインを実行します。
        # ================================================================
        def process_single_markdown_file(md_file)
          MarkdownPreprocessor.new(md_file).run
        end

        # ================================================================
        # 以下、module_function として公開されたメソッド（後方互換性のため）
        # ----------------------------------------------------------------
        # 各モジュールのメソッドを委譲することで、既存コードとの互換性を維持
        # ================================================================
        module_function :process_single_markdown_file

        # ================================================================
        # フロントマター関連メソッド (FrontmatterGenerator への委譲)
        # ================================================================
        def generate_frontmatter(file_type, chapter_num = nil, existing_frontmatter = {})
          FrontmatterGenerator.generate_frontmatter(file_type, chapter_num, existing_frontmatter)
        end
        module_function :generate_frontmatter

        def apply_frontmatter(content, file_type, chapter_num)
          FrontmatterGenerator.apply_frontmatter(content, file_type, chapter_num)
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

        def process_code_include(content)
          MarkdownTransformer.process_code_include(content)
        end
        module_function :process_code_include

        # ================================================================
        # 画像生成関連メソッド (ImageGenerator への委譲)
        # ================================================================
        def generate_frontispiece_and_ornament_from(image_spec, **options)
          ImageGenerator.generate_frontispiece_and_ornament_from(image_spec, **options)
        end
        module_function :generate_frontispiece_and_ornament_from

        def ensure_variant_generated(source_path, variant)
          ImageGenerator.ensure_variant_generated(source_path, variant)
        end
        module_function :ensure_variant_generated
      end
    end
  end
end
