# frozen_string_literal: true

# ================================================================
# Class: UnifiedTermsManager
# ----------------------------------------------------------------
# 責務:
#   config/index_glossary_terms.yml を統合用語辞書として管理する。
#
#   各用語は flags フィールドで索引/用語集の所属を制御:
#     i  = 索引のみ
#     g  = 用語集のみ
#     ig = 索引＋用語集
#
# 主要メソッド:
#   - load_terms: 全用語を読み込み
#   - index_terms: flags に i を含む用語のリスト
#   - glossary_terms: flags に g を含む用語のリスト
#   - merge_terms!: 用語をマージして保存
#   - remove_term!: 用語を削除
#   - update_flags!: flags を更新
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'

module VivlioStarter
  module CLI
    class UnifiedTermsManager
      UNIFIED_FILE = 'config/index_glossary_terms.yml'

      def initialize
        @cache = nil
      end

      # --- Phase: 読み込み ---

      # 全用語を読み込み
      # @return [Array<Hash>] 用語のリスト
      def load_terms
        return @cache if @cache

        unless File.exist?(UNIFIED_FILE)
          @cache = []
          return @cache
        end

        begin
          data = YAML.load_file(UNIFIED_FILE, symbolize_names: false)
          terms = data['terms'] || []
          # 後方互換: flags 未設定のエントリは用語集由来とみなし 'g' を付与
          terms.each { it['flags'] ||= 'g' }
          @cache = terms
        rescue StandardError => e
          Common.log_warn("#{UNIFIED_FILE} の読み込みに失敗: #{e.message}")
          @cache = []
        end

        @cache
      end

      # flags に i を含む用語（索引対象）
      def index_terms = load_terms.select { index_flag?(it['flags']) }

      # flags に g を含む用語（用語集対象）
      def glossary_terms = load_terms.select { glossary_flag?(it['flags']) }

      # 全用語名
      def term_names = load_terms.map { it['term'] }

      # 索引対象の用語名
      def index_term_names = index_terms.map { it['term'] }

      # 用語集対象の用語名
      def glossary_term_names = glossary_terms.map { it['term'] }

      # 用語を名前で検索
      # @param name [String] 用語名
      # @return [Hash, nil]
      def find_term(name) = load_terms.find { it['term'] == name }

      # --- Phase: 書き込み ---

      # 用語をマージして保存
      # 同名の用語が既存の場合は更新、なければ追加
      # @param new_terms [Array<Hash>] 追加する用語
      # @param flags [String] デフォルトの flags ('i', 'g', 'ig')
      # @param source [String] 登録元
      # @return [Array<String>] 新規追加された用語名（呼び出し元の登録要約表示・R8 に使う）
      def merge_terms!(new_terms, flags: 'i', source: 'auto_extracted')
        return [] if new_terms.nil? || new_terms.empty?

        existing = load_terms.dup
        added_names = []

        new_terms.each do |term|
          term_name = term['term'] || term[:term]
          next if term_name.nil? || term_name.empty?

          idx = existing.find_index { it['term'] == term_name }
          if idx
            # 既存用語を更新（flags をマージ、データを上書き）
            existing[idx] = merge_term_data(existing[idx], term, flags)
          else
            # 新規追加
            existing << build_term_entry(term, flags, source)
            added_names << term_name
          end
        end

        save_terms!(existing)
        Common.log_success("#{added_names.size} 件の用語を追加しました") if added_names.any?
        added_names
      end

      # 用語を削除
      # @param term_name [String] 削除する用語名
      def remove_term!(term_name)
        return if term_name.nil? || term_name.empty?

        existing = load_terms.dup
        original_size = existing.size
        existing.reject! { it['term'] == term_name }

        save_terms!(existing) if existing.size < original_size
      end

      # flags から特定のフラグを除去（用語自体は残す）
      # 例: flags 'ig' から 'i' を除去 → 'g' に変更
      # @param term_name [String] 用語名
      # @param remove_flag [String] 除去するフラグ ('i' or 'g')
      def remove_flag!(term_name, remove_flag)
        existing = load_terms.dup
        term = existing.find { it['term'] == term_name }
        return unless term

        current = term['flags'] || ''
        new_flags = case remove_flag
                    when 'i' then current.delete('i')
                    when 'g' then current.delete('g')
                    else current
                    end

        if new_flags.empty?
          # フラグがなくなったら用語自体を削除
          existing.reject! { it['term'] == term_name }
        else
          term['flags'] = new_flags
        end

        save_terms!(existing)
      end

      # flags を更新
      # @param term_name [String] 用語名
      # @param new_flags [String] 新しい flags
      def update_flags!(term_name, new_flags)
        existing = load_terms.dup
        term = existing.find { it['term'] == term_name }
        return unless term

        term['flags'] = new_flags
        save_terms!(existing)
      end

      # 読みを更新
      # @param yomi_changes [Array<Hash>] 読み変更のリスト
      def update_yomi!(yomi_changes)
        return if yomi_changes.nil? || yomi_changes.empty?

        existing = load_terms.dup
        updated_count = 0

        yomi_changes.each do |change|
          term = existing.find { it['term'] == change['term'] }
          next unless term
          next if term['yomi'] == change['yomi']

          term['yomi'] = change['yomi']
          updated_count += 1
        end

        return unless updated_count.positive?

        save_terms!(existing)
        Common.log_info("#{updated_count} 件の読みを更新しました")
      end

      # 説明文を更新
      # @param term_name [String] 用語名
      # @param definition [String] 説明文
      def update_definition!(term_name, definition)
        existing = load_terms.dup
        term = existing.find { it['term'] == term_name }
        return false unless term

        term['definition'] = definition
        term['updated_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        save_terms!(existing)
        true
      end

      # --- Phase: 章走査記録（R7: 章追加の検知） ---

      # index:auto が走査した章集合（辞書トップレベル）
      # キーが無い旧辞書・辞書なしでは nil（呼び出し側は判定をスキップする）
      # @return [Array<String>, nil]
      def scanned_chapters
        return nil unless File.exist?(UNIFIED_FILE)

        data = YAML.load_file(UNIFIED_FILE, symbolize_names: false)
        data['scanned_chapters']
      rescue StandardError
        nil
      end

      # 走査した章集合を和集合で記録する（R7）。
      # contents/ に実在する章だけ残し、改名・削除の残骸は落とす。
      # 辞書ファイルが無いときは何もしない（空辞書を作ると「辞書なし」案内を壊すため）
      # @param chapters [Array<String>] 今回走査した章（ベースネームまたはパス）
      def record_scanned_chapters!(chapters)
        return unless File.exist?(UNIFIED_FILE)

        data = YAML.load_file(UNIFIED_FILE, symbolize_names: false)
        existing_files = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { File.basename(it, '.md') }
        merged = ((data['scanned_chapters'] || []) | chapters.map { File.basename(it.to_s, '.md') }) & existing_files
        data['scanned_chapters'] = merged.sort
        File.write(UNIFIED_FILE, data.to_yaml, encoding: 'utf-8')
      end

      # キャッシュをクリア
      def clear_cache!
        @cache = nil
      end

      private

      # flags に 'i' を含むか
      def index_flag?(flags) = flags.to_s.include?('i')

      # flags に 'g' を含むか
      def glossary_flag?(flags) = flags.to_s.include?('g')

      # flags をマージ（例: 'g' + 'i' → 'ig'）
      def merge_flags(current, add)
        combined = (current.to_s.chars + add.to_s.chars).uniq.sort.join
        # 正規化: 'gi' → 'ig'
        combined.include?('i') && combined.include?('g') ? 'ig' : combined
      end

      # 用語データをマージ（既存 + 新規データ）
      def merge_term_data(existing, new_data, flags)
        merged = existing.dup
        # flags をマージ
        merged['flags'] = merge_flags(merged['flags'], flags)
        # nilでない場合のみ上書き
        merged['yomi'] = new_data['yomi'] || new_data[:yomi] || merged['yomi']
        merged['definition'] = new_data['definition'] if new_data['definition']
        merged['score'] = new_data['score'] || new_data[:score] if new_data['score'] || new_data[:score]
        merged['contexts'] = new_data['contexts'] if new_data['contexts']
        merged['updated_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        merged
      end

      # 用語エントリを構築
      def build_term_entry(term, flags, source)
        entry = {
          'term' => term['term'] || term[:term],
          'yomi' => term['yomi'] || term[:yomi] || term['term'] || term[:term],
          'flags' => flags,
          'definition' => term['definition'] || '',
          'source' => source,
          'approved_at' => term['approved_at'] || Time.now.strftime('%Y-%m-%d %H:%M:%S')
        }
        # オプショナルフィールド
        entry['pattern'] = term['pattern'] || build_pattern(entry['term'])
        entry['auto_approved'] = term['auto_approved'] if term.key?('auto_approved')
        entry['score'] = term['score'] if term['score']
        entry['contexts'] = term['contexts'] if term['contexts']&.any?
        entry
      end

      # パターンを生成
      def build_pattern(term_name)
        escaped = Regexp.escape(term_name)
        term_name.match?(/\A[a-zA-Z0-9_]+\z/) ? "/\\b#{escaped}\\b/" : "/#{escaped}/"
      end

      # 用語を保存（読み順でソート）
      def save_terms!(terms)
        FileUtils.mkdir_p(File.dirname(UNIFIED_FILE))

        # R3: 廃止済みの backlink_sources（出現情報は中間 YAML へ移行済み）が
        # 旧辞書に残置していても、保存の機会に黙って捨てる
        sorted = terms.map { it.except('backlink_sources') }
                      .sort_by { it['yomi'] || it['term'] || '' }

        data = {
          'generated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          'terms' => sorted
        }
        # 既存の走査記録（R7）は用語の保存で落とさない
        scanned = scanned_chapters
        data['scanned_chapters'] = scanned if scanned
        File.write(UNIFIED_FILE, data.to_yaml, encoding: 'utf-8')

        @cache = sorted
      end
    end
  end
end
