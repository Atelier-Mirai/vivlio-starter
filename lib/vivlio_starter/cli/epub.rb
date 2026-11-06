# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/epub.rb
# ================================================================
# 責務:
#   Vivliostyle CLI を --format epub で実行し EPUB を生成する。
#   EPUB 専用の vivliostyle.config.epub.js を参照してビルドする。
#
# 仕様書: epub_output_spec.md
#
# 依存:
#   - Build::EpubBuilder: EPUB 用中間ファイル生成
#   - Common: 設定読み込み・ログ出力
# ================================================================

require 'fileutils'

module VivlioStarter
  module CLI
    # EPUB 生成コマンドモジュール
    module EpubCommands
      module_function

      # EPUB 生成を実行する
      #
      # @param options [Hash] オプション
      # @param target_output [String, nil] 出力ファイル名（リネーム先）
      # @param config_path [String] --config で渡す生成 config のパス（消費者 dir 内・P4 §5.2）
      # @param output_path [String] config の output と一致する生成先（消費者 dir 内）
      # @return [Boolean] ビルド成功なら true
      def execute_epub(options, target_output = nil, config_path:, output_path:)
        EpubCommandRunner.new(options, target_output, config_path:, output_path:).call
      end

      # Vivliostyle CLI を --format epub で実行して EPUB を生成する
      class EpubCommandRunner
        def initialize(options, target_output = nil, config_path:, output_path:)
          @options = options || {}
          @target_output = target_output
          @config_path = config_path
          @output_path = output_path
          @build_success = false
        end

        # EPUB ビルドを実行し、成功時にリネームする
        # @return [Boolean] ビルド成功なら true
        def call
          Common.log_action('EPUB を生成しています…')
          execute_build
          handle_build_result
          @build_success
        end

        private

        attr_reader :options, :target_output, :config_path, :output_path

        # Vivliostyle CLI を実行して EPUB を生成する
        def execute_build
          @build_success = Common.run_vivliostyle_build(build_command, label: 'epub')
        end

        # EPUB ビルド用のコマンド文字列を組み立てる
        # --config で EPUB 専用設定ファイル（消費者 dir 内の生成 config）を指定する
        def build_command
          cmd = 'npx vivliostyle build'
          cmd += " --config #{config_path}"
          cmd
        end

        # ビルド結果に応じてログを出す
        def handle_build_result
          if @build_success
            handle_successful_build
          else
            Common.log_error('EPUB の生成に失敗しました')
          end
        end

        # 成功時の出力ファイル処理を行う
        def handle_successful_build
          output = output_path
          unless File.exist?(output)
            Common.log_warn("EPUB 生成は成功しましたが、出力ファイルが見つかりません: #{output}")
            return
          end

          return finalize_default_output(output) unless rename_requested?

          rename_output_file(output)
        end

        # リネーム指定があるかどうか返す
        def rename_requested?
          target_output && !target_output.to_s.strip.empty?
        end

        # 出力先をそのまま利用する際の後処理
        def finalize_default_output(path)
          Common.log_success('EPUB の生成が完了しました')
          Common.log_info("出力先: #{File.expand_path(path)}")
        end

        # 生成された EPUB をターゲットにリネームする
        def rename_output_file(output)
          return finalize_default_output(output) if File.expand_path(output) == File.expand_path(target_output)

          FileUtils.rm_f(target_output)
          FileUtils.mv(output, target_output)
          Common.log_success("EPUB の生成が完了しました（リネーム: #{output} → #{target_output}）")
          Common.log_info("出力先: #{File.expand_path(target_output)}")
        rescue StandardError => e
          Common.log_warn("EPUB のリネームに失敗しました: #{e}")
        end
      end
    end
  end
end
