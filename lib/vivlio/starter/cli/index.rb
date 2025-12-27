# frozen_string_literal: true

# ================================================================
# Module: 索引機能オーケストレーター
# ----------------------------------------------------------------
# 【役割】
# - 索引機能のエントリポイント
# - IndexTermScanner と IndexPageBuilder を統括
# - CLI コマンド（vs index:scan, vs index:build）を提供
#
# 【処理の流れ】
# 1. vs index:scan: 原稿をスキャンして索引候補を抽出
# 2. vs index:build: 索引ページを生成
# 3. vs build: 通常ビルドに索引生成を統合
#
# 【依存モジュール】
# - IndexTermScanner: 索引語スキャン・ID付与
# - IndexPageBuilder: 索引ページHTML生成
# - YomiInferrer: MeCab による読み推測
# ================================================================

require_relative 'common'
require_relative 'index/index_term_scanner'
require_relative 'index/index_page_builder'
require_relative 'index/yomi_inferrer'
require_relative 'index/term_extractor'
require_relative 'index/scoring_engine'
require_relative 'index/hierarchical_index'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: IndexCommands
      # ----------------------------------------------------------------
      # 索引機能の CLI コマンド群とヘルパーメソッドを提供
      # ================================================================
      module IndexCommands
        module_function

        INDEX_SCAN_DESC = {
          short: '索引候補を自動抽出し、YAML を生成します',
          long: <<~DESC
            原稿をスキャンして索引候補を自動抽出します。

            処理内容:
            - [用語|読み] または [用語] 記法を検出
            - [用語] 形式の場合、MeCab で読みを自動推測
            - 検出結果を config/index_candidates.yml に出力

            例:
              vs index:scan
              vs index:scan --threshold 80
          DESC
        }.freeze

        INDEX_BUILD_DESC = {
          short: '索引ページを生成します',
          long: <<~DESC
            .cache/index_matches.yml から索引ページを生成します。

            処理内容:
            - 索引データを読み込み
            - 用語を五十音順でソート
            - _indexpage.html を生成

            例:
              vs index:build
              vs index:build --preview
          DESC
        }.freeze

        INDEX_EXTRACT_DESC = {
          short: '索引候補を自動抽出します（Phase 2）',
          long: <<~DESC
            原稿から索引候補を自動抽出し、スコアリングします。

            処理内容:
            - 定義パターン検出（「〜とは」など）
            - 専門用語パターン検出（カタカナ語、英字語）
            - MeCab による名詞連続抽出
            - TF-IDF スコアリング
            - config/index_candidates.yml に出力

            例:
              vs index:extract
              vs index:extract --threshold 60
          DESC
        }.freeze

        # 索引スキャンを実行
        # @param context_or_options [Hash] オプション
        # @param tokens [Array<String>] 対象章（省略時は全章）
        def execute_index_scan(context_or_options, tokens = [])
          opts = normalize_options(context_or_options)
          ENV['VERBOSE'] = '1' if opts[:verbose]

          chapters = resolve_chapters(tokens)

          Common.log_action('索引語のスキャンを開始します...')

          scanner = IndexTermScanner.new
          scanner.scan_all_chapters!(chapters)

          Common.log_success('索引スキャンが完了しました')
          report_scan_results(scanner)
        end

        # 索引ページを生成
        # @param context_or_options [Hash] オプション
        # @param _tokens [Array<String>] 未使用
        def execute_index_build(context_or_options, _tokens = [])
          opts = normalize_options(context_or_options)
          ENV['VERBOSE'] = '1' if opts[:verbose]

          Common.log_action('索引ページを生成します...')

          builder = IndexPageBuilder.new
          builder.build!

          Common.log_success('索引ページの生成が完了しました')
        end

        # 索引候補を自動抽出（Phase 2）
        # @param context_or_options [Hash] オプション
        # @param tokens [Array<String>] 対象章（省略時は全章）
        def execute_index_extract(context_or_options, tokens = [])
          opts = normalize_options(context_or_options)
          ENV['VERBOSE'] = '1' if opts[:verbose]

          threshold = opts[:threshold] || 50
          chapters = resolve_chapters(tokens)

          Common.log_action('索引候補の自動抽出を開始します...')

          extractor = TermExtractor.new
          extractor.extract_from_chapters!(chapters)
          extractor.export_candidates!('config/index_candidates.yml', threshold)

          Common.log_success('索引候補の自動抽出が完了しました')
          report_extraction_results(extractor, threshold)
        end

        # ビルドパイプラインから呼び出される索引処理
        # @param chapters [Array<String>] 対象章のリスト
        def process_index_for_build!(chapters)
          return unless index_enabled?

          Common.log_action('[Index] 索引語のスキャンを開始...')
          scanner = IndexTermScanner.new
          scanner.scan_all_chapters!(chapters)

          Common.log_action('[Index] 索引ページを生成...')
          builder = IndexPageBuilder.new
          builder.build!
        end

        # 索引機能が有効かどうか
        def index_enabled?
          config = Common::CONFIG || {}
          index_config = config['index'] || {}
          index_config['enabled'] == true
        end

        private

        # オプションを正規化
        def normalize_options(context_or_options)
          if context_or_options.is_a?(Hash)
            context_or_options[:options] || context_or_options
          elsif context_or_options.respond_to?(:options)
            context_or_options.options || {}
          else
            {}
          end
        end
        module_function :normalize_options

        # 対象章を解決
        def resolve_chapters(tokens)
          files = Common.normalize_tokens(tokens)

          if files.any?
            files
          else
            # 全章を対象
            Dir.glob('*.md').map { |f| File.basename(f, '.md') }.sort
          end
        end
        module_function :resolve_chapters

        # スキャン結果をレポート
        def report_scan_results(scanner)
          Common.log_info("\n=== スキャン結果 ===")
          Common.log_info("検出用語数: #{scanner.index_data.size} 件")
          Common.log_info("総マッチ数: #{scanner.matches.size} 件")

          # 読み推測が必要な用語を警告
          yomi_inferrer = YomiInferrer.new
          if yomi_inferrer.available?
            Common.log_info("\nMeCab による読み推測が利用可能です")
            Common.log_warn("読み間違いがないか .cache/index_matches.yml を確認してください")
          else
            Common.log_warn("\nMeCab が利用できないため、読み推測は行われていません")
          end
        end
        module_function :report_scan_results

        # 自動抽出結果をレポート
        def report_extraction_results(extractor, threshold)
          Common.log_info("\n=== 自動抽出結果 ===")
          Common.log_info("候補語数: #{extractor.term_scores.size} 件")

          above_threshold = extractor.term_scores.count { |_, score| score >= threshold }
          Common.log_info("閾値(#{threshold})以上: #{above_threshold} 件")

          # 上位10件を表示
          top_terms = extractor.term_scores.sort_by { |_, score| -score }.first(10)
          if top_terms.any?
            Common.log_info("\n上位10件:")
            top_terms.each do |term, score|
              Common.log_info("  #{term}: #{score.round(1)}")
            end
          end

          Common.log_info("\n候補は config/index_candidates.yml に出力されました")
          Common.log_info("確認・編集後、[用語|読み] 記法で原稿にマークアップしてください")
        end
        module_function :report_extraction_results
      end
    end
  end
end
