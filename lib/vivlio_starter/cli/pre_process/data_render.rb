# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/data_render.rb
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
require_relative 'data_image_resolver'
require_relative 'issue_registry'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # QueryStream 記法を展開してMarkdownを生成するモジュール
      # 実処理は query-stream gem に委譲する
      module DataRender
        module_function

        # Markdown コンテンツ内の QueryStream 記法をすべて展開する
        # @param content [String] Markdown コンテンツ
        # @param source_filename [String] エラー報告用のソースファイル名
        # @param chapter_slug [String, nil] 章スラッグ（データ画像の章ローカル探索に使う。nil ならデータ画像解決なし）
        # @param data_dir [String] データディレクトリのパス
        # @param templates_dir [String] テンプレートディレクトリのパス
        # @return [String] 展開後の Markdown コンテンツ
        def process(content, source_filename: nil, chapter_slug: nil, data_dir: Common.data_dir,
                    templates_dir: Common::TEMPLATES_DIR)
          # gem 側はログを出力しないため、on_error / on_warning コールバックでメッセージを構成する。
          # Common.log_error / log_warn が 🔴 / 🟡 の絵文字プレフィックスを付与するため、
          # コールバック側ではプレフィックスを付けない。
          # 章別サマリーへの記録（preflight-chapter-summary-spec.md §2.2）。
          # 章は処理中のファイルそのもの、行は location（"file:line"）から取る
          # （location を持たない一般エラー・警告もあるため respond_to? で確かめる）。
          record_issue = lambda do |severity, subject|
            location = subject.respond_to?(:location) ? subject.location : nil
            IssueRegistry.record(
              chapter: source_filename, line: line_from_location(location),
              severity:, category: :query_stream, message: subject.message
            )
          end

          on_error = lambda do |error|
            record_issue.call(:error, error)
            case error
            in QueryStream::TemplateNotFoundError => e
              # location は "filename:line" 形式
              detail_lines = ["雛形の場所: #{e.template_path}"]
              detail_lines << "ヒント: #{e.hint}" if e.hint
              Common.log_error(
                "#{e.location} - 雛形ファイル '#{File.basename(e.template_path)}' が見つかりません（記法: #{e.query}）",
                detail: detail_lines.join("\n")
              )
            in QueryStream::DataNotFoundError => e
              Common.log_error(
                "#{e.location} - データファイルが見つかりません（記法: #{e.query}）",
                detail: "データの場所: #{e.expected_path}"
              )
            in QueryStream::UnknownKeyError => e
              Common.log_error(
                "#{e.location} - 雛形に無いキーが書かれています: =#{e.key_path}",
                detail: unknown_key_detail(e)
              )
            else
              Common.log_error("QueryStream 展開エラー: #{error.message}")
            end
          end

          on_warning = lambda do |warning|
            record_issue.call(:warn, warning)
            case warning
            in QueryStream::NoResultWarning => w
              Common.log_warn(
                "#{w.location} - 一件検索で該当レコードが見つかりません（記法: #{w.query}）"
              )
            in QueryStream::AmbiguousQueryWarning => w
              Common.log_warn(
                "#{w.location} - 一件検索で複数件ヒット（#{w.count} 件）。条件を明示してください（記法: #{w.query}）"
              )
            else
              Common.log_warn("QueryStream 警告: #{warning.message}")
            end
          end

          # QueryStream 展開結果内の素ファイル名画像を data/ 配下から解決する後段フィルタ。
          # gem は画像を知らないため、この post_render で vivlio-starter 固有の解決を担う（spec §3.3）。
          # chapter_slug が無い（単体テスト等）ときは解決を行わず素通しする。
          post_render = nil
          if chapter_slug
            post_render = lambda do |text, ctx|
              DataImageResolver.rewrite(text, ctx, chapter_slug:)
            rescue StandardError => e
              Common.log_warn("データ画像の解決に失敗しました: #{e.class}: #{e.message}")
              text
            end
          end

          QueryStream.render(
            content,
            source_filename:,
            data_dir:,
            templates_dir:,
            on_error:,
            on_warning:,
            post_render:
          )
        end

        # QueryStream の location（"21-images.md:42"）から行番号だけを取り出す。
        # 章はコールバック側で source_filename を使うため、ここでは行のみを見る。
        # @return [Integer, nil]
        def line_from_location(location)
          location.to_s[/:(\d+)\z/, 1]&.to_i
        end

        # 雛形の打ち間違いをどう直せばよいかを著者へ示す。
        # gem が持つのは素材（無いキー・使えるキー・雛形のパス）までで、そこから
        # 「もしかして」を組み立てられるのは、著者向けの言葉づかいを担うこちら側だけである。
        # ドット記法（=author.name）は先頭のキーだけが検証対象なので、候補も先頭で探す。
        # @param error [QueryStream::UnknownKeyError]
        # @return [String]
        def unknown_key_detail(error)
          keys = error.available_keys.map(&:to_s)
          root = error.key_path.to_s.split('.').first
          near = DidYouMean::SpellChecker.new(dictionary: keys).correct(root).first

          detail = []
          # 記法の位置（見出し行の location）ではなく雛形を直すので、開くべきファイルを名指しする
          detail << "直す場所: #{error.template_path}" if error.template_path
          detail << "→ もしかして: =#{root} ではなく =#{near} ではありませんか？" if near
          detail << "この雛形で使えるキー: #{keys.join(', ')}"
          detail.join("\n")
        end
      end
    end
  end
end
