# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/data_render.rb
# ================================================================
# 責務:
#   query-stream gem への薄いラッパー。
#   QueryStream 記法を検出し、データファイルとテンプレートを用いて
#   Markdown を生成する。pre_process パイプラインの一部として動作する。
#
# 実装は query-stream gem に委譲し、Vivlio Starter 固有の
# 設定（データ/テンプレートディレクトリ、ロガー）を注入する。
# ================================================================

require 'query_stream'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # QueryStream 記法を展開してMarkdownを生成するモジュール
        # 実処理は query-stream gem に委譲する
        module DataRender
          module_function

          # Markdown コンテンツ内の QueryStream 記法をすべて展開する
          # @param content [String] Markdown コンテンツ
          # @param source_filename [String] エラー報告用のソースファイル名
          # @param data_dir [String] データディレクトリのパス
          # @param templates_dir [String] テンプレートディレクトリのパス
          # @return [String] 展開後の Markdown コンテンツ
          def process(content, source_filename: nil, data_dir: 'data', templates_dir: Common::TEMPLATES_DIR)
            # gem 側はログを出力しないため、on_error / on_warning コールバックでメッセージを構成する。
            # Common.log_error / log_warn が ❌ / ⚠️ の絵文字プレフィックスを付与するため、
            # コールバック側ではプレフィックスを付けない。
            on_error = lambda do |error|
              case error
              in QueryStream::TemplateNotFoundError => e
                Common.log_error("QueryStream 展開エラー: テンプレートファイルが見つかりません: #{e.template_path}")
                Common.log_error("   記法: #{e.query} (#{e.location})")
                Common.log_error("   ヒント: #{e.hint}") if e.hint
              in QueryStream::DataNotFoundError => e
                Common.log_error("QueryStream 展開エラー: データファイルが見つかりません: #{e.expected_path}")
                Common.log_error("   記法: #{e.query} (#{e.location})")
              else
                Common.log_error("QueryStream 展開エラー: #{error.message}")
              end
            end

            on_warning = lambda do |warning|
              case warning
              in QueryStream::NoResultWarning => w
                Common.log_warn("QueryStream 一件検索: 該当レコードが見つかりません")
                Common.log_warn("   記法: #{w.query} (#{w.location})")
              in QueryStream::AmbiguousQueryWarning => w
                Common.log_warn("QueryStream 一件検索: 複数件ヒット（#{w.count} 件）。条件を明示してください")
                Common.log_warn("   記法: #{w.query} (#{w.location})")
              else
                Common.log_warn("QueryStream 警告: #{warning.message}")
              end
            end

            QueryStream.render(
              content,
              source_filename:,
              data_dir:,
              templates_dir:,
              on_error:,
              on_warning:
            )
          end
        end
      end
    end
  end
end
