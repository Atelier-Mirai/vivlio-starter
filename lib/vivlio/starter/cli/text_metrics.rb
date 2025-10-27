# frozen_string_literal: true

require 'json'
require 'pathname'
require 'yaml'

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

        # Thor ベースクラスへ text_metrics コマンドを登録する
        def included(base)
          base.class_eval do
            desc 'text_metrics [BASENAME ...]', TEXT_METRICS_DESC[:short]
            long_desc TEXT_METRICS_DESC[:long]
            option :json, type: :boolean, desc: '結果を JSON 形式で出力'
            option :yaml, type: :boolean, desc: '結果を YAML 形式で出力'

            # text_metrics サブコマンドのエントリポイント
            def text_metrics(*targets)
              Vivlio::Starter::CLI::TextMetricsCommands.execute_text_metrics(targets, options)
            end
          end
        end

        # text_metrics コマンドの処理を実行クラスに委譲する
        def execute_text_metrics(targets, options = {})
          TextMetricsRunner.new(targets, options).call
        end
        module_function :execute_text_metrics
      end

      # text_metrics 全体の制御フローを担う実行クラス
      class TextMetricsRunner
        # 対象トークンとオプションを初期化する
        def initialize(targets, options)
          @targets = Array(targets)
          @options = options || {}
          @resolver = MarkdownResolver.new(@targets)
          @stat_builder = StatBuilder.new
        end

        # 対象ファイル解決から出力までの処理を一括実行する
        def call
          files = resolver.resolve
          return warn_no_targets if files.empty?

          stats = files.map { |path| stat_builder.build(path) }
          return output_json(stats) if json?
          return output_yaml(stats) if yaml?

          TablePrinter.new(stats).print
        end

        private

        attr_reader :targets, :options, :resolver, :stat_builder

        # 対象ファイルが無い場合の警告を出力する
        def warn_no_targets
          Common.log_warn('対象となる Markdown ファイルが見つかりません。')
        end

        # JSON 出力オプションが有効か判定する
        def json?
          options[:json]
        end

        # YAML 出力オプションが有効か判定する
        def yaml?
          options[:yaml]
        end

        # JSON 出力を整形して標準出力へ書き出す
        def output_json(stats)
          payload = { stats: stats }
          payload[:totals] = TotalsCalculator.calculate(stats) if stats.any?
          puts JSON.pretty_generate(payload)
        end

        # YAML 出力を構築して標準出力へ書き出す
        def output_yaml(stats)
          payload = { 'stats' => stats }
          payload['totals'] = TotalsCalculator.calculate(stats) if stats.any?
          puts payload.to_yaml
        end
      end

      # Markdown ファイルの探索とパス正規化を行う
      class MarkdownResolver
        # 指定されたターゲットトークンを受け取る
        def initialize(targets)
          @targets = targets
        end

        # 存在するパスのみを抽出し、プロジェクト相対パスに整形する
        def resolve
          paths = existing_paths
          warn_missing(paths[:missing])
          relativize(paths[:existing])
        end

        private

        attr_reader :targets

        # 既存パスと存在しないパスを振り分ける
        def existing_paths
          all_paths.partition { |path| File.exist?(path) }.then do |existing, missing|
            { existing: existing, missing: missing }
          end
        end

        # 指定ターゲットから検査する全パスを生成する
        def all_paths
          return glob_all if targets.empty?

          basenames = Common.normalize_tokens(targets)
          basenames.map { |name| File.join(Common::CONTENTS_DIR, "#{name}.md") }
        end

        # contents 以下の全 Markdown ファイルを列挙する
        def glob_all
          Dir.glob(File.join(Common::CONTENTS_DIR, '**', '*.md'))
        end

        # 存在しないパスについて警告を出力する
        def warn_missing(missing)
          missing.each { |path| Common.log_warn("見つかりません: #{path}") }
        end

        # パスをプロジェクトルートからの相対表記に変換する
        def relativize(paths)
          root = Pathname.new('.')
          paths.sort.map { |path| Pathname.new(path).cleanpath.relative_path_from(root).to_s }
        end
      end

      # 個別 Markdown の統計情報を構築する
      class StatBuilder
        # 単一ファイルから統計情報ハッシュを生成する
        def build(path)
          absolute = Pathname.new(path)
          absolute = Pathname.new('.') / path unless absolute.absolute?
          content = File.read(absolute, encoding: 'UTF-8')
          base_metrics(content).merge(sentence_metrics(content)).merge(clause_metrics(content)).merge('path' => path)
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
          Common.log_warn("エンコーディングエラーのためスキップします: #{path} (#{e.message})")
          blank_stat(path)
        end

        private

        # コンテンツの行数を数える
        def line_count(content)
          content.empty? ? 0 : content.each_line.count
        end

        # 行数・文字数などの基本統計を算出する
        def base_metrics(content)
          {
            'lines' => line_count(content),
            'chars' => content.length,
            'chars_without_newline' => content.delete("\r\n").length
          }
        end

        # 文単位の統計を算出する
        def sentence_metrics(content)
          sentences = sentence_segments(content)
          count = sentences.size
          total_chars = sentences.sum(&:length)
          {
            'sentences' => count,
            'avg_sentence_chars' => average(total_chars, count)
          }
        end

        # 句単位の統計を算出する
        def clause_metrics(content)
          clauses = clause_segments(content)
          count = clauses.size
          total_chars = clauses.sum(&:length)
          {
            'commas' => comma_count(content),
            'clauses' => count,
            'avg_clause_chars' => average(total_chars, count)
          }
        end

        # 文単位に分割し改行を除去した配列を返す
        def sentence_segments(content)
          content.split(/[。！？!?]+/).map { |segment| clean_segment(segment) }.reject(&:empty?)
        end

        # 読点単位に分割し改行を除去した配列を返す
        def clause_segments(content)
          content.split('、').map { |segment| clean_segment(segment) }.reject(&:empty?)
        end

        # 読点の出現数を数える
        def comma_count(content)
          content.count('、')
        end

        # 改行削除と前後空白除去を行う
        def clean_segment(segment)
          segment.delete("\r\n").strip
        end

        # 合計値と件数から平均を計算する
        def average(sum, count)
          count.positive? ? sum.fdiv(count) : 0.0
        end

        # 失敗時に空の統計情報を返す
        def blank_stat(path)
          {
            'path' => path,
            'lines' => 0,
            'chars' => 0,
            'chars_without_newline' => 0,
            'sentences' => 0,
            'avg_sentence_chars' => 0.0,
            'commas' => 0,
            'clauses' => 0,
            'avg_clause_chars' => 0.0
          }
        end
      end

      # 統計情報の合計を算出する
      class TotalsCalculator
        # 渡された統計配列を累積し合計値を返す
        def self.calculate(stats)
          TotalsAggregator.new(stats).result
        end

        # 集計処理本体
        class TotalsAggregator
          COUNT_KEYS = %w[lines chars chars_without_newline sentences commas clauses].freeze

          def initialize(stats)
            @stats = stats
            @totals = initial_totals
          end

          def result
            stats.each { |stat| accumulate(stat) }
            finalize_averages
            totals
          end

          private

          attr_reader :stats, :totals

          def accumulate(stat)
            COUNT_KEYS.each { |key| totals[key] += stat[key] }
            totals['sentence_char_sum'] += stat['avg_sentence_chars'] * stat['sentences']
            totals['clause_char_sum'] += stat['avg_clause_chars'] * stat['clauses']
          end

          def finalize_averages
            assign_sentence_average
            assign_clause_average
            cleanup_char_sums
          end

          def average(sum, count)
            count.positive? ? sum / count : 0.0
          end

          def initial_totals
            {
              'lines' => 0,
              'chars' => 0,
              'chars_without_newline' => 0,
              'sentences' => 0,
              'commas' => 0,
              'clauses' => 0,
              'avg_sentence_chars' => 0.0,
              'avg_clause_chars' => 0.0,
              'sentence_char_sum' => 0.0,
              'clause_char_sum' => 0.0
            }
          end

          def assign_sentence_average
            totals['avg_sentence_chars'] = average(totals['sentence_char_sum'], totals['sentences'])
          end

          def assign_clause_average
            totals['avg_clause_chars'] = average(totals['clause_char_sum'], totals['clauses'])
          end

          def cleanup_char_sums
            totals.delete('sentence_char_sum')
            totals.delete('clause_char_sum')
          end
        end
      end

      # 統計情報を表形式で出力する
      class TablePrinter
        HEADER_FORMAT = [
          '%-40s',
          '%10s',
          '%12s',
          '%18s',
          '%12s',
          '%9s',
          '%9s',
          '%10s',
          '%11s'
        ].join(' ').freeze

        ROW_FORMAT = [
          '%<path>-40s',
          '%<lines>10d',
          '%<chars>12d',
          '%<no_crlf>18d',
          '%<sentences>12d',
          '%<avg_sentence>9.2f',
          '%<commas>9d',
          '%<clauses>10d',
          '%<avg_clause>11.2f'
        ].join(' ').freeze

        HEADER_LABELS = {
          path: 'path',
          lines: 'lines',
          chars: 'chars',
          no_crlf: 'chars(no CR/LF)',
          sentences: 'sentences',
          avg_sentence: 'avg sent',
          commas: 'commas',
          clauses: 'clauses',
          avg_clause: 'avg clause'
        }.freeze

        # 表示対象の統計情報を保持する
        def initialize(stats)
          @stats = stats
          @header = build_header
          @divider = '-' * @header.length
        end

        # ヘッダーと各行・合計を順に出力する
        def print
          puts header
          puts divider
          stats.each { |stat| puts row(stat['path'], stat) }
          print_totals
        end

        private

        attr_reader :stats, :header, :divider

        # 合計行を出力する
        def print_totals
          puts divider
          totals = TotalsCalculator.calculate(stats)
          puts row('TOTAL', totals)
        end

        # 1 行分の文字列を整形して返す
        def row(label, stat)
          format(ROW_FORMAT,
                 path: label,
                 lines: stat['lines'],
                 chars: stat['chars'],
                 no_crlf: stat['chars_without_newline'],
                 sentences: stat['sentences'],
                 avg_sentence: stat['avg_sentence_chars'],
                 commas: stat['commas'],
                 clauses: stat['clauses'],
                 avg_clause: stat['avg_clause_chars'])
        end

        def build_header
          format(HEADER_FORMAT,
                 HEADER_LABELS[:path],
                 HEADER_LABELS[:lines],
                 HEADER_LABELS[:chars],
                 HEADER_LABELS[:no_crlf],
                 HEADER_LABELS[:sentences],
                 HEADER_LABELS[:avg_sentence],
                 HEADER_LABELS[:commas],
                 HEADER_LABELS[:clauses],
                 HEADER_LABELS[:avg_clause])
        end
      end
    end
  end
end
