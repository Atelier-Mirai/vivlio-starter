# frozen_string_literal: true

# ================================================================
# Test: doctor/config_salvager_test.rb
# ================================================================
# テスト対象:
#   DoctorCommands::ConfigSalvager（lib/vivlio_starter/cli/doctor/config_salvager.rb）
#
# 検証内容（docs/specs/doctor-restore-and-plugin-tools-spec.md §7.3）:
#   SV-01: catalog.yml 破損 → contents/ から章番号順・正しいセクションで再構築
#   SV-02: 部タイトル・除外設定が復元されない旨を案内する
#   SV-03: book.yml 破損（値の行は無傷） → main_title / author 等を救出
#   SV-04: book.yml の値の行自体が破損 → 当該値は既定値・他の無傷行は救出（取りこぼし容認）
#
# サルベージは best-effort のため、取りこぼしは欠陥ではなく仕様（spec §3D.1）。
# 原本は呼び出し元が .bak へ退避している前提で、ここでは抽出精度のみを検証する。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'

module VivlioStarter
  module CLI
    class ConfigSalvagerTest < Minitest::Test
      SCAFFOLD_BOOK_YML = File.join(DoctorCommands::SCAFFOLD_CONFIG_DIR, 'book.yml')

      # SV-01: contents/ の章ファイルから、章番号順・正しいセクションで catalog を再構築する
      def test_should_rebuild_catalog_from_contents_with_correct_sections
        with_contents(%w[00-preface 12-second 11-first 95-appendix 99-postface _titlepage]) do
          result = DoctorCommands::ConfigSalvager.salvage('config/catalog.yml', 'broken: [', SCAFFOLD_BOOK_YML)

          expected = {
            'PREFACE' => ['00-preface'],
            'CHAPTERS' => %w[11-first 12-second],
            'APPENDICES' => ['95-appendix'],
            'POSTFACE' => ['99-postface']
          }
          assert_equal expected, YAML.safe_load(result.content)
          refute_includes result.content, '_titlepage', 'システムページは目録に含めない'
          assert_includes result.summary, '5 章'
        end
      end

      # SV-02: 部タイトル・除外設定は構造上復元できないことを利用者へ案内する
      def test_should_note_that_part_titles_and_exclusions_are_lost
        with_contents(%w[11-first]) do
          result = DoctorCommands::ConfigSalvager.salvage('config/catalog.yml', 'broken: [', SCAFFOLD_BOOK_YML)

          assert result.notes.any? { it.include?('部タイトル') && it.include?('除外') },
                 '部タイトル・除外設定が失われる旨を notes で案内すべき'
        end
      end

      # contents/ に章ファイルが 1 つも無ければ nil（素の scaffold 復元へフォールバック）
      def test_should_return_nil_when_contents_has_no_chapters
        with_contents([]) do
          assert_nil DoctorCommands::ConfigSalvager.salvage('config/catalog.yml', 'broken: [', SCAFFOLD_BOOK_YML)
        end
      end

      # SV-03: 破損 book.yml でも無傷の単一行スカラーは救出され、復元ファイルへ反映される
      def test_should_salvage_intact_scalar_lines_from_corrupt_book_yml
        corrupt = <<~YAML
          book: {{{broken syntax
            main_title: "わたしの技術書"
            author: "アトリヱ未來"
            series: "夏コミ新刊"
        YAML

        in_tmpdir do
          result = DoctorCommands::ConfigSalvager.salvage('config/book.yml', corrupt, SCAFFOLD_BOOK_YML)

          parsed = YAML.safe_load(result.content, aliases: true)
          assert_equal 'わたしの技術書', parsed['book']['main_title']
          assert_equal 'アトリヱ未來', parsed['book']['author']
          assert_equal '夏コミ新刊', parsed['book']['series'], 'プレースホルダの無いキーも行置換で反映されるべき'
          refute_includes result.content, '{{'
          assert_includes result.summary, '要確認'
          assert result.notes.any? { it.include?('main_title') }
        end
      end

      # SV-04: 破損した値の行は救出されず既定値になるが、他の無傷行は救出される（取りこぼし容認）
      def test_should_skip_broken_value_line_and_salvage_the_rest
        corrupt = <<~YAML
          book:
            main_title: "閉じ引用符のない破損行
            author: "残った著者名"
        YAML

        in_tmpdir do
          result = DoctorCommands::ConfigSalvager.salvage('config/book.yml', corrupt, SCAFFOLD_BOOK_YML)

          parsed = YAML.safe_load(result.content, aliases: true)
          assert_equal '新しい本', parsed['book']['main_title'], '破損行の値は既定値へフォールバックすべき'
          assert_equal '残った著者名', parsed['book']['author']
        end
      end

      # 救出できる値が 1 件も無ければ nil（素の scaffold 復元へフォールバック）
      def test_should_return_nil_when_no_scalar_can_be_salvaged
        in_tmpdir do
          assert_nil DoctorCommands::ConfigSalvager.salvage('config/book.yml', "completely: [broken\n", SCAFFOLD_BOOK_YML)
        end
      end

      # 救出値に YAML を壊す文字（" や \）が含まれていてもエスケープして埋め込む
      def test_should_escape_salvaged_values_for_yaml_safety
        corrupt = %(book: [\n  main_title: 引用"符\\入り\n)

        in_tmpdir do
          result = DoctorCommands::ConfigSalvager.salvage('config/book.yml', corrupt, SCAFFOLD_BOOK_YML)

          parsed = YAML.safe_load(result.content, aliases: true)
          assert_equal %(引用"符\\入り), parsed['book']['main_title']
        end
      end

      private

      def in_tmpdir(&)
        Dir.mktmpdir('vs-salvager') { |dir| Dir.chdir(dir, &) }
      end

      def with_contents(basenames, &)
        in_tmpdir do
          FileUtils.mkdir_p('contents')
          basenames.each { File.write("contents/#{it}.md", "# #{it}\n") }
          yield
        end
      end
    end
  end
end
