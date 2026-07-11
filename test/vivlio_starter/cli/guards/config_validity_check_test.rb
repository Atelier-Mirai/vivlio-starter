# frozen_string_literal: true

# ================================================================
# Test: guards/config_validity_check_test.rb
# ================================================================
# テスト対象:
#   Guards::ConfigValidityCheck（lib/vivlio_starter/cli/guards/config_validity_check.rb）
#
# 検証内容（docs/specs/doctor-restore-and-plugin-tools-spec.md §7.1）:
#   CV-01: 必須 YAML 4 種すべて存在・妥当 → 違反 0 件
#   CV-02: catalog.yml 欠落 → :error 1 件・該当パス
#   CV-03: book.yml が不正 YAML → :error 1 件・解析失敗を detail に
#   CV-04: book.yml の中身が空 → :error 1 件
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class GuardsConfigValidityCheckTest < Minitest::Test
      # CV-01: 4 種すべて存在し妥当な YAML なら合格
      def test_should_pass_when_all_required_yaml_files_are_valid
        with_temp_config do
          write_valid_required_yaml_files

          assert_empty Guards::ConfigValidityCheck.new.validate
        end
      end

      # CV-02: catalog.yml が欠落していれば :error 1 件・該当パスをメッセージに含む
      def test_should_report_error_when_catalog_yml_is_missing
        with_temp_config do
          write_valid_required_yaml_files
          File.delete('config/catalog.yml')

          violations = Guards::ConfigValidityCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert_includes violations.first.message, 'config/catalog.yml'
          assert_includes violations.first.message, '見つかりません'
        end
      end

      # CV-03: book.yml が YAML として解析できなければ :error・detail に解析失敗の内容
      def test_should_report_error_with_detail_when_book_yml_is_corrupt
        with_temp_config do
          write_valid_required_yaml_files
          File.write('config/book.yml', "book: [unclosed\n  main_title: broken\n")

          violations = Guards::ConfigValidityCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert_includes violations.first.message, 'config/book.yml'
          assert_includes violations.first.message, 'YAML 解析に失敗'
          refute_nil violations.first.detail
        end
      end

      # CV-04: book.yml が空（YAML として Hash/Array にならない）なら :error
      def test_should_report_error_when_book_yml_is_empty
        with_temp_config do
          write_valid_required_yaml_files
          File.write('config/book.yml', '')

          violations = Guards::ConfigValidityCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert_includes violations.first.message, 'config/book.yml'
        end
      end

      # diagnose は doctor の復元判断と共有する入口のため、3 状態を直接検証する
      def test_should_diagnose_ok_missing_and_corrupt_states
        with_temp_config do
          File.write('config/book.yml', "book:\n  main_title: 'test'\n")
          assert_equal :ok, Guards::ConfigValidityCheck.diagnose('config/book.yml').first

          assert_equal :missing, Guards::ConfigValidityCheck.diagnose('config/catalog.yml').first

          File.write('config/catalog.yml', "PREFACE: [unclosed\n")
          status, detail = Guards::ConfigValidityCheck.diagnose('config/catalog.yml')
          assert_equal :corrupt, status
          refute_nil detail
        end
      end

      private

      def with_temp_config(&)
        Dir.mktmpdir('vs-config-validity') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            yield
          end
        end
      end

      def write_valid_required_yaml_files
        File.write('config/book.yml', "book:\n  main_title: 'test'\n")
        File.write('config/catalog.yml', "PREFACE:\nCHAPTERS:\n  - 11-intro\nAPPENDICES:\nPOSTFACE:\n")
        File.write('config/page_presets.yml', "presets:\n  a5_standard:\n    size: A5\n")
      end
    end
  end
end
