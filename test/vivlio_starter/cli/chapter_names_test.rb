# frozen_string_literal: true

# ================================================================
# Test: chapter_names_test.rb
# ================================================================
# テスト対象:
#   ChapterNames（lib/vivlio_starter/cli/chapter_names.rb）
#
# 検証内容:
#   - 番号が同じ別の章・名前が同じ別の章を、理由の文にして返す（大文字小文字は区別しない）
#   - 名前を変えるときは、変えない部分を見ない（既にある重なりを解く rename を止めない）
#   - 重ならない番号（同じ区分の空き）・名前（「-2」を足す）を勧める
#   - contents/ の原稿と catalog.yml の章を数え、システムページは除く
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/chapter_names'

module VivlioStarter
  module CLI
    class ChapterNamesTest < Minitest::Test
      TAKEN = %w[00-preface 11-intro 97-sample].freeze

      def test_should_report_a_number_used_by_another_chapter
        assert_equal ['97 番は 97-sample が使っています'], ChapterNames.conflicts('97-foo', TAKEN)
      end

      def test_should_report_a_name_used_by_another_chapter
        assert_equal ['スラッグ sample は 97-sample が使っています'], ChapterNames.conflicts('01-sample', TAKEN)
        assert_equal ['スラッグ sample は 97-sample が使っています'], ChapterNames.conflicts('01-Sample', TAKEN),
                     '大文字と小文字の違いだけの名前も同じとみなす'
      end

      def test_should_report_both_reasons_at_once
        assert_equal ['11 番は 11-intro が使っています', 'スラッグ sample は 97-sample が使っています'],
                     ChapterNames.conflicts('11-sample', TAKEN)
      end

      def test_should_pass_a_name_used_by_nobody
        assert_empty ChapterNames.conflicts('12-basics', TAKEN)
        assert_empty ChapterNames.conflicts('12', TAKEN), '番号だけの章は名前を比べない'
      end

      # 番号 97 が重なった本で、名前だけを変えて重なりを解く rename は止めない
      def test_should_ignore_the_part_left_unchanged_by_a_rename
        taken = %w[97-sample 97-sample-ocr 01-sample]

        assert_empty ChapterNames.conflicts('97-sample-2', taken, except: '97-sample')
        assert_empty ChapterNames.conflicts('98-sample', taken, except: '97-sample'),
                     '番号だけを変えるときは、名前の重なりを見ない'
        assert_equal ['98 番は 98-x が使っています'], ChapterNames.conflicts('98-sample-ocr', [*taken, '98-x'], except: '97-sample-ocr')
      end

      def test_should_suggest_a_free_number_and_a_free_name
        assert_equal '90-foo', ChapterNames.suggestion('97-foo', TAKEN), '同じ区分（付録）の空き番号'
        assert_equal '01-sample-2', ChapterNames.suggestion('01-sample', TAKEN)
        assert_equal '01-sample-3', ChapterNames.suggestion('01-sample', [*TAKEN, '02-sample-2'])
        assert_equal '97-sample-2', ChapterNames.suggestion('97-sample', %w[97-sample 01-sample])
      end

      # 章の名前は vs create の作る形に限る
      def test_should_accept_only_the_chapter_name_rule
        assert ChapterNames.valid?('11-intro')
        assert ChapterNames.valid?('15'), '番号だけの章'
        assert ChapterNames.valid?('97-sample-2')
        %w[11-Intro 11_intro 11-my_intro 11-intro.v2 999-x 1-intro 01-245 11-intro- 11-サンプル].each do |name|
          refute ChapterNames.valid?(name), name
        end
        refute ChapterNames.valid?('11-intro copy')
      end

      # 著者が打った名前は、番号の 0 埋め・大文字・`_` だけを整える。点・空白・日本語は整えない
      def test_should_normalize_only_padding_capitals_and_underscores
        assert_equal '05-intro-guide', ChapterNames.normalize('5-Intro_Guide')
        assert_equal '15', ChapterNames.normalize('15')
        assert_nil ChapterNames.normalize('01-foo.bar')
        assert_nil ChapterNames.normalize('01-foo bar')
        assert_nil ChapterNames.normalize('01-サンプル')
        assert_nil ChapterNames.normalize('245'), '3 桁の番号'
      end

      # 勧める名前は使えない字をハイフンにする。日本語しか無ければ chapter
      def test_should_repair_names_in_suggestions
        assert_equal '90-sample-v2', ChapterNames.suggestion('97-sample.v2', TAKEN)
        assert_equal '90-sample-2', ChapterNames.suggestion('97-sample のコピー', TAKEN)
        assert_equal '90-chapter', ChapterNames.suggestion('97-サンプル', TAKEN)
      end

      # 空白・括弧などはエスケープし、日本語はそのまま残す（引用符を求めない）
      def test_should_escape_only_shell_meta_characters
        assert_equal 'contents/97-sample\ のコピー.md', ChapterNames.shell_word('contents/97-sample のコピー.md')
        assert_equal 'IPSJ-MGN621105\ \(1\).pdf', ChapterNames.shell_word('IPSJ-MGN621105 (1).pdf')
      end

      def test_should_count_contents_and_catalog_but_not_system_pages
        Dir.mktmpdir('vs-chapter-names') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p(%w[config contents])
            File.write('config/catalog.yml', "PREFACE:\nCHAPTERS:\n  - 11-intro\n  - 12-planned\nAPPENDICES:\nPOSTFACE:\n")
            %w[11-intro 13-draft _toc].each { File.write("contents/#{it}.md", "# #{it}\n") }

            assert_equal %w[11-intro 12-planned 13-draft], ChapterNames.existing_basenames
          end
        end
      end
    end
  end
end
