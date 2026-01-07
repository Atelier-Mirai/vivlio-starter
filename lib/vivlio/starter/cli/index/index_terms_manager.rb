# frozen_string_literal: true

# ================================================================
# Class: IndexTermsManager
# ----------------------------------------------------------------
# 責務:
#   config/index_terms.yml の読み込み・書き込み・マージを管理
#
# 主要メソッド:
#   - load_existing_terms: 既存の用語辞書を読み込み
#   - merge_terms!: 新しい用語を辞書にマージ
#   - save_terms!: 用語辞書を保存
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      class IndexTermsManager
        CONFIG_FILE = 'config/index_terms.yml'

        def initialize
          @terms = nil
        end

        # 既存の用語辞書を読み込み
        # @return [Array<Hash>] 用語のリスト
        def load_existing_terms
          return @terms if @terms

          unless File.exist?(CONFIG_FILE)
            @terms = []
            return @terms
          end

          begin
            data = YAML.load_file(CONFIG_FILE)
            @terms = data['terms'] || []
          rescue StandardError => e
            Common.log_warn("#{CONFIG_FILE} の読み込みに失敗しました: #{e.message}")
            @terms = []
          end

          @terms
        end

        # 新しい用語を辞書にマージ
        # @param new_terms [Array<Hash>] 追加する用語のリスト
        # @param source [String] ソース種別 ('manual_markup' または 'auto_extracted')
        def merge_terms!(new_terms, source: 'auto_extracted')
          return if new_terms.nil? || new_terms.empty?

          existing = load_existing_terms
          added_count = 0

          new_terms.each do |term|
            term_name = term['term'] || term[:term]
            next if term_name.nil? || term_name.empty?

            # 重複チェック
            unless existing.any? { |t| t['term'] == term_name }
              yomi = term['yomi'] || term[:yomi] || term_name
              score = term['score'] || term[:score]
              entry = {
                'term' => term_name,
                'yomi' => yomi,
                'pattern' => build_pattern(term_name),
                'approved_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
                'auto_approved' => source == 'auto_extracted',
                'source' => source
              }
              entry['score'] = score if score
              existing << entry
              added_count += 1
            end
          end

          if added_count.positive?
            save_terms!(existing)
            Common.log_success("#{added_count} 件の用語を index_terms.yml に追加しました")
          end
        end

        # 用語の読みを更新
        # @param yomi_changes [Array<Hash>] 読み変更のリスト ({ 'term' => '...', 'yomi' => '...' })
        def update_yomi!(yomi_changes)
          return if yomi_changes.nil? || yomi_changes.empty?

          existing = load_existing_terms
          updated_count = 0

          yomi_changes.each do |change|
            term_name = change['term']
            new_yomi = change['yomi']
            next if term_name.nil? || new_yomi.nil?

            term_entry = existing.find { |t| t['term'] == term_name }
            next unless term_entry
            next if term_entry['yomi'] == new_yomi

            term_entry['yomi'] = new_yomi
            updated_count += 1
          end

          if updated_count.positive?
            save_terms!(existing)
            Common.log_info("#{updated_count} 件の読みを更新しました")
          end
        end

        # 用語辞書を保存（読み順でソート）
        # @param terms [Array<Hash>] 用語のリスト
        def save_terms!(terms)
          FileUtils.mkdir_p(File.dirname(CONFIG_FILE))

          # 読み順でソート
          sorted_terms = terms.sort_by { |t| t['yomi'] || t['term'] || '' }

          data = { 'terms' => sorted_terms }
          File.write(CONFIG_FILE, data.to_yaml, encoding: 'utf-8')

          # キャッシュを更新
          @terms = sorted_terms
        end

        # 用語名のリストを取得
        # @return [Array<String>] 用語名のリスト
        def term_names
          load_existing_terms.map { |t| t['term'] }
        end

        # キャッシュをクリア
        def clear_cache!
          @terms = nil
        end

        private

        # パターンを生成
        # @param term_name [String] 用語名
        # @return [String] 正規表現パターン
        def build_pattern(term_name)
          escaped = Regexp.escape(term_name)
          # 英単語の場合は単語境界を付与
          if term_name.match?(/\A[a-zA-Z0-9_]+\z/)
            "/\\b#{escaped}\\b/"
          else
            "/#{escaped}/"
          end
        end
      end
    end
  end
end
