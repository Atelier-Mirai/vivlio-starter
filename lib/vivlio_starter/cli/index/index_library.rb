# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/index_library.rb
# ================================================================
# 責務:
#   索引ライブラリ（書籍間で持ち運べる作者の資産）の export/import。
#   - 用語集の定義[g]（term/yomi/definition）
#   - reject 一覧（索引に載せない語）
#
#   書籍固有情報（contexts / backlink_sources / link / source 等）は含めず、
#   別の書籍へそのまま引き継げる最小限のデータだけを扱う。
#
# 仕様: docs/specs/index-library-portability-spec.md
#   （yomi 個人辞書は Phase 2 で追加予定）
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'
require_relative 'unified_terms_manager'
require_relative 'review_queue_manager'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexLibrary
        SCHEMA_VERSION = 1
        DEFAULT_PATH = 'index_library.yml'

        # import の結果サマリ。
        ImportResult = Data.define(:glossary_added, :glossary_skipped, :reject_added, :reject_skipped)

        def initialize(terms_manager: UnifiedTermsManager.new, queue_manager: ReviewQueueManager.new)
          @terms_manager = terms_manager
          @queue_manager = queue_manager
        end

        # export/import の対象パスを解決する。
        # 先勝ち: コマンド引数 > library.export_to/import_from > library.path > 組み込み既定。
        # @param arg [String, nil] コマンド引数のパス
        # @param mode [Symbol] :export | :import
        def self.resolve_path(arg, mode)
          return File.expand_path(arg) if arg && !arg.to_s.empty?

          config = library_config
          override = mode == :export ? config[:export_to] : config[:import_from]
          File.expand_path((override || config[:path] || DEFAULT_PATH).to_s)
        end

        # book.yml の index_glossary.library をシンボルキーのハッシュで返す。
        def self.library_config
          shared = Common::CONFIG.respond_to?(:index_glossary) ? Common::CONFIG.index_glossary : nil
          shared_hash = shared.respond_to?(:to_h) ? shared.to_h : {}
          library = shared_hash[:library]
          library.respond_to?(:to_h) ? library.to_h : {}
        rescue StandardError
          {}
        end

        # --- Phase: export ---

        # 現プロジェクトの用語集[g]・reject をライブラリファイルへ書き出す。
        def export!(path)
          glossary = export_glossary
          reject = export_reject

          if glossary.empty? && reject.empty?
            Common.log_warn('書き出す用語集[g]・reject がありません（ライブラリは作成しませんでした）')
            return false
          end

          library = {
            'version' => SCHEMA_VERSION,
            'exported_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'glossary' => glossary,
            'reject' => reject
          }

          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless dir == '.'
          File.write(path, library.to_yaml, encoding: 'utf-8')
          Common.log_success("索引ライブラリを書き出しました: #{path}（用語集 #{glossary.size} 件 / reject #{reject.size} 件）")
          true
        end

        # 用語集[g]を term 昇順で term/yomi/definition のみ抽出する（固有情報は落とす）。
        def export_glossary
          @terms_manager.glossary_terms
                        .sort_by { it['term'].to_s }
                        .map { { 'term' => it['term'], 'yomi' => it['yomi'], 'definition' => it['definition'].to_s } }
        end

        # reject 一覧を term 昇順で term(+reason) のみ抽出する。
        def export_reject
          @queue_manager.load_rejected_terms_with_metadata
                        .sort_by { it['term'].to_s }
                        .map do |rejected|
            entry = { 'term' => rejected['term'] }
            entry['reason'] = rejected['reason'] if rejected['reason']
            entry
          end
        end

        # --- Phase: import ---

        # ライブラリファイルを現プロジェクトへ取り込む（追記マージ・既定は既存優先）。
        # @param prefer_import [Boolean] 既存語をライブラリ側で上書きするか
        def import!(path, prefer_import: false)
          data = load_library(path)
          return nil unless data

          unless data['version'] == SCHEMA_VERSION
            Common.log_warn("未知のライブラリ version: #{data['version'].inspect}（想定 #{SCHEMA_VERSION}）。可能な範囲で取り込みます")
          end

          glossary_added, glossary_skipped = import_glossary(data['glossary'] || [], prefer_import:)
          reject_added, reject_skipped = import_reject(data['reject'] || [])

          Common.log_success(
            "取り込み完了: 用語集 +#{glossary_added}（スキップ #{glossary_skipped}） / " \
            "reject +#{reject_added}（スキップ #{reject_skipped}）"
          )
          ImportResult.new(glossary_added:, glossary_skipped:, reject_added:, reject_skipped:)
        end

        private

        def load_library(path)
          unless File.exist?(path)
            Common.log_error("索引ライブラリが見つかりません: #{path}")
            return nil
          end

          YAML.load_file(path) || {}
        rescue StandardError => e
          Common.log_error("索引ライブラリの読み込みに失敗しました: #{e.message}")
          nil
        end

        # 用語集[g]を取り込む。既存語は既定でスキップ（prefer_import なら上書き）。
        def import_glossary(entries, prefer_import:)
          existing = @terms_manager.term_names
          skipped = 0

          to_merge = entries.filter_map do |entry|
            term = entry['term']
            next if term.nil? || term.to_s.empty?

            if existing.include?(term) && !prefer_import
              skipped += 1
              next
            end

            { 'term' => term, 'yomi' => entry['yomi'] || term, 'definition' => entry['definition'].to_s }
          end

          @terms_manager.merge_terms!(to_merge, flags: 'g', source: 'imported') if to_merge.any?
          [to_merge.size, skipped]
        end

        # reject を取り込む。既に reject 済み、または採用済み（[i]/[g]）の語はスキップ。
        def import_reject(entries)
          already_rejected = @queue_manager.load_rejected_terms
          adopted = @terms_manager.term_names
          skipped = 0

          to_add = entries.filter_map do |entry|
            term = entry['term']
            next if term.nil? || term.to_s.empty?

            if already_rejected.include?(term) || adopted.include?(term)
              skipped += 1
              next
            end

            reject_entry = { 'term' => term }
            reject_entry['reason'] = entry['reason'] if entry['reason']
            reject_entry
          end

          @queue_manager.save_rejected_terms(to_add) if to_add.any?
          [to_add.size, skipped]
        end
      end
    end
  end
end
