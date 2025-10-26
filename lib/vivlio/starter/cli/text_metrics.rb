# frozen_string_literal: true

require 'json'
require 'pathname'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: TextMetricsCommands
      # ------------------------------------------------
      # Markdown コンテンツの行数・文字数などの統計を表示するコマンド群
      # 提供コマンド:
      #   - text_metrics [BASENAME ...]
      #     contents/ 以下の Markdown ファイルについて行数・文字数を集計
      # ------------------------------------------------
      module TextMetricsCommands
        module_function

        TEXT_METRICS_DESC = {
          short: 'Markdown の行数・文字数などを集計します',
          long: <<~DESC
            contents/ ディレクトリ以下の Markdown ファイルについて、行数と文字数を集計して一覧表示します。
            引数にベース名を指定すると、そのファイルのみを対象にします（拡張子省略可／contents/ 接頭辞可）。

            例:
              vs text_metrics            # 全 Markdown を対象
              vs text_metrics 11-install 21-customize
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'text_metrics [BASENAME ...]', TEXT_METRICS_DESC[:short]
            long_desc TEXT_METRICS_DESC[:long]
            option :json, type: :boolean, desc: '結果を JSON 形式で出力'
            option :yaml, type: :boolean, desc: '結果を YAML 形式で出力'

            def text_metrics(*targets)
              Vivlio::Starter::CLI::TextMetricsCommands.execute_text_metrics(targets, options)
            end
          end
        end

        def execute_text_metrics(targets, options = {})
          markdown_files = resolve_markdown_files(targets)
          if markdown_files.empty?
            Common.log_warn('対象となる Markdown ファイルが見つかりません。')
            return
          end

          stats = markdown_files.map { |path| build_stat(path) }

          if options[:json]
            payload = { stats: stats }
            payload[:totals] = totals(stats) if stats.any?
            puts JSON.pretty_generate(payload)
            return
          end

          if options[:yaml]
            payload = { 'stats' => stats }
            payload['totals'] = totals(stats) if stats.any?
            puts payload.to_yaml
            return
          end

          print_table(stats)
        end
        module_function :execute_text_metrics

        def resolve_markdown_files(targets)
          base_dir = Common::CONTENTS_DIR
          root = Pathname.new('.')

          paths = if targets.any?
                    basenames = Common.normalize_tokens(targets)
                    basenames.map { |name| File.join(base_dir, "#{name}.md") }
                  else
                    Dir.glob(File.join(base_dir, '**', '*.md'))
                  end

          missing = paths.reject { |path| File.exist?(path) }
          if missing.any?
            missing.each { |path| Common.log_warn("見つかりません: #{path}") }
            paths = paths.select { |path| File.exist?(path) }
          end

          paths.sort.map { |path| Pathname.new(path).cleanpath.relative_path_from(root).to_s }
        end
        module_function :resolve_markdown_files

        def build_stat(path)
          absolute = Pathname.new(path)
          absolute = Pathname.new('.') / path unless absolute.absolute?
          content = File.read(absolute, encoding: 'UTF-8')
          lines = content.empty? ? 0 : content.each_line.count
          chars_total = content.length
          chars_without_newline = content.delete("\r\n").length
          {
            'path' => path,
            'lines' => lines,
            'chars' => chars_total,
            'chars_without_newline' => chars_without_newline
          }
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
          Common.log_warn("エンコーディングエラーのためスキップします: #{path} (#{e.message})")
          {
            'path' => path,
            'lines' => 0,
            'chars' => 0,
            'chars_without_newline' => 0
          }
        end
        module_function :build_stat

        def totals(stats)
          stats.each_with_object({ 'lines' => 0, 'chars' => 0, 'chars_without_newline' => 0 }) do |stat, acc|
            acc['lines'] += stat['lines']
            acc['chars'] += stat['chars']
            acc['chars_without_newline'] += stat['chars_without_newline']
          end
        end
        module_function :totals

        def print_table(stats)
          header = 'path                                          lines        chars    chars(no CR/LF)'
          puts header
          puts '-' * header.length
          stats.each do |stat|
            puts format('%-40s %10d %12d %18d',
                        stat['path'], stat['lines'], stat['chars'], stat['chars_without_newline'])
          end

          total = totals(stats)
          puts '-' * header.length
          puts format('%-40s %10d %12d %18d', 'TOTAL', total['lines'], total['chars'], total['chars_without_newline'])
        end
        module_function :print_table
      end
    end
  end
end
