# frozen_string_literal: true

require_relative '../../test_helper'
require 'vivlio_starter/cli/import'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    # 章をまたぐ処理（ラベルの一意化・catalog の読み取り）
    class ImportCommandsTest < Minitest::Test
      def setup
        @report = Import::ReReport.new
      end

      def chapter(basename, markdown, labels)
        ImportCommands::Chapter.new(basename:, markdown:, labels:, lines: markdown.lines.size)
      end

      # ================================================================
      # ラベルの一意化（re-direct-import-spec.md §3.6）
      # ================================================================
      # Re:VIEW は章内で一意ならよいが、Vivlio は本全体で一意でなければならない
      def test_should_rename_labels_duplicated_across_chapters
        chapters = [
          chapter('01-intro', "** 表 @tbl1 **\n\n@tbl1 を参照。\n", ['tbl1']),
          chapter('02-basic', "** 表 @tbl1 **\n\n@tbl1 を参照。\n", ['tbl1'])
        ]

        result = ImportCommands.unify_labels(chapters, @report)

        assert_includes result[0].markdown, '@01-intro-tbl1'
        assert_includes result[1].markdown, '@02-basic-tbl1'
        assert_equal 2, @report.counted(:relabel)
      end

      # 重複しなかった ID は、著者が覚えている名前のまま残す
      def test_should_keep_unique_labels_untouched
        chapters = [
          chapter('01-intro', "** 図 @fig-a **\n", ['fig-a']),
          chapter('02-basic', "** 図 @fig-b **\n", ['fig-b'])
        ]

        result = ImportCommands.unify_labels(chapters, @report)

        assert_equal '@fig-a', result[0].markdown[/@fig-a/]
        assert_equal 0, @report.counted(:relabel)
      end

      # 似た名前のラベルを巻き込まない（@fig1 の置換が @fig10 に及ばない）
      def test_should_not_touch_labels_with_longer_names
        chapters = [
          chapter('01-intro', "@fig1 と @fig10\n", %w[fig1 fig10]),
          chapter('02-basic', "@fig1\n", ['fig1'])
        ]

        result = ImportCommands.unify_labels(chapters, @report)

        assert_includes result[0].markdown, '@01-intro-fig1 と @fig10'
      end

      # ================================================================
      # catalog の読み取り（同 §6.1）
      # ================================================================
      # catalog に載っていない .re は原稿ではない（書きかけ・没の章が残っている）
      def test_should_read_chapters_from_catalog_in_order
        Dir.mktmpdir('import_test') do |dir|
          File.write(File.join(dir, 'catalog.yml'), <<~YAML, encoding: 'utf-8')
            PREDEF:
              - 00-preface.re
            CHAPS:
              - 導入篇:
                - 01-intro.re
                # - draft.re
            APPENDIX:
              - 91-books.re
            POSTDEF:
              - 99-postface.re
          YAML
          ImportCommands.instance_variable_set(:@starter_dir, dir)

          assert_equal %w[00-preface 01-intro 91-books 99-postface], ImportCommands.catalog_chapters
        end
      end
    end
  end
end
