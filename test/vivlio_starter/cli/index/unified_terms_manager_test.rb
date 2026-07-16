# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/unified_terms_manager'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    class UnifiedTermsManagerTest < Minitest::Test
      def setup
        @original_dir = Dir.pwd
        @temp_dir = Dir.mktmpdir('unified_terms_test')
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
        @manager = UnifiedTermsManager.new
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
      end

      # --- Phase: 基本操作 ---

      def test_load_terms_returns_empty_when_no_file
        assert_empty @manager.load_terms
      end

      def test_merge_terms_creates_file
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'i')

        assert File.exist?('config/index_glossary_terms.yml')
        terms = @manager.load_terms
        assert_equal 1, terms.size
        assert_equal 'CSS', terms.first['term']
        assert_equal 'i', terms.first['flags']
      end

      def test_merge_terms_adds_new_term
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'i')
        @manager.merge_terms!([{ 'term' => 'HTML', 'yomi' => 'HTML' }], flags: 'g')

        assert_equal 2, @manager.load_terms.size
      end

      def test_merge_terms_updates_existing_flags
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'i')
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'g')

        terms = @manager.load_terms
        assert_equal 1, terms.size
        assert_equal 'ig', terms.first['flags']
      end

      def test_remove_term_deletes_entry
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'i')
        @manager.remove_term!('CSS')

        assert_empty @manager.load_terms
      end

      # --- Phase: flags 操作 ---

      def test_index_terms_filters_by_i_flag
        seed_terms([
          { 'term' => 'CSS', 'flags' => 'i' },
          { 'term' => 'HTML', 'flags' => 'g' },
          { 'term' => 'Ruby', 'flags' => 'ig' }
        ])

        index = @manager.index_terms
        assert_equal 2, index.size
        names = index.map { it['term'] }
        assert_includes names, 'CSS'
        assert_includes names, 'Ruby'
        refute_includes names, 'HTML'
      end

      def test_glossary_terms_filters_by_g_flag
        seed_terms([
          { 'term' => 'CSS', 'flags' => 'i' },
          { 'term' => 'HTML', 'flags' => 'g' },
          { 'term' => 'Ruby', 'flags' => 'ig' }
        ])

        glossary = @manager.glossary_terms
        assert_equal 2, glossary.size
        names = glossary.map { it['term'] }
        assert_includes names, 'HTML'
        assert_includes names, 'Ruby'
        refute_includes names, 'CSS'
      end

      def test_remove_flag_downgrades_ig_to_g
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'ig')
        @manager.remove_flag!('CSS', 'i')

        term = @manager.find_term('CSS')
        assert_equal 'g', term['flags']
      end

      def test_remove_flag_deletes_term_when_no_flags_remain
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'i')
        @manager.remove_flag!('CSS', 'i')

        assert_nil @manager.find_term('CSS')
      end

      def test_update_flags
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'i')
        @manager.update_flags!('CSS', 'ig')

        assert_equal 'ig', @manager.find_term('CSS')['flags']
      end

      # --- Phase: メタデータ ---

      def test_merge_preserves_metadata
        @manager.merge_terms!(
          [{ 'term' => 'CSS', 'yomi' => 'CSS', 'score' => 250.5 }],
          flags: 'i', source: 'auto_extracted'
        )

        term = @manager.find_term('CSS')
        assert_equal 'auto_extracted', term['source']
        assert term['approved_at']
        assert_equal 250.5, term['score']
        assert term['pattern']
      end

      def test_update_yomi
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'i')
        @manager.update_yomi!([{ 'term' => 'CSS', 'yomi' => 'しーえすえす' }])

        assert_equal 'しーえすえす', @manager.find_term('CSS')['yomi']
      end

      def test_update_definition
        @manager.merge_terms!([{ 'term' => 'CSS', 'yomi' => 'CSS' }], flags: 'g')
        @manager.update_definition!('CSS', 'スタイルシート言語')

        assert_equal 'スタイルシート言語', @manager.find_term('CSS')['definition']
      end

      # R3: 旧辞書に残置した backlink_sources は次の保存の機会に黙って消える
      def test_save_terms_discards_legacy_backlink_sources
        legacy_data = {
          'generated_at' => Time.now.to_s,
          'terms' => [
            { 'term' => 'CSS', 'yomi' => 'CSS', 'flags' => 'g', 'definition' => '',
              'backlink_sources' => [{ 'chapter' => '01-intro', 'occurrence' => 1 }] }
          ]
        }
        File.write('config/index_glossary_terms.yml', legacy_data.to_yaml)
        @manager.clear_cache!

        # 保存を伴う操作（読み更新）を実行
        @manager.update_yomi!([{ 'term' => 'CSS', 'yomi' => 'しーえすえす' }])

        saved = File.read('config/index_glossary_terms.yml')
        refute_includes saved, 'backlink_sources'
      end

      # --- Phase: scanned_chapters（R7） ---

      def test_scanned_chapters_returns_nil_for_legacy_dictionary
        seed_terms([{ 'term' => 'CSS', 'flags' => 'i' }])

        assert_nil @manager.scanned_chapters
      end

      def test_record_scanned_chapters_unions_and_filters_by_existing_files
        FileUtils.mkdir_p('contents')
        File.write('contents/10-intro.md', '# intro')
        File.write('contents/20-body.md', '# body')
        seed_terms([{ 'term' => 'CSS', 'flags' => 'i' }])

        # 初回: 10-intro のみ走査
        @manager.record_scanned_chapters!(['10-intro'])
        assert_equal ['10-intro'], @manager.scanned_chapters

        # 2 回目: 20-body と実在しない章（改名残骸）→ 和集合＋実在フィルタ
        @manager.record_scanned_chapters!(%w[20-body 99-deleted])
        assert_equal %w[10-intro 20-body], @manager.scanned_chapters
      end

      def test_save_terms_preserves_scanned_chapters
        FileUtils.mkdir_p('contents')
        File.write('contents/10-intro.md', '# intro')
        seed_terms([{ 'term' => 'CSS', 'flags' => 'i' }])
        @manager.record_scanned_chapters!(['10-intro'])

        # 用語の保存（merge）で走査記録が落ちないこと
        @manager.merge_terms!([{ 'term' => 'HTML', 'yomi' => 'HTML' }], flags: 'i')

        assert_equal ['10-intro'], @manager.scanned_chapters
      end

      # --- Phase: 後方互換 ---

      def test_legacy_entries_without_flags_default_to_g
        # Phase B 以前の index_glossary_terms.yml は flags フィールドがない
        legacy_data = {
          'generated_at' => Time.now.to_s,
          'terms' => [
            { 'term' => 'ウェブサイト', 'yomi' => 'ウェブサイト', 'definition' => '', 'source' => 'review' }
          ]
        }
        File.write('config/index_glossary_terms.yml', legacy_data.to_yaml)
        @manager.clear_cache!

        terms = @manager.load_terms
        assert_equal 'g', terms.first['flags']

        glossary = @manager.glossary_terms
        assert_equal 1, glossary.size
        assert_equal 'ウェブサイト', glossary.first['term']
      end

      # --- Phase: ソート ---

      def test_terms_sorted_by_yomi
        @manager.merge_terms!([{ 'term' => 'さ行', 'yomi' => 'さぎょう' }], flags: 'i')
        @manager.merge_terms!([{ 'term' => 'あ行', 'yomi' => 'あぎょう' }], flags: 'i')
        @manager.merge_terms!([{ 'term' => 'か行', 'yomi' => 'かぎょう' }], flags: 'i')

        terms = @manager.load_terms
        assert_equal 'あ行', terms[0]['term']
        assert_equal 'か行', terms[1]['term']
        assert_equal 'さ行', terms[2]['term']
      end

      private

      def seed_terms(entries)
        terms = entries.map do |e|
          {
            'term' => e['term'], 'yomi' => e['yomi'] || e['term'],
            'flags' => e['flags'] || 'i', 'definition' => e['definition'] || '',
            'pattern' => "/#{e['term']}/", 'source' => 'test',
            'approved_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
          }
        end
        File.write('config/index_glossary_terms.yml',
                   { 'generated_at' => Time.now.to_s, 'terms' => terms }.to_yaml)
        @manager.clear_cache!
      end
    end
  end
end
