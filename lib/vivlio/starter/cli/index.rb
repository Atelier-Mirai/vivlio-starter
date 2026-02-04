# frozen_string_literal: true

# ================================================================
# Module: 索引・用語集機能オーケストレーター
# ----------------------------------------------------------------
# 【役割】
# - 索引・用語集機能のエントリポイント
# - IndexMatchScanner, IndexPageBuilder, GlossaryPageBuilder を統括
# - CLI コマンド（vs index:auto, vs index:apply, vs index:build）を提供
#
# 【処理の流れ】
# 1. vs index:auto: 原稿をスキャンして候補を抽出 → _index_glossary_review.md 生成
# 2. vs index:apply: レビュー結果を適用
# 3. vs build: 索引・用語集ページを生成
#
# 【依存モジュール】
# - IndexMatchScanner: 索引語スキャン・ID付与
# - IndexPageBuilder: 索引ページHTML生成
# - GlossaryPageBuilder: 用語集ページHTML生成
# - YomiInferrer: MeCab による読み推測
# ================================================================

require_relative 'common'
require_relative 'index/index_match_scanner'
require_relative 'index/index_page_builder'
require_relative 'index/glossary_page_builder'
require_relative 'index/yomi_inferrer'
require_relative 'index/index_candidate_extractor'
require_relative 'index/scoring_engine'
require_relative 'index/hierarchical_index'
require_relative 'index/glossary_terms_manager'
require_relative 'token_resolver'

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

        INDEX_MATCH_DESC = {
          short: '索引候補を自動抽出し、YAML を生成します',
          long: <<~DESC
            原稿をスキャンして索引候補を自動抽出します。

            処理内容:
            - [用語|読み] または [用語] 記法を検出
            - [用語] 形式の場合、MeCab で読みを自動推測
            - 検出結果を config/index_candidates.yml に出力

            例:
              vs index:match
              vs index:match --threshold 80
          DESC
        }.freeze

        INDEX_BUILD_DESC = {
          short: '索引ページを生成します',
          long: <<~DESC
            _index_matches.yml から索引ページを生成します。

            処理内容:
            - 索引データを読み込み
            - 用語を五十音順でソート
            - _indexpage.html を生成

            例:
              vs index:build
              vs index:build --preview
          DESC
        }.freeze

        INDEX_CANDIDATE_DESC = {
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
              vs index:candidate
              vs index:candidate --threshold 60
          DESC
        }.freeze

        # 索引マッチングを実行
        # @param context_or_options [Hash] オプション
        # @param tokens [Array<String>] 対象章（省略時は全章）
        def execute_index_match(context_or_options, tokens = [])
          opts = normalize_options(context_or_options)
          ENV['VERBOSE'] = '1' if opts[:verbose]

          chapters = resolve_chapters(tokens)

          Common.log_action('索引語のスキャンを開始します...')

          scanner = IndexMatchScanner.new
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
          output_path = builder.build!

          if output_path
            Common.log_success("索引ページの生成が完了しました: #{output_path}")
            Common.log_info('完成した _indexpage.html を確認してください')
            Common.echo_always('📄 _indexpage.html を生成しました。')
          else
            Common.log_warn('索引ページを生成できませんでした')
          end
        end

        # 索引候補を自動抽出（Phase 2）
        # @param context_or_options [Hash] オプション
        # @param tokens [Array<String>] 対象章（省略時は全章）
        def execute_index_candidate(context_or_options, tokens = [])
          opts = normalize_options(context_or_options)
          ENV['VERBOSE'] = '1' if opts[:verbose]

          threshold = opts[:threshold] || 150
          # catalog.yml に基づいて対象章を決定（引数がある場合はそちらを優先）
          chapters = resolve_chapters(tokens)

          extractor = IndexCandidateExtractor.new
          extractor.extract_from_chapters!(chapters)
          extractor.export_candidates!('config/index_candidates.yml', threshold)

          report_extraction_results(extractor, threshold)
        end

        # ビルドパイプラインから呼び出される索引・用語集処理
        # 仕様書 index_glossary_spec.md に準拠
        # @param chapters [Array<String>] 対象章のリスト
        def process_index_for_build!(chapters)
          return unless index_enabled?

          require_relative 'index/unified_index_manager'
          manager = UnifiedIndexManager.new
          manager.build_index!(chapters)
          manager.build_glossary!
        end

        # 索引・用語集機能が有効かどうか（シンボルキー前提）
        def index_enabled?
          Common::CONFIG.index_glossary&.enabled == true
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
          resolver = TokenResolver::Resolver.new
          entries = resolver.resolve(tokens)

          if entries.any?
            # トークン指定あり: Entry から basename を取得
            basenames = entries.select(&:valid?).map(&:basename)
            Common.log_info("引数から対象章を特定しました: #{basenames.join(', ')}")
            basenames
          else
            # トークン指定なし: catalog.yml から全章を取得
            begin
              require_relative 'build/catalog_loader'
              chapters = Build::CatalogLoader.load_existing_basenames
              Common.log_info("catalog.yml から対象章を特定しました: #{chapters.size} 章")
              chapters
            rescue StandardError => e
              Common.log_warn("catalog.yml の読み込みに失敗したため、全 Markdown ファイルを対象にします: #{e.message}")
              chapters = Dir.glob('*.md').map { |f| File.basename(f, '.md') }.sort
              Common.log_info("カレントディレクトリの全ファイルを対象にします: #{chapters.size} 章")
              chapters
            end
          end
        end
        module_function :resolve_chapters

        # スキャン結果をレポート
        def report_scan_results(scanner)
          Common.log_info("\n=== スキャン結果 ===")
          Common.log_info("検出用語数: #{scanner.index_data.size} 件")
          Common.log_info("総マッチ数: #{scanner.matches.size} 件")

          # 読み推測が必要な用語を警告
          if Vivlio::Starter::CLI::IndexCommands::YomiInferrer.new.available?
            Common.log_info("\nMeCab による読み推測が利用可能です")
          else
            Common.log_warn("\nMeCab が利用できないため、読み推測は行われていません")
          end
        end
        module_function :report_scan_results

        # 自動抽出結果をレポート
        def report_extraction_results(extractor, threshold)
          Common.log_info("抽出完了: #{extractor.all_candidates.size} 件の候補が見つかりました")
          Common.log_info("出現回数 #{threshold} 回以上の語句を config/index_candidates.yml に出力しました")
          Common.log_warn('読み間違いがないか config/index_candidates.yml を確認してください')
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
