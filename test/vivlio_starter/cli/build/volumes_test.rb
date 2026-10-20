# frozen_string_literal: true

# ================================================================
# Test: volumes_test.rb
# ================================================================
# テスト対象（multivolume-spec.md）:
#   Build::Volumes と、分冊の目次を読む・書く各所
#   - 目次の見え方: 巻・合本・全巻（§3.4・§4.3・§6.1）
#   - 番号: 章番号は前の巻から続け、chapter_start で始め直す。付録は初めて出た巻で記号を振る（§5）
#   - --volume の指定の誤り（§4.5）と、巻の書き方の検査（§3.3）
#   - vs create / delete / rename が巻の中を書き換える（§7）
#   - 出力ファイル名に巻の id を入れる（§4.6）
#
# 2 巻だけで確かめると「最初の巻でなければ最後の巻」という思い込みが隠れるので、上中下の 3 巻で確かめる（§2）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module Build
      class VolumesTest < Minitest::Test
        CATALOG = <<~YAML
          VOLUMES:
            - name: 上巻
              id: upper
              PREFACE:
                - 00-preface
              CHAPTERS:
                - 入門:
                    - 01-intro
                    - 02-basics
              APPENDICES:
                - 90-how-to-ask

            - name: 中巻
              id: middle
              PREFACE:
                - 10-vol2-intro
              CHAPTERS:
                - 11-apply
                - 12-more
                - 13-deep
              APPENDICES:
                - 90-how-to-ask
                - 91-tools

            - name: 下巻
              id: lower
              chapter_start: 1
              appendix_start: A
              PREFACE:
                - 20-vol3-intro
              CHAPTERS:
                - 21-final
              APPENDICES:
                - 92-links
                - 90-how-to-ask
              POSTFACE:
                - 99-postface
        YAML

        BASENAMES = %w[00-preface 01-intro 02-basics 90-how-to-ask 10-vol2-intro 11-apply 12-more 13-deep
                       91-tools 20-vol3-intro 21-final 92-links 99-postface].freeze

        def teardown
          Volumes.select!(nil)
        end

        # --- 目次の見え方 ---

        def test_should_show_only_the_selected_volume
          with_project do
            Volumes.select!(Volumes.find('middle'))

            assert_equal %w[10-vol2-intro 11-apply 12-more 13-deep 90-how-to-ask 91-tools],
                         CatalogLoader.load_all_basenames
          end
        end

        def test_should_combine_first_preface_all_chapters_and_last_postface
          with_project do
            Volumes.select!(:combined)
            catalog = CatalogLoader.load_catalog

            assert_equal ['00-preface'], catalog['PREFACE'], '2 巻目以降の前書きは合本に載せない'
            assert_equal ['99-postface'], catalog['POSTFACE']
            assert_equal %w[01-intro 02-basics 11-apply 12-more 13-deep 21-final],
                         CatalogLoader.flatten_section(catalog['CHAPTERS'])
            assert_equal %w[90-how-to-ask 91-tools 92-links], catalog['APPENDICES'], '共通の付録は一つにまとめる'
          end
        end

        def test_should_see_every_manuscript_by_default
          with_project do
            kinds = TokenResolver::Resolver.new.resolve.to_h { [it.basename, it.kind] }

            assert_equal BASENAMES.sort, kinds.keys.sort, '既定では全巻の原稿を見る'
            assert_equal :preface, kinds['10-vol2-intro']
            assert_equal :preface, kinds['20-vol3-intro']
          end
        end

        # --- 番号 ---

        def test_should_continue_chapter_numbers_and_restart_with_chapter_start
          with_project do
            assert_equal({ 'upper' => 1, 'middle' => 3, 'lower' => 1 }, Volumes.chapter_starts)

            Volumes.select!(Volumes.find('middle'))
            assert_equal 2, Volumes.chapter_offset
            assert_equal '第3章', PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for('11-apply'),
                         '中巻は上巻の 2 章の続きから数える'
            assert_equal '第5章', PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for('13-deep')
          end
        end

        def test_should_letter_appendices_by_first_appearance_across_volumes
          with_project do
            Volumes.select!(Volumes.find('middle'))
            assert_equal 'a', Common.appendix_number_to_letter(90), '上巻で初めて出た付録は、中巻でも同じ記号'
            assert_equal 'b', Common.appendix_number_to_letter(91), '中巻で初めて出た付録は次の記号'

            Volumes.select!(Volumes.find('upper'))
            assert_equal 'a', Common.appendix_number_to_letter(90)
          end
        end

        def test_should_restart_appendix_letters_with_appendix_start
          with_project do
            Volumes.select!(Volumes.find('lower'))

            assert_equal 'a', Common.appendix_number_to_letter(90), '下巻の付録だけを番号の順に A から振る'
            assert_equal 'b', Common.appendix_number_to_letter(92)
          end
        end

        # 目次の「第 N 章」「付録 A」は CSS のカウンタなので、章扉と同じ番号になるよう始まりを与える
        def test_should_start_toc_counters_from_volume_numbers
          with_project do
            FileUtils.mkdir_p('html')
            Volumes.select!(Volumes.find('middle'))
            PostProcessCommands::HeadingProcessor.chapter_number_offset = 2
            entry_map = %w[11-apply 91-tools].to_h do |bn|
              path = File.expand_path("html/#{bn}.html")
              File.write(path, %(<html><body><h1 id="h-#{bn}">#{bn}</h1></body></html>))
              [path, TokenResolver::Resolver.new.resolve_file(bn)]
            end

            toc = TocCommands::TocDocumentBuilder.new(entry_map, base_dir: 'html', depth: 1).build

            assert_includes toc, '<ul style="counter-reset: toc-list-counter 2 toc-list-appendix-counter 0">',
                            '中巻の最初の章は第3章（カウンタは 2 から増える）'
            assert_includes toc, '<li class="toc-chapter-appendix" style="counter-reset: toc-list-appendix-counter 1">',
                            '中巻で初めて出た付録 91 は付録 B'
          ensure
            PostProcessCommands::HeadingProcessor.chapter_number_offset = 0
          end
        end

        # PDF のしおりは、前書きに番号の範囲から「第 N 章」を付けない
        def test_should_not_number_volume_preface_in_outline
          with_project do
            assert_equal '', OutlineExtractor.resolve_chapter_number_display('10-vol2-intro', { number_display: '' })
          end
        end

        # --- --volume の指定 ---

        def test_should_find_volume_by_id_or_name_and_explain_unknown_one
          with_project do
            assert_equal 'lower', Volumes.find!('下巻').id
            error = assert_raises(Volumes::SelectionError) { Volumes.find!('vol9') }
            assert_includes error.detail, 'upper（上巻）、middle（中巻）、lower（下巻）'
          end
        end

        def test_should_explain_how_to_write_volumes_when_catalog_has_none
          with_project(catalog: "CHAPTERS:\n  - 01-intro\n") do
            error = assert_raises(Volumes::SelectionError) { Volumes.find!('upper') }
            assert_includes error.message, 'VOLUMES'
            assert_includes error.detail, 'VOLUMES:'
          end
        end

        # --- 巻の書き方の検査 ---

        def test_should_accept_well_formed_volumes
          with_project { assert_empty Guards::VolumeDefinitionCheck.new.validate }
        end

        def test_should_stop_on_mixed_sections_bad_ids_and_shared_chapters
          catalog = <<~YAML
            CHAPTERS:
              - 05-stray
            VOLUMES:
              - name: 上巻
                id: Upper
                CHAPTERS:
                  - 01-intro
              - name: 上巻
                id: all
                CHAPTERS:
                  - 01-intro
                colour: red
          YAML
          with_project(catalog:) do
            violations = Guards::VolumeDefinitionCheck.new.validate
            messages = violations.map(&:message)

            assert(messages.any? { it.include?('一番上の CHAPTERS') }, '一番上の区分と VOLUMES の併記')
            assert(messages.any? { it.include?('英小文字・数字・_') }, 'id の形')
            assert(messages.any? { it.include?('all は使えません') }, 'id の all')
            assert(messages.any? { it.include?('name が 上巻 で同じ') }, 'name の重なり')
            assert(messages.any? { it.include?('01-intro が、上巻と上巻') }, '同じ本文の章を二つの巻に')
            assert(violations.any? { it.warn? && it.message.include?('colour') }, '知らない設定キーは 🟡')
          end
        end

        # --- 章の管理コマンド ---

        def test_should_add_new_chapter_to_volume_of_previous_number
          with_project do
            CatalogUpdater.add_chapter('14-extra')
            Volumes.select!(Volumes.find('middle'))

            assert_includes CatalogLoader.load_all_basenames, '14-extra', '13 を載せた中巻に足すこと'
            assert_includes File.read('config/catalog.yml'), "      - 13-deep\n      - 14-extra\n", '巻の中の字下げにそろえる'
          end
        end

        def test_should_add_to_chosen_volume_and_part
          with_project do
            CatalogUpdater.add_chapter('03-extra', volume: Volumes.find('upper'))

            assert_includes File.read('config/catalog.yml'), "          - 02-basics\n          - 03-extra\n",
                            '部の中の字下げにそろえる'
          end
        end

        def test_should_remove_and_rename_in_every_volume
          with_project do
            CatalogUpdater.rename_chapter('90-how-to-ask', '90-asking')
            text = File.read('config/catalog.yml')
            assert_equal 3, text.scan('- 90-asking').size, '共通の付録は、載っているすべての巻で書き換える'

            CatalogUpdater.remove_chapter('90-asking')
            refute_includes File.read('config/catalog.yml'), '90-asking'
          end
        end

        # --- 出力ファイル名 ---

        def test_should_put_volume_id_into_output_names
          with_project do
            config = Common::CONFIG
            Volumes.select!(Volumes.find('lower'))

            assert_match(/\A#{Regexp.escape(config.project.name)}_lower(_v.+)?\.pdf\z/,
                         Common.generate_output_filename('pdf'))
            assert_match(/_lower_frontcover/, Common.generate_cover_output_filename('front'))
          end
        end

        def test_should_clear_workspace_when_switching_volumes
          with_project do
            Volumes.select!(Volumes.find('upper'))
            Volumes.prepare_workspace!
            FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
            File.write(File.join(Common::BUILD_HTML_DIR, '01-intro.html'), '')

            Volumes.select!(Volumes.find('lower'))
            Common.stub(:log_action, nil) { Volumes.prepare_workspace! }

            refute File.exist?(File.join(Common::BUILD_HTML_DIR, '01-intro.html')), '前の巻の HTML を残さない'
            assert_equal 'lower', File.read(Volumes.workspace_marker)
          end
        end

        private

        def with_project(catalog: CATALOG)
          Dir.mktmpdir('vs-volumes') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(%w[config contents])
              File.write('config/catalog.yml', catalog)
              BASENAMES.each { File.write("contents/#{it}.md", "# #{it}\n") }
              Common.stub(:log_info, nil) { yield }
            end
          end
        end
      end
    end
  end
end
