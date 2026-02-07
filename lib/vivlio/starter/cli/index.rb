# frozen_string_literal: true

# ================================================================
# Module: 索引・用語集機能オーケストレーター
# ----------------------------------------------------------------
# 【役割】
# - 索引・用語集機能のエントリポイント
# - IndexMatchScanner, UnifiedPageBuilder, UnifiedTermsManager を統括
# - CLI コマンド（vs index:auto, vs index:apply）の共通ヘルパーを提供
#
# 【処理の流れ】
# 1. vs index:auto: 原稿をスキャンして候補を抽出 → _index_glossary_review.md 生成
# 2. vs index:apply: レビュー結果を適用
# 3. vs build: 索引・用語集ページを生成（パイプライン経由）
#
# 【依存モジュール】
# - IndexMatchScanner: 索引語スキャン・ID付与
# - UnifiedPageBuilder: 索引・用語集ページHTML生成
# - UnifiedTermsManager: 統合用語辞書管理
# - YomiInferrer: MeCab による読み推測
# ================================================================

require_relative 'common'
require_relative 'index/index_match_scanner'
require_relative 'index/unified_page_builder'
require_relative 'index/yomi_inferrer'
require_relative 'index/index_candidate_extractor'
require_relative 'index/scoring_engine'
require_relative 'index/hierarchical_index'
require_relative 'index/unified_terms_manager'
require_relative 'token_resolver'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: IndexCommands
      # ----------------------------------------------------------------
      # 索引機能のヘルパーメソッドを提供
      # CLI コマンド本体は samovar/index_command.rb で定義
      # ================================================================
      module IndexCommands
        module_function

        # ビルドパイプラインから呼び出される索引・用語集処理
        # @param chapters [Array<String>] 対象章のリスト
        def process_index_for_build!(chapters)
          return unless index_enabled?

          require_relative 'index/unified_index_manager'
          manager = UnifiedIndexManager.new
          manager.build_index!(chapters)
        end

        # 索引・用語集機能が有効かどうか（シンボルキー前提）
        def index_enabled?
          Common::CONFIG.index_glossary&.enabled == true
        end

        # 対象章を解決
        # @param tokens [Array<String>] 対象章トークン（省略時は全章）
        def resolve_chapters(tokens)
          resolver = TokenResolver::Resolver.new
          entries = resolver.resolve(tokens)

          if entries.any?
            basenames = entries.select(&:valid?).map(&:basename)
            Common.log_info("引数から対象章を特定しました: #{basenames.join(', ')}")
            basenames
          else
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
      end
    end
  end
end
