# frozen_string_literal: true

# ================================================================
# Class: ReviewQueueManager
# ----------------------------------------------------------------
# 責務:
#   config/index_review_queue.yml と config/index_rejected.yml の管理
#
# 主要メソッド:
#   - save_queue: レビューキューを保存
#   - load_queue: レビューキューを読み込み
#   - clear_terms: 指定した用語をキューから削除
#   - save_rejected_terms: リジェクト済み候補を保存
#   - load_rejected_terms: リジェクト済み用語名のリストを取得
#   - unreject_term!: リジェクト解除
#   - reset_rejected!: リジェクト履歴をクリア
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      class ReviewQueueManager
        QUEUE_FILE = 'config/index_review_queue.yml'
        REJECTED_FILE = 'config/index_glossary_rejected.yml'

        def initialize
          @queue_cache = nil
          @rejected_cache = nil
        end

        # レビューキューを保存
        # @param candidates [Array<Hash>] 候補のリスト
        def save_queue(candidates)
          FileUtils.mkdir_p(File.dirname(QUEUE_FILE))

          data = {
            'generated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'pending_count' => candidates.size,
            'candidates' => candidates
          }
          File.write(QUEUE_FILE, data.to_yaml, encoding: 'utf-8')

          @queue_cache = candidates
        end

        # レビューキューを読み込み
        # @return [Array<Hash>] 候補のリスト
        def load_queue
          return @queue_cache if @queue_cache

          unless File.exist?(QUEUE_FILE)
            @queue_cache = []
            return @queue_cache
          end

          begin
            data = YAML.load_file(QUEUE_FILE)
            @queue_cache = data['candidates'] || []
          rescue StandardError => e
            Common.log_warn("#{QUEUE_FILE} の読み込みに失敗しました: #{e.message}")
            @queue_cache = []
          end

          @queue_cache
        end

        # 指定した用語をキューから削除
        # @param term_names [Array<String>] 削除する用語名のリスト
        def clear_terms(term_names)
          queue = load_queue
          remaining = queue.reject { |c| term_names.include?(c['term']) }
          save_queue(remaining)
        end

        # リジェクト済み候補を保存
        # @param rejected_terms [Array<Hash>] リジェクトする用語のリスト
        def save_rejected_terms(rejected_terms)
          return if rejected_terms.nil? || rejected_terms.empty?

          FileUtils.mkdir_p(File.dirname(REJECTED_FILE))

          # 既存のリジェクト済みリストを読み込み
          existing = load_rejected_terms_with_metadata

          # 新規リジェクトを追加（スコア・文脈も保存）
          rejected_terms.each do |term|
            term_name = term['term'] || term[:term]
            next if term_name.nil? || term_name.empty?

            unless existing.any? { |t| t['term'] == term_name }
              entry = {
                'term' => term_name,
                'yomi' => term['yomi'] || term[:yomi] || term_name,
                'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
              }
              # スコアがあれば保存
              score = term['score'] || term[:score]
              entry['score'] = score if score
              # 文脈があれば保存
              contexts = term['contexts'] || term[:contexts]
              entry['contexts'] = contexts if contexts&.any?

              existing << entry
            end
          end

          # 保存
          data = {
            'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'rejected_terms' => existing
          }
          File.write(REJECTED_FILE, data.to_yaml, encoding: 'utf-8')

          @rejected_cache = nil # キャッシュをクリア
        end

        # リジェクト済み用語名のリストを取得
        # @return [Array<String>] 用語名のリスト
        def load_rejected_terms
          load_rejected_terms_with_metadata.map { |t| t['term'] }
        end

        # リジェクト済み候補（メタデータ付き）を取得
        # @return [Array<Hash>] リジェクト済み候補のリスト
        def load_rejected_terms_with_metadata
          return @rejected_cache if @rejected_cache

          unless File.exist?(REJECTED_FILE)
            @rejected_cache = []
            return @rejected_cache
          end

          begin
            data = YAML.load_file(REJECTED_FILE)
            @rejected_cache = data['rejected_terms'] || []
          rescue StandardError => e
            Common.log_warn("#{REJECTED_FILE} の読み込みに失敗しました: #{e.message}")
            @rejected_cache = []
          end

          @rejected_cache
        end

        # リジェクト済み候補の一覧表示
        def list_rejected_terms
          rejected = load_rejected_terms_with_metadata

          if rejected.empty?
            Common.log_info('リジェクト済み候補はありません')
            return
          end

          puts "\nリジェクト済み候補:"
          rejected.each_with_index do |term, idx|
            puts "#{idx + 1}. #{term['term']} (#{term['yomi']})"
          end
        end

        # リジェクト解除
        # @param term_or_number [String] 用語名または番号
        # @return [Boolean] 成功したか
        def unreject_term!(term_or_number)
          rejected = load_rejected_terms_with_metadata

          if rejected.empty?
            Common.log_warn('リジェクト済み候補がありません')
            return false
          end

          # 番号または用語名で検索
          target = if term_or_number.match?(/^\d+$/)
                     idx = term_or_number.to_i - 1
                     (idx >= 0 && idx < rejected.size) ? rejected[idx] : nil
                   else
                     rejected.find { |t| t['term'] == term_or_number }
                   end

          unless target
            Common.log_error("「#{term_or_number}」が見つかりません")
            return false
          end

          # リジェクトリストから削除
          rejected.delete(target)
          save_rejected_terms_data(rejected)

          Common.log_success("「#{target['term']}」をリジェクトから解除しました")
          Common.log_info('次回の vs index:auto で再び候補として表示されます')
          true
        end

        # リジェクト履歴を全てクリア
        def reset_rejected!
          unless File.exist?(REJECTED_FILE)
            Common.log_info('リジェクト済み候補はありません')
            return
          end

          FileUtils.rm_f(REJECTED_FILE)
          @rejected_cache = nil
          Common.log_success('リジェクト履歴をクリアしました')
        end

        # 用語名でリジェクト解除（内部用）
        # @param term_name [String] 用語名
        # @return [Boolean] 成功したか
        def unreject_term_by_name!(term_name)
          rejected = load_rejected_terms_with_metadata
          target = rejected.find { |t| t['term'] == term_name }
          return false unless target

          rejected.delete(target)
          save_rejected_terms_data(rejected)
          true
        end

        # リジェクト済み候補の件数
        # @return [Integer] 件数
        def rejected_count
          load_rejected_terms.size
        end

        # キャッシュをクリア
        def clear_cache!
          @queue_cache = nil
          @rejected_cache = nil
        end

        private

        # リジェクト済みデータを直接保存
        # @param rejected [Array<Hash>] リジェクト済み候補のリスト
        def save_rejected_terms_data(rejected)
          FileUtils.mkdir_p(File.dirname(REJECTED_FILE))

          if rejected.empty?
            FileUtils.rm_f(REJECTED_FILE)
          else
            data = {
              'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
              'rejected_terms' => rejected
            }
            File.write(REJECTED_FILE, data.to_yaml, encoding: 'utf-8')
          end

          @rejected_cache = nil
        end
      end
    end
  end
end
