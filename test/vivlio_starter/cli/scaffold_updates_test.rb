# frozen_string_literal: true

# ================================================================
# Test: scaffold_updates_test.rb
# ================================================================
# テスト対象:
#   ScaffoldUpdates（lib/vivlio_starter/cli/scaffold_updates.rb）
#
# 検証内容（scaffold-update-notice-spec.md）:
#   - 新しくなった CSS の判定（更新・競合・追加・断った競合・次の更新）
#   - 増えたキーの判定（著者が書いた・消した・親ごと増えた・移すキー・古い lock）
#   - 全章のビルドの知らせの文面と、黙るとき
#   - vs upgrade の最後に並べる行（親のキーつき・雛形の行のまま）
#
# テスト環境:
#   - Dir.mktmpdir にミニ雛形とプロジェクトを組み、scaffold_source で差し替える
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'samovar'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    # 雛形の更新の判定と知らせ
    class ScaffoldUpdatesTest < Minitest::Test
      OLD_CSS = "body { color: black; }\n"
      NEW_CSS = "body { color: navy; }\n"
      CUSTOM_CSS = "body { color: hotpink; }\n"

      BOOK = <<~YAML
        book:
          main_title: "題" # 書名
        theme:
          color: green # 本の色
      YAML

      GROWN_BOOK = <<~YAML
        book:
          main_title: "題" # 書名
          cover: master # 表紙
        theme:
          color: green # 本の色
          lead_size: 1.2 # リードの大きさ
          frontispiece:
            lead_size:     # 章扉のリードの大きさ
        lint:
          line_links: compact # 指摘の行のリンク
        verify:
          # 確かめる項目
          external_links: false # 外部のリンク
          timeout: 10 # 待つ秒数
      YAML

      # --- CSS ---

      def test_should_report_stylesheets_the_author_has_not_touched
        within_project do |scaffold|
          write(scaffold, 'stylesheets/glossary.css', NEW_CSS)
          write('.', 'stylesheets/glossary.css', OLD_CSS)

          lock = lock_with({ 'stylesheets/glossary.css' => OLD_CSS })

          assert_equal ['stylesheets/glossary.css'], ScaffoldUpdates.stale_stylesheets(lock, scaffold)
        end
      end

      def test_should_report_customized_and_missing_stylesheets
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)
          write(scaffold, 'stylesheets/brand-new.css', NEW_CSS)

          lock = lock_with({ 'stylesheets/custom.css' => OLD_CSS })

          assert_equal ['stylesheets/brand-new.css', 'stylesheets/custom.css'],
                       ScaffoldUpdates.stale_stylesheets(lock, scaffold)
        end
      end

      def test_should_stay_silent_when_the_scaffold_has_not_changed
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', OLD_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)

          lock = lock_with({ 'stylesheets/custom.css' => OLD_CSS })

          assert_empty ScaffoldUpdates.stale_stylesheets(lock, scaffold)
        end
      end

      def test_should_not_repeat_a_declined_conflict_until_the_scaffold_changes_again
        within_project do |scaffold|
          write(scaffold, 'stylesheets/custom.css', NEW_CSS)
          write('.', 'stylesheets/custom.css', CUSTOM_CSS)
          lock = lock_with({ 'stylesheets/custom.css' => OLD_CSS })
          lock[:declined] = { 'stylesheets/custom.css' => digest(NEW_CSS) }

          assert_empty ScaffoldUpdates.stale_stylesheets(lock, scaffold), '断ったときと同じ雛形なら言わない'

          write(scaffold, 'stylesheets/custom.css', "body { color: teal; }\n")

          assert_equal ['stylesheets/custom.css'], ScaffoldUpdates.stale_stylesheets(lock, scaffold), '雛形が変われば言う'
        end
      end

      # --- book.yml のキー ---

      def test_should_find_keys_added_since_the_lock
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', GROWN_BOOK)
          write('.', 'config/book.yml', BOOK)

          keys = ScaffoldUpdates.new_book_keys(lock_with({}, book_keys: ScaffoldLock.book_keys(BOOK)), scaffold)

          assert_equal %w[book.cover theme.lead_size theme.frontispiece lint verify], keys, '親ごと増えたら親だけ'
        end
      end

      def test_should_not_list_keys_the_author_removed_or_already_wrote
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', GROWN_BOOK)
          write('.', 'config/book.yml', <<~YAML)
            book:
              main_title: "題"
            theme:
              lead_size: 1.1
          YAML

          keys = ScaffoldUpdates.new_book_keys(lock_with({}, book_keys: ScaffoldLock.book_keys(BOOK)), scaffold)

          refute_includes keys, 'theme.lead_size', '著者が書いたキーは並べない'
          refute_includes keys, 'theme.color', '前の雛形にあって著者が消したキーは並べない'
        end
      end

      def test_should_not_list_the_target_of_a_key_upgrade_will_move
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', GROWN_BOOK)
          write('.', 'config/book.yml', <<~YAML)
            book:
              main_title: "題"
            output:
              cover: master
          YAML

          keys = ScaffoldUpdates.new_book_keys(lock_with({}, book_keys: ScaffoldLock.book_keys(BOOK)), scaffold)

          refute_includes keys, 'book.cover', 'output.cover の値は vs upgrade が移す'
        end
      end

      def test_should_list_every_key_the_author_lacks_when_the_lock_has_no_key_list
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', BOOK)
          write('.', 'config/book.yml', "book:\n  main_title: \"題\"\n")

          assert_equal %w[theme], ScaffoldUpdates.new_book_keys(lock_with({}, book_keys: nil), scaffold)
        end
      end

      def test_should_read_an_authors_book_with_an_unquoted_date
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', BOOK)
          write('.', 'config/book.yml', "book:\n  main_title: \"題\"\n  release: 2026-11-01\ntheme:\n  color: red\n")

          assert_empty ScaffoldUpdates.new_book_keys(lock_with({}, book_keys: ScaffoldLock.book_keys(BOOK)), scaffold)
        end
      end

      # --- 全章のビルドの知らせ ---

      def test_should_report_stylesheets_and_keys_in_two_lines
        within_project do |scaffold|
          prepare_stale_project(scaffold)

          out, = capture_io { ScaffoldUpdates.report(scaffold_source: scaffold) }

          assert_includes out, '💡 雛形が新しくなっています（CSS: colophon.css ほか 1 件・book.yml の設定: 5 件）'
          assert_includes out, 'vs upgrade で確かめられます'
        end
      end

      def test_should_name_only_what_changed
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', BOOK)
          write('.', 'config/book.yml', BOOK)
          write(scaffold, 'stylesheets/glossary.css', NEW_CSS)
          write('.', 'stylesheets/glossary.css', OLD_CSS)
          write_lock({ 'stylesheets/glossary.css' => OLD_CSS })

          out, = capture_io { ScaffoldUpdates.report(scaffold_source: scaffold) }

          assert_includes out, '（CSS: glossary.css）'
        end
      end

      def test_should_stay_silent_without_a_lock
        within_project do |scaffold|
          write(scaffold, 'stylesheets/glossary.css', NEW_CSS)
          write(scaffold, 'config/book.yml', GROWN_BOOK)
          write('.', 'config/book.yml', BOOK)

          out, = capture_io { ScaffoldUpdates.report(scaffold_source: scaffold) }

          assert_empty out
        end
      end

      def test_should_stay_silent_when_the_lock_is_newer_than_the_gem
        within_project do |scaffold|
          prepare_stale_project(scaffold, version: '99.0.0')

          out, = capture_io { ScaffoldUpdates.report(scaffold_source: scaffold) }

          assert_empty out, '共著者が先に更新した本で、古い gem が「新しい」と言わない'
        end
      end

      def test_should_stay_silent_in_a_volume_build_of_vs_build_all
        within_project do |scaffold|
          prepare_stale_project(scaffold)
          ENV[ScaffoldUpdates::SILENT_ENV] = '1'

          out, = capture_io { ScaffoldUpdates.report(scaffold_source: scaffold) }

          assert_empty out
        ensure
          ENV.delete(ScaffoldUpdates::SILENT_ENV)
        end
      end

      def test_should_not_let_a_broken_book_stop_the_build
        within_project do |scaffold|
          prepare_stale_project(scaffold)
          write('.', 'config/book.yml', "book: [\n")

          out, = capture_io { ScaffoldUpdates.report(scaffold_source: scaffold) }

          assert_empty out
        end
      end

      # --- vs upgrade の最後の一覧 ---

      def test_should_print_the_lines_of_the_scaffold_with_their_parents
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', GROWN_BOOK)
          write('.', 'config/book.yml', BOOK)
          lock = lock_with({}, book_keys: ScaffoldLock.book_keys(BOOK))
          plan = ScaffoldUpdates.plan_new_book_keys(lock, scaffold_source: scaffold)

          out, = capture_io { ScaffoldUpdates.report_new_book_keys(plan, scaffold_source: scaffold, dry_run: true) }

          assert_includes out, '💡 book.yml に書ける設定が 5 つ増えました（vs upgrade で足します。値は既定値です）'
          listed = out.lines.map(&:chomp).drop_while { !it.strip.empty? }.drop(1).map { it.delete_prefix(Common::DETAIL_INDENT) }
          assert_equal <<~YAML.lines(chomp: true), listed
            book:
              cover: master # 表紙
            theme:
              lead_size: 1.2 # リードの大きさ
              frontispiece:
                lead_size:     # 章扉のリードの大きさ
            lint:
              line_links: compact # 指摘の行のリンク
            verify:
              # 確かめる項目
              external_links: false # 外部のリンク
              timeout: 10 # 待つ秒数
          YAML
          assert YAML.safe_load(listed.join("\n")), 'そのまま YAML として読める'
        end
      end

      def test_should_stay_silent_when_no_key_is_new
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', BOOK)
          write('.', 'config/book.yml', BOOK)
          lock = lock_with({}, book_keys: ScaffoldLock.book_keys(BOOK))

          assert_nil ScaffoldUpdates.plan_new_book_keys(lock, scaffold_source: scaffold)

          out, = capture_io { ScaffoldUpdates.report_new_book_keys(nil, scaffold_source: scaffold) }

          assert_empty out
        end
      end

      def test_should_list_the_whole_line_for_a_key_written_inside_a_flow_mapping
        within_project do |scaffold|
          write(scaffold, 'config/book.yml', "metrics:\n  section: { min: 1, ideal: 2, max: 3 } # 節の分量\n")
          write('.', 'config/book.yml', "metrics:\n  section: { max: 3 }\n")
          lock = lock_with({}, book_keys: %w[metrics metrics.section metrics.section.max])
          plan = ScaffoldUpdates.plan_new_book_keys(lock, scaffold_source: scaffold)

          out, = capture_io { ScaffoldUpdates.report_new_book_keys(plan, scaffold_source: scaffold) }

          assert_empty plan.added, '1 行にまとめたキーの中には差し込めない'
          assert_includes out, 'book.yml へ自動で足せなかった設定が 2 つあります'
          assert_equal 1, out.scan('section: { min: 1, ideal: 2, max: 3 } # 節の分量').size, '同じ行を 2 度並べない'
        end
      end

      # 配る雛形のどのキーでも、行を写せること
      def test_should_be_able_to_list_every_key_of_the_real_scaffold
        scaffold = NewCommands::SCAFFOLD_SOURCE
        text = File.read(File.join(scaffold, ScaffoldLock::BOOK_RELATIVE), encoding: 'utf-8')
        lines = text.lines(chomp: true)

        ScaffoldLock.book_keys(text).each do |key|
          listed = ScaffoldUpdates.send(:key_lines, text, [key])

          assert_operator listed.size, :>=, 1, key
          assert_includes lines, listed.last, "#{key} は雛形の行のまま並ぶはずです"
        end
      end

      private

      def within_project
        Dir.mktmpdir('vs-scaffold-updates') do |dir|
          project = File.join(dir, 'project')
          scaffold = File.join(dir, 'scaffold')
          FileUtils.mkdir_p([project, scaffold])
          Dir.chdir(project) { yield scaffold }
        end
      end

      def write(root, relative, content)
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def digest(content) = "sha256:#{Digest::SHA256.hexdigest(content)}"

      def lock_with(files, book_keys: [])
        { version: '0.9.0', files: files.transform_values { digest(it) }, book_keys:, declined: {} }
      end

      def write_lock(files, version: '0.9.0', book_keys: ScaffoldLock.book_keys(BOOK))
        ScaffoldLock.write('.', version:, files: files.transform_values { digest(it) }, book_keys:)
      end

      def prepare_stale_project(scaffold, version: '0.9.0')
        write(scaffold, 'config/book.yml', GROWN_BOOK)
        write('.', 'config/book.yml', BOOK)
        %w[colophon glossary].each do |name|
          write(scaffold, "stylesheets/#{name}.css", NEW_CSS)
          write('.', "stylesheets/#{name}.css", OLD_CSS)
        end
        write_lock({ 'stylesheets/colophon.css' => OLD_CSS, 'stylesheets/glossary.css' => OLD_CSS }, version:)
      end
    end
  end
end
