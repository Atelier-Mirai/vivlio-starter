# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/epub.rb
# ================================================================
# 責務:
#   Vivliostyle CLI を --format epub で実行し EPUB を生成する。
#   EPUB 専用の vivliostyle.config.epub.js を参照してビルドする。
#
# 仕様書: docs/specs/epub_output_spec.md
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
      #   - :verbose [Boolean] 詳細ログ出力
      # @param target_output [String, nil] 出力ファイル名（リネーム先）
      # @return [Boolean] ビルド成功なら true
      def execute_epub(options, target_output = nil)
        EpubCommandRunner.new(options, target_output).call
      end

      # Vivliostyle CLI を --format epub で実行して EPUB を生成する
      class EpubCommandRunner
        def initialize(options, target_output = nil)
          @options = options || {}
          @target_output = target_output
          @build_success = false
        end

        # EPUB ビルドを実行し、成功時にリネームする
        # @return [Boolean] ビルド成功なら true
        def call
          apply_verbose
          Common.log_action('EPUB を生成しています…')
          execute_build
          handle_build_result
          @build_success
        end

        private

        attr_reader :options, :target_output

        # verbose モードを有効化する
        def apply_verbose
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        # Vivliostyle CLI を実行して EPUB を生成する
        def execute_build
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          @build_success = if quiet_mode?
                             system(build_command, out: File::NULL, err: File::NULL)
                           else
                             system(build_command)
                           end

          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          Common.log_info(format('[epub] vivliostyle build 所要時間: %.2fs', elapsed))
          Common.record_vivliostyle_build(elapsed, Common.current_step_label)
        end

        # quiet モードが有効かどうか返す
        def quiet_mode?
          (ENV['VIVLIO_QUIET'] == '1') || Common.truthy?(Common::CONFIG.vivliostyle.quiet)
        end

        # EPUB ビルド用のコマンド文字列を組み立てる
        # --config で EPUB 専用設定ファイルを指定する
        def build_command
          cmd = 'npx vivliostyle build'
          cmd += " --config #{Build::EpubBuilder::EPUB_CONFIG_FILE}"
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
          output = Build::EpubBuilder::EPUB_OUTPUT_FILE
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
