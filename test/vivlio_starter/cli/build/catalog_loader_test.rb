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
      # 仕様: catalog-parser-unification-spec.md §4
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

        # --- 番号だけの項目と、書けない書き方（範囲・一行の形） ---

        # 番号だけの項目は、その番号の原稿を指す（contents/24.md のように番号だけの原稿も）
        def test_expands_number_only_items
          with_project("CHAPTERS:\n  - 22\n  - 24\n", files: %w[22-bravo 24]) do |paths|
            assert_equal %w[22-bravo 24], CatalogLoader.load_labeled_entries(**paths).map(&:basename)
          end
        end

        # 範囲で書いた章は、消しても範囲に番号が残り、改番すると別の章を指すので書けない。
        # 原稿のある番号だけを一つずつ書いた形を示す
        def test_rejects_number_range_with_numbers_spelled_out
          within_chdir_project("CHAPTERS:\n  - 21-25\n", %w[21-alpha 22-bravo 23-charlie 25-echo]) do
            error = assert_raises(StandardError) { CatalogLoader.load_catalog }

            assert_includes error.message, '番号の範囲か一行の形で書いた章があります'
            assert_includes error.message, "config/catalog.yml:2\n      - 21-25\n"
            assert_includes error.message, "      - 21\n      - 22\n      - 23\n      - 25\n"
            assert_includes error.message, 'vs build 21-23 のように範囲を打てます'
          end
        end

        # 範囲を含まない並び（`- 21, 25`）も、行で書き換えられないので同じく止める。
        # 以前は「contents/??-21, 25.md が見つかりません」と、原因のわからない案内になっていた
        def test_rejects_comma_list_item_with_numbers_spelled_out
          within_chdir_project("CHAPTERS:\n  - 21, 25\n  - 22 - 23\n", %w[21-alpha 22-bravo 23-charlie 25-echo]) do
            error = assert_raises(StandardError) { CatalogLoader.load_catalog }

            assert_includes error.message, "config/catalog.yml:2\n      - 21, 25\n  → リストの形で、章を一つずつ書いてください:\n      - 21\n      - 25\n"
            assert_includes error.message, "config/catalog.yml:3\n      - 22 - 23\n  → リストの形で、章を一つずつ書いてください:\n      - 22\n      - 23\n"
          end
        end

        # 一行の形は vs create が書き足せない（二つ目の CHAPTERS: ができ、前の章が黙って消える）
        def test_rejects_one_line_section_with_list_form
          within_chdir_project("CHAPTERS: 21-23, 25  # 番号で指定\n", %w[21-alpha 22-bravo 23-charlie 25-echo]) do
            error = assert_raises(StandardError) { CatalogLoader.load_catalog }

            assert_includes error.message, "config/catalog.yml:1\n    CHAPTERS: 21-23, 25\n"
            assert_includes error.message, "    CHAPTERS:\n      - 21\n      - 22\n      - 23\n      - 25"
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
                  - 22
              - 30-outro
            APPENDICES:
              - 90-appendix
            POSTFACE:
              - 99-postface
          YAML
          files = %w[00-preface 10-intro 22-b 30-outro 90-appendix 99-postface]

          within_chdir_project(catalog, files) do
            assert_equal CatalogLoader.load_all_basenames,
                         CatalogLoader.load_labeled_entries.map(&:basename)
          end
        end

        # --- 区分の無い目次の案内 ---

        # 区分を書かずに原稿を並べた目次は読めない。著者の並びを番号で区分に分けた例を添えて、
        # そのまま写せば直るようにする
        def test_explains_sections_with_authors_own_items
          within_chdir_project("- 00-preface\n- 11-intro.md\n- 90-tips\n", %w[00-preface 11-intro 90-tips]) do
            error = assert_raises(StandardError) { CatalogLoader.load_catalog }

            assert_includes error.message, '区分の無い並びになっています'
            assert_includes error.message, "    PREFACE:\n      - 00-preface\n    CHAPTERS:\n      - 11-intro\n" \
                                           "    APPENDICES:\n      - 90-tips"
          end
        end

        # 前書きと本文の章をまたぐ範囲（00-02）を一つの区分に置くと、区分で種類が決まるため
        # 本文の章まで前書きになる。範囲は原稿の名前に開いてから区分を分ける
        def test_splits_a_range_across_sections_in_the_explanation
          within_chdir_project("00-02\n", %w[00-preface 01-intro 02-setup]) do
            message = CatalogLoader.unsectioned_catalog_message('00-02')

            assert_includes message, "    PREFACE:\n      - 00-preface\n    CHAPTERS:\n      - 01-intro\n      - 02-setup"
          end
        end

        # `00-02` とだけ書いた目次は、必須ファイルの検査で止まる。ファイルの作り直し（doctor --fix）では
        # なく、区分の書き方を示す
        def test_required_files_check_explains_sections_for_scalar_catalog
          within_chdir_project("00-02\n", %w[00-preface 01-intro]) do
            File.write('config/book.yml', "book:\n  main_title: 本\n")
            File.write('config/page_presets.yml', "b5_standard:\n  width: 182mm\n")

            out, err = capture_io { assert_raises(SystemExit) { Common.ensure_required_yaml_files! } }

            assert_includes out + err, '区分の無い並びになっています'
            refute_includes out + err, 'doctor --fix'
          end
        end

        # 番号だけの項目も、章の削除・改名・改番に追随する（contents/24.md のような原稿もあるので、
        # 番号の項目も章の名前の一つ）。行末の注釈は残す
        def test_number_only_entries_follow_delete_rename_and_renumber
          catalog = "CHAPTERS:\n  - 21\n  - 22   # 番号で指定\n  - 23-c\n  - 24\n"
          within_chdir_project(catalog, %w[21-a 22-b 23-c 24]) do
            Common.stub(:log_info, nil) do
              CatalogUpdater.remove_chapter('22-b')
              assert_equal "CHAPTERS:\n  - 21\n  - 23-c\n  - 24\n", File.read('config/catalog.yml'), '削除'

              CatalogUpdater.rename_chapter('24', '28-d')
              assert_equal "CHAPTERS:\n  - 21\n  - 23-c\n  - 28\n", File.read('config/catalog.yml'), '改名（番号の形のまま）'

              # 改番は対応表を一度に当てる（1 章ずつだと 21→23 の後に 23→25 が当たり、- 21 が 25 まで動く）
              CatalogUpdater.rename_chapters('21-a' => '23-a', '23-c' => '25-c', '28-d' => '27-d')
              assert_equal "CHAPTERS:\n  - 23\n  - 25-c\n  - 27\n", File.read('config/catalog.yml'), '改番'
            end
          end
        end

        private

        # 注入パス（catalog_path / contents_dir）で load_labeled_entries を呼ぶための一時プロジェクト。
        # files に basename を渡すと番号だけの項目を原稿の名前にするための実ファイルを作る。
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
