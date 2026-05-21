# frozen_string_literal: true

require 'fileutils'
require 'yaml'

require_relative 'common'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'import/markdown_converter'
require_relative 'import/image_processor'
require_relative 'import/yaml_processor'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: import（Re:VIEW Starter からの移行）
    # ================================================================
    # 責務:
    #   Re:VIEW Starter プロジェクトから vivlio-starter への移行処理を行う。
    #
    # 処理内容:
    #   1. 既存ディレクトリ（contents/, images/, codes/）の削除
    #   2. .re → .md 変換（Starter 付属スクリプト使用）
    #   3. 画像の WebP 変換（ResizeCommands 使用）
    #   4. source/ → codes/ コピー
    #   5. catalog.yml / config.yml の変換
    #
    # 依存:
    #   - ResizeCommands: 画像最適化
    #   - Common: ログ出力
    # ================================================================
    module ImportCommands
      module_function

      IMPORT_DESC = {
        default: {
          short: 'Re:VIEW Starter プロジェクトをインポートします',
          long: <<~DESC
            Re:VIEW Starter プロジェクトを vivlio-starter にインポートします。

            引数:
              STARTER_DIR    Re:VIEW Starter プロジェクトのディレクトリ（必須）

            オプション:
              --force    確認プロンプトをスキップ

            使用例:
              vs import ../review_starter_project
              vs import --force ../review_starter_project
          DESC
        }
      }.freeze

      # メイン実行メソッド
      def execute_import(starter_dir, options = {})
        @options = options
        @starter_dir = File.expand_path(starter_dir)

        validate_starter_directory!
        return 1 unless confirm_cleanup_or_force?

        cleanup_existing_directories!
        convert_re_to_md!
        Import::ImageProcessor.convert_to_webp!(@starter_dir)
        copy_source_to_codes!
        Import::YamlProcessor.convert_catalog!(@starter_dir)
        convert_config_with_cover!

        Common.log_success('インポートが完了しました')
        0
      rescue StandardError => e
        Common.log_error("インポート中にエラーが発生しました: #{e.message}")
        Common.log_error(e.backtrace.join("\n")) if ENV['VS_DEBUG']
        1
      end

      # Starter ディレクトリの検証
      def validate_starter_directory!
        raise "Starter ディレクトリが見つかりません: #{@starter_dir}" unless Dir.exist?(@starter_dir)

        # 必須スクリプトの存在確認
        markdownmaker = File.join(@starter_dir, 'lib/ruby/review-markdownmaker.rb')
        markdownbuilder = File.join(@starter_dir, 'lib/ruby/review-markdownbuilder.rb')

        raise "変換スクリプトが見つかりません: #{markdownmaker}" unless File.exist?(markdownmaker)

        raise "変換スクリプトが見つかりません: #{markdownbuilder}" unless File.exist?(markdownbuilder)

        Common.log_info("Starter ディレクトリ: #{@starter_dir}")
      end

      # 確認プロンプトまたは --force
      def confirm_cleanup_or_force?
        return true if @options[:force]

        dirs_to_delete = %w[contents images codes].select do |dir|
          Dir.exist?(dir)
        end

        if dirs_to_delete.empty?
          Common.log_info('削除対象のディレクトリはありません')
          return true
        end

        Common.log_warn('以下のディレクトリを削除してインポートを行います:')
        dirs_to_delete.each { |d| Common.log_warn("  - #{d}/") }

        print '続行しますか？ [y/N]: '
        return false unless $stdin.tty?

        ans = $stdin.gets
        return false unless ans && ans.strip.downcase == 'y'

        true
      end

      # 既存ディレクトリの削除
      def cleanup_existing_directories!
        Common.log_action('[Step 1] 既存ディレクトリを削除します')

        %w[contents images codes].each do |dir|
          next unless Dir.exist?(dir)

          FileUtils.rm_rf(dir)
          Common.log_info("  削除: #{dir}/")

          # ディレクトリを再作成
          FileUtils.mkdir_p(dir)
        end
      end

      # .re → .md 変換
      def convert_re_to_md!
        Common.log_action('[Step 2] .re → .md 変換を実行します')

        # temp ディレクトリを準備
        temp_dir = 'temp'
        FileUtils.mkdir_p(temp_dir)

        # Starter ディレクトリで rake markdown を実行
        Dir.chdir(@starter_dir) do
          config_file = File.join(@starter_dir, 'config.yml')
          raise "config.yml が見つかりません: #{config_file}" unless File.exist?(config_file)

          # bookname を取得して出力ディレクトリを特定
          config = YAML.safe_load_file(config_file, permitted_classes: [Symbol])
          bookname = config['bookname'] || 'book'
          md_output_dir = "#{bookname}-md"

          # 既存の md 出力ディレクトリがあればそれを使用、なければ rake markdown を実行
          if Dir.exist?(md_output_dir) && !Dir.glob(File.join(md_output_dir, '*.md')).empty?
            Common.log_info("  既存の #{md_output_dir}/ を使用します")
          else
            # rake markdown を実行
            Common.log_info('  rake markdown を実行中...')
            # RUBYOPT をクリアして環境の競合を回避
            env = { 'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil }
            system(env, 'rake', 'markdown')

            # 生成された md ファイルを確認
            unless Dir.exist?(md_output_dir) && !Dir.glob(File.join(md_output_dir, '*.md')).empty?
              raise "Markdown 出力ディレクトリが見つからないか空です: #{md_output_dir}\n" \
                    "手動で `cd #{@starter_dir} && rake markdown` を実行してから再度インポートしてください。"
            end
          end
          Common.log_info("  #{Dir.glob(File.join(md_output_dir, '*.md')).size} 個の Markdown ファイルを検出しました")

          @md_output_dir = md_output_dir
        end

        # vivlio-starter の temp にコピー
        starter_md_dir = File.join(@starter_dir, @md_output_dir)
        vivlio_root = Dir.pwd
        Dir.chdir(vivlio_root) do
          Dir.glob(File.join(starter_md_dir, '*.md')).each do |md_file|
            FileUtils.cp(md_file, temp_dir)
            Common.log_info("  コピー: #{File.basename(md_file)} → temp/")
          end

          # 追従変換を実行
          Import::MarkdownConverter.process!(temp_dir)

          # contents/ に移動
          Dir.glob(File.join(temp_dir, '*.md')).each do |md_file|
            dest = File.join('contents', File.basename(md_file))
            FileUtils.mv(md_file, dest)
            Common.log_info("  移動: #{File.basename(md_file)} → contents/")
          end

          # temp を削除
          FileUtils.rm_rf(temp_dir)
          Common.log_info('  temp/ を削除しました')
        end

        cleanup_starter_markdown_dir!
      end

      # source/ → codes/ コピー
      def copy_source_to_codes!
        Common.log_action('[Step 4] source/ → codes/ をコピーします')

        starter_source = File.join(@starter_dir, 'source')
        unless Dir.exist?(starter_source)
          Common.log_info('  source/ ディレクトリが見つかりません（スキップ）')
          return
        end

        FileUtils.cp_r(Dir.glob(File.join(starter_source, '*')), 'codes/')
        Common.log_info('  source/ の内容を codes/ にコピーしました')
      end

      # config.yml / config-starter.yml の変換と表紙 PDF のコピー
      #
      # config-starter.yml に frontcover_pdffile の指定がある場合、
      # 表紙 PDF を covers/ にコピーし、book.yml の output.cover.front を更新する
      def convert_config_with_cover!
        Common.log_action('[Step 6] config.yml を変換します')

        # 基本的な設定変換
        Import::YamlProcessor.convert_config!(@starter_dir)

        # 表紙 PDF の処理
        starter_config_starter = File.join(@starter_dir, 'config-starter.yml')
        return unless File.exist?(starter_config_starter)

        config_starter = YAML.safe_load_file(starter_config_starter, permitted_classes: [Symbol])
        cover_filename = config_starter.dig('starter', 'frontcover_pdffile')
        return unless cover_filename

        # PDF のみ対応
        unless cover_filename.downcase.end_with?('.pdf')
          Common.log_info("  表紙ファイル #{cover_filename} は PDF ではないためスキップします")
          return
        end

        # 表紙 PDF をコピー
        return unless Import::ImageProcessor.copy_front_cover!(@starter_dir, cover_filename)

        # book.yml の output.cover.front を Vivlio 既定の frontcover_rgb.pdf に合わせる
        Import::YamlProcessor.update_cover_config!('frontcover_rgb.pdf')
        Common.log_info('  config/book.yml の output.cover.front を frontcover_rgb.pdf に更新しました')
      end

      def cleanup_starter_markdown_dir!
        return unless @starter_dir && @md_output_dir

        md_dir = File.join(@starter_dir, @md_output_dir)
        return unless Dir.exist?(md_dir)

        FileUtils.rm_rf(md_dir)
        Common.log_info("  #{@md_output_dir}/ を削除しました（Starter 側）")
      rescue StandardError => e
        Common.log_warn("  #{@md_output_dir}/ の削除に失敗しました: #{e.message}")
      end
    end
  end
end
