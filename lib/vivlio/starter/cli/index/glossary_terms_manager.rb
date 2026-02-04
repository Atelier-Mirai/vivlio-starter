# frozen_string_literal: true

# ================================================================
# Class: GlossaryTermsManager
# ----------------------------------------------------------------
# 責務:
#   config/glossary_terms.yml の読み書きを担当
#   用語集データ（用語、読み、説明文、backlink_sources）を管理
#
# 主要メソッド:
#   - load_existing_terms: 既存用語を読み込み
#   - merge_terms!: 用語をマージして保存
#   - term_names: 登録済み用語名のリスト
#   - update_definition!: 説明文を更新
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      # 用語集データを管理するクラス
      class GlossaryTermsManager
        GLOSSARY_FILE = 'config/glossary_terms.yml'

        def initialize
          @cache = nil
        end

        # 既存用語を読み込み
        # @return [Array<Hash>] 用語のリスト
        def load_existing_terms
          return @cache if @cache

          unless File.exist?(GLOSSARY_FILE)
            @cache = []
            return @cache
          end

          begin
            data = YAML.load_file(GLOSSARY_FILE, symbolize_names: false)
            @cache = data['terms'] || []
          rescue StandardError => e
            Common.log_warn("#{GLOSSARY_FILE} の読み込みに失敗しました: #{e.message}")
            @cache = []
          end

          @cache
        end

        # 用語をマージして保存
        # 同名の用語が既存の場合は更新、なければ追加
        # @param new_terms [Array<Hash>] 追加する用語
        # @param source [String] 登録元（'manual_markup' / 'review'）
        def merge_terms!(new_terms, source: 'review')
          return if new_terms.nil? || new_terms.empty?

          existing = load_existing_terms.dup
          existing_names = existing.map { it['term'] }

          new_terms.each do |term|
            term_name = term['term']
            next if term_name.nil? || term_name.empty?

            if existing_names.include?(term_name)
              # 既存用語を更新（説明文があれば上書き）
              idx = existing.find_index { it['term'] == term_name }
              if idx
                existing[idx] = merge_term_data(existing[idx], term)
              end
            else
              # 新規追加
              existing << build_term_entry(term, source)
              existing_names << term_name
            end
          end

          save_terms!(existing)
        end

        # 登録済み用語名のリスト
        # @return [Array<String>]
        def term_names
          load_existing_terms.map { it['term'] }
        end

        # 説明文を更新
        # @param term_name [String] 用語名
        # @param definition [String] 説明文
        def update_definition!(term_name, definition)
          existing = load_existing_terms.dup
          term = existing.find { it['term'] == term_name }
          return false unless term

          term['definition'] = definition
          term['updated_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
          save_terms!(existing)
          true
        end

        # backlink_sources を更新
        # @param term_name [String] 用語名
        # @param sources [Array<Hash>] 出現箇所リスト
        def update_backlink_sources!(term_name, sources)
          existing = load_existing_terms.dup
          term = existing.find { it['term'] == term_name }
          return false unless term

          term['backlink_sources'] = sources
          save_terms!(existing)
          true
        end

        # 用語を削除
        # @param term_name [String] 用語名
        def remove_term!(term_name)
          existing = load_existing_terms.dup
          existing.reject! { it['term'] == term_name }
          save_terms!(existing)
        end

        # キャッシュをクリア
        def clear_cache!
          @cache = nil
        end

        private

        # 用語データをマージ
        # 既存データに新規データを上書き（nilでない場合のみ）
        def merge_term_data(existing, new_data)
          merged = existing.dup
          merged['yomi'] = new_data['yomi'] if new_data['yomi']
          merged['definition'] = new_data['definition'] if new_data['definition']
          merged['backlink_sources'] = new_data['backlink_sources'] if new_data['backlink_sources']
          merged['updated_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
          merged
        end

        # 用語エントリを構築
        def build_term_entry(term, source)
          entry = {
            'term' => term['term'],
            'yomi' => term['yomi'] || term['term'],
            'definition' => term['definition'] || '',
            'source' => source,
            'approved_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
          }
          entry['backlink_sources'] = term['backlink_sources'] if term['backlink_sources']
          entry['contexts'] = term['contexts'] if term['contexts']
          entry
        end

        # 用語を保存
        def save_terms!(terms)
          FileUtils.mkdir_p(File.dirname(GLOSSARY_FILE))

          data = {
            'generated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'terms' => terms
          }
          File.write(GLOSSARY_FILE, data.to_yaml, encoding: 'utf-8')

          @cache = terms
        end
      end
    end
  end
end
