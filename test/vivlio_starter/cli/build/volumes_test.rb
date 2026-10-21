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
#   - 巻に書いた book: の値（書名・ISBN・発行日・表紙）を book.yml に重ねる。ISBN の共有を 🟡（§3.2・§4.7）
#   - vs cover --volume が巻ごとの値で表紙を作る（§4.8）
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

        # --- 巻をまたぐ参照（§8） ---

        # 別の巻のラベルは、巻の名前を添えた文字にし、リンクにしない。@pageref も章なら章番号と章題
        def test_should_render_reference_to_other_volume_without_link
          label = PreProcessCommands::CrossReferenceProcessor::Label
          labels = {
            'ch-dom' => label.new('ch-dom', :chap, '8', '第8章', 'ページを操作する', '08-dom.md', 1, true),
            'fig-tree' => label.new('fig-tree', :fig, '8', '8-2', 'DOM の木', '08-dom.md', 20, false)
          }
          content = "@chapref:ch-dom と @fig-tree、@pageref:ch-dom を見ます。\n"

          result = PreProcessCommands::CrossReferenceProcessor.replace_references(
            content, labels, nil, other_volumes: { '08-dom.md' => '上巻' }
          )[:content]

          assert_includes result, '<span class="cross-ref-other-volume">上巻 第8章「ページを操作する」</span> と'
          assert_includes result, '<span class="cross-ref-other-volume">上巻 図 8-2</span>'
          assert_equal 2, result.scan('上巻 第8章').size, '@pageref:ch-dom も章番号と章題になる'
          refute_includes result, '<a ', '別の巻へはリンクしない'
        end

        # 別の巻のラベルは、その巻の振り方で数える（組んでいる巻の並びでは数えられない）
        def test_should_number_other_volume_chapters_by_their_volume
          with_project do
            Volumes.select!(Volumes.find('lower'))
            middle = Volumes.find('middle')

            number = Volumes.with_selection(middle) do
              PreProcessCommands::CrossReferenceProcessor.catalog_chapter_number_for('12-more.md')
            end
            text = Volumes.with_selection(middle) do
              PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for('12-more.md')
            end

            assert_equal ['4', '第4章'], [number, text]
            assert_equal({ '12-more.md' => 'middle', '02-basics.md' => 'upper' },
                         PreProcessCommands.other_volume_files(%w[contents/12-more.md contents/02-basics.md
                                                                 contents/21-final.md contents/90-how-to-ask.md])
                                           .transform_values(&:id),
                         '下巻にも載る共通の付録 90 は、下巻の原稿として扱う')
          end
        end

        # --- 全巻の目次（§9） ---

        def test_should_list_every_volume_to_chapters_with_their_numbers
          with_project do
            Volumes.select!(Volumes.find('middle'))

            markdown = WholeTocGenerator.markdown

            assert_includes markdown, '<section class="whole-toc-volume vs-current-volume">' \
                                      "\n<p class=\"whole-toc-volume-name\">中巻</p>", '今の巻だけを目立たせる'
            assert_equal 2, markdown.scan('<section class="whole-toc-volume">').size
            assert_includes markdown, '<li class="whole-toc-part">入門</li>', '部の題名'
            assert_includes markdown, '<li class="whole-toc-chapter"><span class="whole-toc-number">第3章</span>11-apply</li>'
            assert_includes markdown, '<li class="whole-toc-chapter"><span class="whole-toc-number">第1章</span>21-final</li>',
                            '下巻は chapter_start: 1 で始め直す'
            assert_includes markdown, '<li class="whole-toc-preface">10-vol2-intro</li>', '前書きは番号なし'
            assert_includes markdown, '<span class="whole-toc-number">付録 B</span>92-links</li>',
                            '下巻は appendix_start: A で、下巻の付録だけを振り直す（90 が A・92 が B）'
            refute_includes markdown, 'href', 'リンクにしない'
          end
        end

        # 節（##）は詳しい目次と同じ決まりで載せる: page.toc_depth が 2 以上のとき、本文の章と付録だけ、
        # 章扉の節と同じ番号（13-2・A-1）で。ほかの巻は組まないので原稿から取り、コードの中の ## は拾わない
        def test_should_list_sections_of_every_volume_when_toc_depth_allows
          with_project do
            File.write('contents/11-apply.md', <<~MD)
              # 11-apply

              ## 準備する {.no-break}

              ```markdown
              ## コードの中の見出し
              ```

              ## 組む @sec-build
            MD
            File.write('contents/92-links.md', "# 92-links\n\n## 公式サイト\n")
            File.write('contents/10-vol2-intro.md', "# 10-vol2-intro\n\n## 前書きの節\n")
            Volumes.select!(Volumes.find('upper'))

            markdown = TocCommands::HeadingExtractor.stub(:configured_depth, 2) { WholeTocGenerator.markdown }

            assert_includes markdown, '<span class="whole-toc-number">第3章</span>11-apply' \
                                      "\n<ul class=\"whole-toc-sections\">\n" \
                                      '<li class="whole-toc-section"><span class="whole-toc-number">3-1</span>準備する</li>' \
                                      "\n" \
                                      '<li class="whole-toc-section"><span class="whole-toc-number">3-2</span>組む</li>'
            refute_includes markdown, 'コードの中の見出し'
            assert_includes markdown, '<span class="whole-toc-number">B-1</span>公式サイト', '付録の節は付録の記号で'
            refute_includes markdown, '前書きの節', '前書きの節は載せない（詳しい目次と同じ）'

            chapters_only = TocCommands::HeadingExtractor.stub(:configured_depth, 1) { WholeTocGenerator.markdown }
            refute_includes chapters_only, 'whole-toc-sections', 'toc_depth: 1 なら章まで'
          end
        end

        def test_should_include_whole_toc_only_for_volume_asking_for_it
          with_project(catalog: CATALOG.sub("    id: middle\n", "    id: middle\n    whole_toc: true\n")) do
            Volumes.select!(Volumes.find('middle'))
            assert WholeTocGenerator.needed?

            Volumes.select!(Volumes.find('upper'))
            refute WholeTocGenerator.needed?

            Volumes.select!(:combined)
            refute WholeTocGenerator.needed?, '合本には載せない'
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

        # --- 書誌情報の上書き（段階 5） ---

        BOOK_YML = <<~YAML
          book:
            main_title: "全巻の書名"
            author: "著者"
            release: "令和八年十月一日"
            isbn: "978-4-0000-0000-0"
            cover: master
        YAML

        def test_should_override_only_book_values_written_in_volume
          catalog = CATALOG.sub("  - name: 上巻\n    id: upper\n",
                                "  - name: 上巻\n    id: upper\n    main_title: 上巻の書名\n    isbn: \"978-4-0000-0000-1\"\n")
                           .sub("  - name: 下巻\n    id: lower\n",
                                "  - name: 下巻\n    id: lower\n    release: 令和九年一月十日\n    isbn: \"\"\n    cover: lower\n")
          with_project(catalog:, book_yml: BOOK_YML) do
            original = Common::CONFIG

            Volumes.apply_config!(Volumes.find('upper'))
            book = Common::CONFIG.book
            assert_equal ['上巻の書名', '978-4-0000-0000-1', '令和八年十月一日', 'master', '著者'],
                         [book.main_title, book.isbn, book.release, book.cover, book.author], '書かないキーは book.yml の値'

            Volumes.apply_config!(Volumes.find('lower'))
            book = Common::CONFIG.book
            assert_equal ['全巻の書名', '', '令和九年一月十日', 'lower'], [book.main_title, book.isbn, book.release, book.cover],
                         'isbn: "" は「この巻には ISBN がない」として上書きする'
          ensure
            Common.install_configuration!(original)
          end
        end

        # 巻の設定の名前と book: のキーが重なると、巻の中でどちらの値か区別できない（§3.2）
        def test_should_keep_book_keys_apart_from_volume_settings
          assert_empty Volumes::BOOK_KEYS & Volumes::VOLUME_KEYS
          assert(Volumes::BOOK_KEYS.none? { it.match?(/[A-Z]/) }, '大文字のキーは目次の区分')
          assert_includes Volumes::BOOK_KEYS, 'cover', 'cover は book: の下へ移した（§3.5）'
        end

        def test_should_accept_book_keys_written_in_volume
          catalog = CATALOG.sub("    id: middle\n", "    id: middle\n    release: 令和九年\n    cover: middle\n    isbn: \"\"\n")
          with_project(catalog:) { assert_empty Guards::VolumeDefinitionCheck.new.validate }
        end

        def test_should_warn_when_volumes_share_isbn_of_book_yml
          catalog = CATALOG.sub("    id: middle\n", "    id: middle\n    isbn: \"978-4-0000-0000-2\"\n")
          with_project(catalog:, book_yml: BOOK_YML) do
            warnings = Guards::VolumeDefinitionCheck.new.validate

            assert_equal 1, warnings.size
            assert warnings.first.warn?
            assert_includes warnings.first.message, '上巻・下巻が、book.yml の ISBN（978-4-0000-0000-0）を共有しています'
            assert_includes Array(warnings.first.detail).first, 'config/catalog.yml:2 上巻'
          end

          # 上書きしない巻が一つだけなら、book.yml の ISBN をその巻のものとみなす
          catalog = catalog.sub("    id: lower\n", "    id: lower\n    isbn: \"\"\n")
          with_project(catalog:, book_yml: BOOK_YML) { assert_empty Guards::VolumeDefinitionCheck.new.validate }
        end

        # vs cover は vs build と同じく、--volume で巻・all で全巻・何も付けなければ合本の表紙を作る（§4.8）
        def test_should_make_covers_with_values_of_each_volume
          catalog = CATALOG.sub("    id: upper\n", "    id: upper\n    cover: upper\n")
                           .sub("    id: lower\n", "    id: lower\n    cover: lower\n")
          with_project(catalog:, book_yml: BOOK_YML) do
            original = Common::CONFIG
            made = []
            record = -> { made << [Volumes.current&.id, Common.cover_theme, Common.generate_cover_output_filename('front')] }

            CoverCommands.stub(:execute_generate, ->(_ = nil) { record.call }) do
              Common.stub(:log_action, nil) do
                run_cover('--volume', 'all')
                run_cover('--volume', '中巻')
                run_cover
              end
            end

            assert_equal [['upper', 'upper'], ['middle', 'master'], ['lower', 'lower'], ['middle', 'master'], [nil, 'master']],
                         made.map { it.first(2) }, '巻の cover、書かない巻と合本は book.yml の cover'
            assert_match(/_lower_frontcover/, made[2].last)
            refute_match(/_(upper|middle|lower)_/, made.last.last, '合本の表紙の名前に巻の id は入らない')
            assert_nil Volumes.current, '作り終えたら巻の選択を戻す'
          ensure
            Common.install_configuration!(original)
          end
        end

        def test_should_stop_cover_for_unknown_volume
          with_project do
            out, err = capture_io { assert_equal 1, run_cover('--volume', 'fourth') }
            assert_includes out + err, '巻 fourth が config/catalog.yml の VOLUMES に見つかりません'
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

        def run_cover(*argv)
          Guards.stub(:precheck, nil) { SamovarCommands::CoverCommand.new(argv).call }
        end

        def with_project(catalog: CATALOG, book_yml: nil)
          Dir.mktmpdir('vs-volumes') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(%w[config contents])
              File.write('config/catalog.yml', catalog)
              File.write('config/book.yml', book_yml) if book_yml
              BASENAMES.each { File.write("contents/#{it}.md", "# #{it}\n") }
              Common.stub(:log_info, nil) { yield }
            end
          end
        end
      end
    end
  end
end
