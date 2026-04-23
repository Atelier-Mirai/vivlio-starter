# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/preflight_command.rb
# ================================================================
# 責務:
#   Samovar CLI の preflight コマンドを実装する。
#   vs build の Step 1〜4 のみを実行し、PDF生成なしで原稿エラーを高速検出する。
#
# 実行内容:
#   Step 1: 画像最適化（--no-resize でスキップ）
#   Step 2: テーマ画像準備
#   Step 3: Markdown前処理（frontmatter・画像パス・QueryStream・コードインクルード・クロスリファレンス）
#   Step 4: 索引スキャン（index_glossary.enabled 時のみ）
#
# 終了コード:
#   0: エラーなし（警告のみ、または問題なし）
#   1: エラー1件以上、または実行時例外
# ================================================================

require_relative '../build'
require_relative '../build/pipeline'
require_relative '../pre_process'
require_relative '../token_resolver'
require_relative '../clean'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # preflight コマンドの Samovar 実装
        class PreflightCommand < Samovar::Command
          self.description = 'ビルド前の原稿エラーチェックを高速実行します'

          many :targets, 'チェック対象（章番号 / 範囲 / スラッグ）', default: []

          options do
            option '--[no]-resize', '画像最適化を行う（--no-resize で無効）', default: true, key: :resize
            option '--[no]-verify', 'リンク・画像の基本検証を実行する（--no-verify でスキップ）', default: true, key: :verify
            option '--verify-links', '外部 URL の HTTP 到達性チェックを実行する', default: false, key: :verify_links
            option '--log <level>', 'ログレベルを指定（error/warn/info/debug）', key: :log_level
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def initialize(input = nil, **)
            processed_input = if input
                                normalized = normalize_log_option_tokens(input)
                                if input.respond_to?(:replace) && !input.equal?(normalized)
                                  input.replace(normalized)
                                  input
                                else
                                  normalized
                                end
                              else
                                input
                              end
            super(processed_input, **)
          end

          def call
            if options[:help]
              print_usage
              return 0
            end

            PreProcessCommands::LinkImageValidator.reset!

            # 検証オプションをスレッドローカルに設定（LinkImageValidator が参照）
            setup_verify_options!

            entries = resolve_entries
            if entries.empty? && targets.any?
              Common.log_error('指定した章が catalog.yml に存在しません。preflight を中断します。')
              return 1
            end

            pipeline = BuildCommands::UnifiedBuildPipeline.new(self, entries: entries, mode: :preflight)
            pipeline.run

            # --verify-links 有効時のみ外部 URL チェックを実行
            PreProcessCommands::LinkImageValidator.check_external_urls!
            PreProcessCommands::LinkImageValidator.print_summary

            print_preflight_summary

            PreProcessCommands::LinkImageValidator.any_issues? ? 1 : 0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("Error: #{e.message}")
            1
          ensure
            # 前処理で生成した中間 .md ファイルを後始末する
            CleanCommands.execute_clean({})
            Thread.current[:vs_verify_options] = nil
          end

          private

          # CLI 引数から Entry 配列を解決する
          def resolve_entries
            resolver = TokenResolver::Resolver.new
            entries = resolver.resolve(targets)
            entries.select(&:in_catalog?)
          end

          # 検証オプションをスレッドローカルに設定する（BuildCommand と同一ロジック）
          def setup_verify_options!
            opts = {}
            if options[:verify] == false
              opts[:no_verify] = true
            else
              opts[:verify_images] = true
              opts[:verify_bare_urls] = true
              opts[:verify_external_links] = options[:verify_links] || false
            end
            Thread.current[:vs_verify_options] = opts
          end

          # preflight 完了サマリーを表示する
          def print_preflight_summary
            if PreProcessCommands::LinkImageValidator.any_issues?
              Common.log_result('Preflight 完了: 問題あり — 詳細は上記を確認してください', status: :failure)
            else
              Common.log_result('Preflight 完了: 問題なし', status: :success)
            end
          end

          # --log オプションのトークンを正規化する（BuildCommand と同一ロジック）
          def normalize_log_option_tokens(input)
            tokens = array_from_input(input)
            normalized = []
            idx = 0

            while idx < tokens.length
              token = tokens[idx]

              if token == '--log'
                normalized << '--log'
                next_value = tokens[idx + 1]
                if next_value.nil? || next_value.start_with?('-')
                  normalized << 'info'
                  idx += 1
                else
                  normalized << next_value
                  idx += 2
                  next
                end
              elsif token.start_with?('--log=')
                normalized << '--log'
                level = token.split('=', 2)[1]
                normalized << (level.nil? || level.empty? ? 'info' : level)
              else
                normalized << token
              end

              idx += 1
            end

            normalized
          end

          def print_usage
            puts <<~USAGE
              vs preflight - ビルド前の原稿エラーチェックを高速実行します

              Usage:
                vs preflight [targets...] [options]

              引数:
                targets...          チェック対象（章番号 / 範囲 / スラッグ）。省略時は全章

              オプション:
                --[no]-resize       画像最適化を行う（--no-resize で無効）         （既定: 有効）
                --[no]-verify       リンク・画像の基本検証を実行する（--no-verify でスキップ）（既定: 有効）
                --verify-links      外部 URL の HTTP 到達性チェックを実行する
                --log <level>       ログレベルを指定（error/warn/info/debug）
                -h, --help          このコマンドの使い方を表示

              終了コード:
                0: エラーなし（警告のみ、または問題なし）
                1: エラー1件以上、または実行時例外
            USAGE
          end

          def array_from_input(input)
            if input.is_a?(Array)
              input.dup
            elsif input.respond_to?(:to_a)
              input.to_a
            else
              Array(input)
            end
          end
        end
      end
    end
  end
end
