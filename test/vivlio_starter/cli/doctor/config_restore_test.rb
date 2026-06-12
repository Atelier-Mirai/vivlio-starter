# frozen_string_literal: true

# ================================================================
# Test: doctor/config_restore_test.rb
# ================================================================
# テスト対象:
#   DoctorCommands.diagnose_config_files!（lib/vivlio_starter/cli/doctor.rb）
#
# 検証内容（docs/specs/doctor-restore-and-plugin-tools-spec.md §7.2 / §7.3）:
#   DR-01: catalog.yml 欠落 + --fix → scaffold から復元・妥当な YAML になる
#   DR-02: book.yml 破損 + --fix → .bak 退避・本体は妥当・プレースホルダが残らない
#   DR-03: 妥当な book.yml + --fix → 変更されない（バックアップも作らない）
#   DR-04: 破損 + --fix なし → 復元しない・vs doctor --fix を案内する
#   DR-05: spellcheck_dictionaries/ 欠落 + --fix → scaffold から再帰コピー
#   DR-06: spellcheck_dictionaries/ が存在（中身欠け）+ --fix → 触らない
#   SV-05: サルベージ中の想定外例外 → 素の scaffold 復元へフォールバック
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'

module VivlioStarter
  module CLI
    class DoctorConfigRestoreTest < Minitest::Test
      # DR-01: 欠落した catalog.yml が scaffold から復元され、妥当な YAML になる
      def test_should_restore_missing_catalog_yml_from_scaffold
        with_temp_project do
          File.delete('config/catalog.yml')

          out, = capture_io { DoctorCommands.diagnose_config_files!(fix: true, yes: true) }

          assert_path_exists 'config/catalog.yml'
          parsed = YAML.safe_load(File.read('config/catalog.yml'), aliases: true)
          assert_kind_of Hash, parsed
          assert_includes out, 'config/catalog.yml'
        end
      end

      # DR-02: 破損した book.yml は .bak へ退避され、本体は妥当な YAML として復元される
      def test_should_backup_and_restore_corrupt_book_yml
        with_temp_project do
          File.write('config/book.yml', "book: [unclosed\n")

          capture_io { DoctorCommands.diagnose_config_files!(fix: true, yes: true) }

          backups = Dir.glob('config/book.yml.bak.*')
          assert_equal 1, backups.size, '破損ファイルは .bak.<timestamp> へ退避されるべき'
          assert_equal "book: [unclosed\n", File.read(backups.first), '.bak には原本がそのまま残るべき'

          restored = File.read('config/book.yml')
          assert_kind_of Hash, YAML.safe_load(restored, aliases: true)
          refute_includes restored, '{{', 'プレースホルダは既定値へ展開されるべき'
        end
      end

      # DR-03: 妥当な book.yml は --fix でも変更されない（バックアップも作らない）
      def test_should_not_touch_valid_book_yml
        with_temp_project do
          original = File.read('config/book.yml')

          capture_io { DoctorCommands.diagnose_config_files!(fix: true, yes: true) }

          assert_equal original, File.read('config/book.yml')
          assert_empty Dir.glob('config/book.yml.bak.*')
        end
      end

      # DR-04: --fix なしでは復元せず、vs doctor --fix を案内する
      def test_should_only_report_and_hint_fix_without_fix_option
        with_temp_project do
          File.write('config/book.yml', "book: [unclosed\n")

          out, = capture_io { DoctorCommands.diagnose_config_files!(fix: false) }

          assert_equal "book: [unclosed\n", File.read('config/book.yml'), '--fix なしでは復元しない'
          assert_empty Dir.glob('config/book.yml.bak.*')
          assert_includes out, 'vs doctor --fix'
        end
      end

      # DR-05: 欠落した spellcheck_dictionaries/ は scaffold から再帰コピーで復元される
      def test_should_restore_missing_dictionary_dir_from_scaffold
        with_temp_project do
          capture_io { DoctorCommands.diagnose_config_files!(fix: true, yes: true) }

          assert Dir.exist?('config/spellcheck_dictionaries'), '欠落ディレクトリは復元されるべき'
          refute_empty Dir.children('config/spellcheck_dictionaries')
        end
      end

      # DR-06: 存在するディレクトリは中身が欠けていても触らない（存在のみ判定）
      def test_should_not_touch_existing_dictionary_dir
        with_temp_project do
          FileUtils.mkdir_p('config/spellcheck_dictionaries')

          capture_io { DoctorCommands.diagnose_config_files!(fix: true, yes: true) }

          assert_empty Dir.children('config/spellcheck_dictionaries'),
                       '存在するディレクトリには再コピーしない'
        end
      end

      # SV-05: サルベージ中の想定外例外は握りつぶし、素の scaffold 復元で完了する
      def test_should_fall_back_to_plain_restore_when_salvage_raises
        with_temp_project do
          File.write('config/book.yml', "book: [unclosed\n")

          DoctorCommands::ConfigSalvager.stub :salvage, ->(*) { raise 'unexpected salvage failure' } do
            capture_io { DoctorCommands.diagnose_config_files!(fix: true, yes: true) }
          end

          assert_kind_of Hash, YAML.safe_load(File.read('config/book.yml'), aliases: true)
          assert_equal 1, Dir.glob('config/book.yml.bak.*').size
        end
      end

      # 書籍プロジェクトの痕跡が無いディレクトリでは何もしない（config/ を作らない）
      def test_should_do_nothing_outside_book_project
        Dir.mktmpdir('vs-restore-outside') do |dir|
          Dir.chdir(dir) do
            capture_io { DoctorCommands.diagnose_config_files!(fix: true, yes: true) }

            refute Dir.exist?('config'), 'プロジェクト外に config/ を生成してはならない'
          end
        end
      end

      private

      # 必須 YAML と任意設定がすべて妥当に揃った一時プロジェクトへ chdir する。
      # 各テストはここから対象ファイルを削除・破損させて検証する（DAMP）
      def with_temp_project(&)
        Dir.mktmpdir('vs-restore') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            File.write('config/book.yml', "book:\n  main_title: 'test'\n")
            File.write('config/catalog.yml', "PREFACE:\nCHAPTERS:\n  - 11-intro\nAPPENDICES:\nPOSTFACE:\n")
            File.write('config/page_presets.yml', "presets:\n  a5_standard:\n    size: A5\n")
            File.write('config/post_replace_list.yml', "replacements: []\n")
            DoctorCommands::OPTIONAL_CONFIG_FILES.each { File.write("config/#{it}", "# placeholder\n") }
            FileUtils.mkdir_p('config/textlint_dictionaries')
            yield
          end
        end
      end
    end
  end
end
