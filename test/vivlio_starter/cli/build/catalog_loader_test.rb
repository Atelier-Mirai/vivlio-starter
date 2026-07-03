# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'

module VivlioStarter
  module CLI
    module Build
      # Build::CatalogLoader.load_labeled_entries（TokenResolver の下層 API）の仕様検証。
      # 仕様: docs/specs/catalog-parser-unification-spec.md §4
      class CatalogLoaderTest < Minitest::Test
        # --- ラベル伝播 ---

        def test_propagates_part_title_as_label_when_nested
          with_project(<<~YAML) do |paths|
            CHAPTERS:
              - 歴史篇:
                  - 01-life
                  - 02-history
              - 実践篇:
                  - 11-env
          YAML
            entries = CatalogLoader.load_labeled_entries(**paths)

            assert_equal %w[01-life 02-history 11-env], entries.map(&:basename)
            assert_equal '歴史篇', entries.find { it.basename == '01-life' }.label
            assert_equal '実践篇', entries.find { it.basename == '11-env' }.label
          end
        end

        def test_uses_section_name_as_label_when_flat
          with_project(<<~YAML) do |paths|
            CHAPTERS:
              - 01-intro
              - 02-setup
          YAML
            entries = CatalogLoader.load_labeled_entries(**paths)

            assert_equal %w[CHAPTERS CHAPTERS], entries.map(&:label)
            assert_equal %w[CHAPTERS CHAPTERS], entries.map(&:section)
          end
        end

        # --- ショートハンド展開（バグ2の根治確認） ---

        def test_expands_shorthand_range
          files = %w[21-alpha 22-bravo 23-charlie 24-delta 25-echo]
          with_project("CHAPTERS:\n  - 21-25\n", files:) do |paths|
            entries = CatalogLoader.load_labeled_entries(**paths)

            assert_equal files, entries.map(&:basename)
          end
        end

        def test_expands_shorthand_list_with_gap
          files = %w[21-alpha 22-bravo 23-charlie 25-echo]
          with_project("CHAPTERS:\n  - 21-23, 25\n", files:) do |paths|
            entries = CatalogLoader.load_labeled_entries(**paths)

            assert_equal files, entries.map(&:basename)
          end
        end

        # --- YAML エイリアス（バグ1の根治確認） ---

        def test_parses_yaml_aliases
          with_project(<<~YAML) do |paths|
            PREFACE: &empty []
            CHAPTERS:
              - 10-intro
              - 30-outro
            APPENDICES: *empty
            POSTFACE: *empty
          YAML
            entries = CatalogLoader.load_labeled_entries(**paths)

            assert_equal %w[10-intro 30-outro], entries.map(&:basename)
          end
        end

        # --- エラー耐性 ---

        def test_returns_empty_when_catalog_missing
          assert_empty CatalogLoader.load_labeled_entries(
            catalog_path: '/nonexistent/catalog.yml', contents_dir: 'contents'
          )
        end

        def test_raises_on_broken_yaml
          with_raw_catalog("CHAPTERS:\n  - [unbalanced\n") do |paths|
            error = assert_raises(StandardError) { CatalogLoader.load_labeled_entries(**paths) }
            assert_match(/catalog\.yml/, error.message)
          end
        end

        def test_warns_and_ignores_unknown_section
          warnings = []
          with_project(<<~YAML) do |paths|
            CHAPTERS:
              - 01-intro
            CHAPTER:
              - 02-typo
          YAML
            Common.stub(:log_warn, ->(msg) { warnings << msg }) do
              entries = CatalogLoader.load_labeled_entries(**paths)

              # 未知セクション（タイプミス CHAPTER）の章は取り込まれない
              assert_equal %w[01-intro], entries.map(&:basename)
            end
          end

          assert(warnings.any? { it.include?('CHAPTER') }, "未知セクションを警告すべき: #{warnings.inspect}")
        end

        # --- パーサ一本化のリグレッションゲート ---
        # load_all_basenames（ビルド用）と load_labeled_entries（TokenResolver 用）が
        # 同じ basename 集合を返すことを保証する。乖離＝バグの再発。
        def test_labeled_entries_match_load_all_basenames
          catalog = <<~YAML
            PREFACE:
              - 00-preface
            CHAPTERS:
              - 基礎篇:
                  - 10-intro
                  - 21-25
              - 30-outro
            APPENDICES:
              - 90-appendix
            POSTFACE:
              - 99-postface
          YAML
          files = %w[00-preface 10-intro 21-a 22-b 23-c 24-d 25-e 30-outro 90-appendix 99-postface]

          within_chdir_project(catalog, files) do
            assert_equal CatalogLoader.load_all_basenames,
                         CatalogLoader.load_labeled_entries.map(&:basename)
          end
        end

        private

        # 注入パス（catalog_path / contents_dir）で load_labeled_entries を呼ぶための一時プロジェクト。
        # files に basename を渡すとショートハンド展開用の実ファイルを作る。
        def with_project(catalog_yaml, files: [])
          Dir.mktmpdir do |dir|
            catalog_path = File.join(dir, 'catalog.yml')
            contents_dir = File.join(dir, 'contents')
            FileUtils.mkdir_p(contents_dir)
            File.write(catalog_path, catalog_yaml)
            files.each { File.write(File.join(contents_dir, "#{it}.md"), "# #{it}") }

            yield({ catalog_path:, contents_dir: })
          end
        end

        # 破損 YAML など「そのまま書き込みたい」ケース用（with_project は heredoc 整形が入るため）。
        def with_raw_catalog(raw)
          Dir.mktmpdir do |dir|
            catalog_path = File.join(dir, 'catalog.yml')
            File.write(catalog_path, raw)
            yield({ catalog_path:, contents_dir: File.join(dir, 'contents') })
          end
        end

        # load_all_basenames はデフォルトパス（config/catalog.yml・contents/）を見るため、
        # 一時ディレクトリへ chdir してリグレッションゲートを回す。
        def within_chdir_project(catalog_yaml, files)
          Dir.mktmpdir do |dir|
            FileUtils.mkdir_p(File.join(dir, 'config'))
            FileUtils.mkdir_p(File.join(dir, 'contents'))
            File.write(File.join(dir, 'config', 'catalog.yml'), catalog_yaml)
            files.each { File.write(File.join(dir, 'contents', "#{it}.md"), "# #{it}") }

            Dir.chdir(dir) { yield }
          end
        end
      end
    end
  end
end
