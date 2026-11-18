# frozen_string_literal: true

# ================================================================
# Test: v1_migration_test.rb
# ================================================================
# テスト対象:
#   V1Migration（lib/vivlio_starter/cli/v1_migration.rb）
#   RootCommand#ensure_project_context!（移していない 1.x の本を止める）
#   DoctorCommands#diagnose_book_layout!（本が 2.0 の vs で組めるかを示す）
#
# 検証内容（v2-migration-plan.md §5.7。S11a）:
#   - stylesheets/ の直下に 1.x の雛形の CSS がある本を 1.x の配置と見なす
#   - そういう本は vs build などを 🔴 で止め、二つの道を示す。vs upgrade と vs doctor は止めない
#   - vs doctor は同じ判定を 🟡 で示し、2.0 の本ではテーマの有無と契約の版を示す
#
# vs upgrade の移行そのものは upgrade_commands_test.rb で確かめる。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'samovar'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    class V1MigrationTest < Minitest::Test
      # --- 1.x の雛形の CSS が直下にあれば 1.x の配置。custom.css だけなら 2.0 の配置 ---
      def test_should_tell_the_v1_layout_from_the_new_one
        within_book do
          write('stylesheets/custom.css', "/* 著者 */\n")
          write('stylesheets/parts/box.css', ".column {}\n")
          refute V1Migration.legacy?

          write('stylesheets/page-settings.css', "@page {}\n")
          assert V1Migration.legacy?
          refute V1Migration.legacy?(scaffold_source: scaffold_with('stylesheets/page-settings.css')),
                 '比べる雛形にもある名前は 1.x の印にしない'
        end
      end

      # --- 移していない本は、本を読むコマンドを 🔴 で止め、二つの道を示す ---
      def test_should_stop_book_commands_on_an_unmigrated_book
        within_book do
          write('stylesheets/theme.css', ":root {}\n")
          root = SamovarCommands::RootCommand.new(%w[build])

          out, = capture_io { assert_equal 1, root.call }

          assert_includes out, '🔴 この本は stylesheets/ が 1.x の配置のままなので、2.0 の vs では組めません'
          assert_includes out, '2.0 へ移すなら: vs upgrade'
          assert_includes out, "gem 'vivlio-starter', '~> 1.0'"
          assert_includes out, 'bundle exec vs build'
        end
      end

      # --- vs upgrade は止めない（移すためのコマンド） ---
      def test_should_not_stop_vs_upgrade_on_an_unmigrated_book
        within_book do
          write('stylesheets/theme.css', ":root {}\n")
          root = SamovarCommands::RootCommand.new(%w[upgrade])

          out, = capture_io do
            Common.stub(:ensure_configured!, nil) { root.send(:ensure_project_context!, root.command) }
          end

          refute_includes out, '1.x の配置のまま'
        end
      end

      # --- vs doctor は同じ判定を止めずに 🟡 で示す ---
      def test_should_warn_about_an_unmigrated_book_in_doctor
        within_book do
          write('stylesheets/theme.css', ":root {}\n")

          out, = capture_io { DoctorCommands.send(:diagnose_book_layout!, {}) }

          assert_includes out, '🟡 この本は stylesheets/ が 1.x の配置のままなので'
          refute_includes out, 'テーマ', '1.x の本にはテーマの誤りを重ねて出さない'
        end
      end

      # --- 2.0 の本では、theme.name のテーマが本に無ければ 🟡 で示す ---
      def test_should_warn_about_a_missing_theme_in_doctor
        within_book(theme: 'mytheme') do
          out, = capture_io { DoctorCommands.send(:diagnose_book_layout!, {}) }

          assert_includes out, '🟡 config/book.yml の theme.name のテーマ mytheme が、本の themes/ にありません'
        end
      end

      # --- 2.0 の本で、テーマが読めて契約の版が合えば ✅ ---
      def test_should_report_a_readable_theme_in_doctor
        within_book do
          write('themes/standard/theme.yml', "name: standard\ncontract: 1\n")

          out, = capture_io { DoctorCommands.send(:diagnose_book_layout!, {}) }

          assert_includes out, '✅ テーマ standard: OK'
        end
      end

      # --- テーマの契約の版が、この vs の読めない版なら 🟡 で示す ---
      def test_should_warn_about_an_unsupported_theme_contract_in_doctor
        within_book do
          write('themes/standard/theme.yml', "name: standard\ncontract: 99\n")

          out, = capture_io { DoctorCommands.send(:diagnose_book_layout!, {}) }

          assert_includes out, '🟡 テーマ standard の契約の版（contract: 99）に、この vs は対応していません'
        end
      end

      private

      def within_book(theme: nil)
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write('config/book.yml', theme ? "theme:\n  name: #{theme}\n" : "book:\n  main_title: わたしの本\n")
            yield
          end
        end
      end

      def scaffold_with(relative)
        root = File.join(Dir.pwd, '.scaffold')
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, '')
        root
      end

      def write(relative, content)
        FileUtils.mkdir_p(File.dirname(relative))
        File.write(relative, content, encoding: 'utf-8')
      end
    end
  end
end
