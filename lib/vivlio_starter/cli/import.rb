# frozen_string_literal: true

require 'fileutils'
require 'yaml'

require_relative 'common'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'import/markdown_converter'
require_relative 'import/image_processor'
require_relative 'import/yaml_processor'
require_relative 'import/sideimage_restorer'
require_relative 'upgrade'

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

      # 取り込みで空に戻す著者辞書（原稿を入れ替えるので中身が意味を失う）
      INDEX_DICTIONARY_FILES = [
        File.join('config', 'index_glossary_terms.yml'),
        File.join('config', 'index_glossary_rejected.yml')
      ].freeze

      # Re:VIEW Starter の表紙指定と、取り込み先のマスター画像の対応
      COVER_SIDES = [
        { key: 'frontcover_pdffile', master: CoverCommands::FRONTCOVER_MASTER, label: '表表紙' },
        { key: 'backcover_pdffile', master: CoverCommands::BACKCOVER_MASTER, label: '裏表紙' }
      ].freeze

      # メイン実行メソッド
      def execute_import(starter_dir, options = {})
        @options = options
        @starter_dir = File.expand_path(starter_dir)

        validate_starter_directory!
        return 1 unless confirm_cleanup_or_force?

        cleanup_existing_directories!
        reset_index_dictionaries!
        convert_re_to_md!
        Import::ImageProcessor.convert_to_webp!(@starter_dir)
        copy_source_to_codes!
        Import::YamlProcessor.convert_catalog!(@starter_dir)
        convert_config_with_cover!

        # 実績を添えて既定ログレベルでも報告する（vs build からは呼ばれない独立コマンド）
        chapters = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).size
        Common.log_result("インポートしました（contents/ に #{chapters} 章）", status: :success)
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
      end

      # 確認プロンプトまたは --force
      def confirm_cleanup_or_force?
        return true if @options[:force]

        dirs_to_delete = %w[contents images codes].select do |dir|
          Dir.exist?(dir)
        end

        return true if dirs_to_delete.empty?

        Common.log_warn('以下のディレクトリを削除してインポートを行います:')
        dirs_to_delete.each { |d| Common.log_warn("  - #{d}/") }

        # 非対話（パイプ/CI）では質問せず安全側に倒す
        return false unless $stdin.tty?

        Common.confirm?('続行しますか？')
      end

      # 取り込み先ディレクトリを空の状態で用意する。
      #
      # 「あれば作り直す」ではなく必ず作る——後段の move / cp は入れ物があることを
      # 前提にしており、contents/ を持たないプロジェクトへ取り込むと
      # `No such file or directory @ rb_file_s_rename` で落ちていた。
      def cleanup_existing_directories!
        %w[contents images codes].each do |dir|
          FileUtils.rm_rf(dir)
          FileUtils.mkdir_p(dir)
        end
      end

      # 索引・用語集の辞書を空に戻す。
      #
      # 辞書は「いま消した原稿」を説明するデータなので、contents/ と一緒に片付ける。
      # 残すと雛形の見本原稿の語が取り込んだ本の用語集・索引に載り、ビルドのたびに
      # 「原稿のどこにも出現しません」が並ぶ。空の初期形は vs upgrade が辞書の無い
      # プロジェクトへ配るものと同じ。取り込んだ原稿からは vs index:auto で作り直す。
      def reset_index_dictionaries!
        INDEX_DICTIONARY_FILES.each do |relative|
          next unless File.exist?(relative)

          File.write(relative, UpgradeCommands::EMPTY_DICTIONARY_TEMPLATES.fetch(relative), encoding: 'utf-8')
        end
        Common.log_info('  索引・用語集の辞書を空にしました（vs index:auto で取り込んだ原稿から作り直せます）')
      end

      # .re → .md 変換
      def convert_re_to_md!
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

          # 既存の md 出力ディレクトリがあればそれを使い、無ければ rake markdown を実行する
          unless Dir.exist?(md_output_dir) && !Dir.glob(File.join(md_output_dir, '*.md')).empty?
            # RUBYOPT をクリアして環境の競合を回避
            env = { 'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil }
            system(env, 'rake', 'markdown')

            # 生成された md ファイルを確認
            unless Dir.exist?(md_output_dir) && !Dir.glob(File.join(md_output_dir, '*.md')).empty?
              raise "Markdown 出力ディレクトリが見つからないか空です: #{md_output_dir}\n" \
                    "手動で `cd #{@starter_dir} && rake markdown` を実行してから再度インポートしてください。"
            end
          end

          @md_output_dir = md_output_dir
        end

        # vivlio-starter の temp にコピー
        starter_md_dir = File.join(@starter_dir, @md_output_dir)
        vivlio_root = Dir.pwd
        Dir.chdir(vivlio_root) do
          Dir.glob(File.join(starter_md_dir, '*.md')).each do |md_file|
            FileUtils.cp(md_file, temp_dir)
          end

          # 追従変換を実行
          Import::MarkdownConverter.process!(temp_dir)

          # //sideimage の囲みを戻す。画像パスが `![](foo.webp)` に揃ったあとに行う
          Import::SideimageRestorer.restore!(temp_dir, @starter_dir)

          # contents/ に移動
          Dir.glob(File.join(temp_dir, '*.md')).each do |md_file|
            dest = File.join('contents', File.basename(md_file))
            FileUtils.mv(md_file, dest)
          end

          # temp を削除
          FileUtils.rm_rf(temp_dir)
        end

        cleanup_starter_markdown_dir!
      end

      # source/ → codes/ コピー
      def copy_source_to_codes!
        starter_source = File.join(@starter_dir, 'source')
        return unless Dir.exist?(starter_source)

        FileUtils.cp_r(Dir.glob(File.join(starter_source, '*')), 'codes/')
      end

      # config.yml / config-starter.yml の変換と表紙 PDF の取り込み
      #
      # config-starter.yml の frontcover_pdffile / backcover_pdffile を
      # covers/ のマスター画像へ変換し、book.yml の output.cover を master に揃える。
      def convert_config_with_cover!
        # 基本的な設定変換
        Import::YamlProcessor.convert_config!(@starter_dir)

        # 表紙 PDF の処理
        starter_config_starter = File.join(@starter_dir, 'config-starter.yml')
        return unless File.exist?(starter_config_starter)

        config_starter = YAML.safe_load_file(starter_config_starter, permitted_classes: [Symbol])
        imported = COVER_SIDES.map { import_cover_side!(config_starter, it) }
        return if imported.none?

        Import::YamlProcessor.use_master_cover!
      end

      # 表紙 1 面を取り込む。
      #
      # 取り込めなかった面は雛形の見本画像がそのまま本の表紙になってしまうので、
      # 差し替え先のパスを添えて知らせる。
      #
      # @return [Boolean] 取り込めたら true
      def import_cover_side!(config_starter, side)
        imported = Import::ImageProcessor.import_master_cover!(
          @starter_dir, config_starter.dig('starter', side[:key]),
          master: side[:master], label: side[:label]
        )
        return true if imported

        Common.log_warn("  #{side[:label]}は雛形の見本画像のままです。",
                        detail: "対処: covers/#{side[:master]} を自分の#{side[:label]}画像に置き換えてください。")
        false
      end

      def cleanup_starter_markdown_dir!
        return unless @starter_dir && @md_output_dir

        md_dir = File.join(@starter_dir, @md_output_dir)
        return unless Dir.exist?(md_dir)

        FileUtils.rm_rf(md_dir)
      rescue StandardError => e
        Common.log_warn("  #{@md_output_dir}/ の削除に失敗しました: #{e.message}")
      end
    end
  end
end
