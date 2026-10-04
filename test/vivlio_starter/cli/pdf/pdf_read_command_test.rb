# frozen_string_literal: true

require "tmpdir"

require "test_helper"
require "vivlio_starter/cli/pdf/pdf_read_command"

module VivlioStarter
  module Commands
    # PdfReadCommand のテストスイート
    class PdfReadCommandTest < Minitest::Test
      # テスト用のコマンドインスタンスを初期化する
      def setup
        @command = PdfReadCommand.new("dummy.pdf")
      end

      # text_area_margin_points が mm を pt に正しく変換することを検証する
      def test_text_area_margin_points_converts_mm_to_points
        margins_cfg = {
          top_margin: 10,
          bottom_margin: 12,
          inner_margin: 8,
          outer_margin: 6
        }

        @command.stub :pdf_read_text_area, margins_cfg do
          @command.instance_variable_set(:@text_area_margin_points, nil)
          margins = @command.send(:text_area_margin_points)

          assert_in_delta(28.346, margins[:top], 0.001)
          assert_in_delta(34.015, margins[:bottom], 0.001)
          assert_in_delta(22.677, margins[:inner], 0.001)
          assert_in_delta(17.008, margins[:outer], 0.001)
        end
      end

      # page_separator が有効な場合、ページ間に "---" が挿入されることを検証する
      def test_build_markdown_inserts_page_separator_when_enabled
        @command.stub :pdf_read_page_separator?, true do
          markdown = @command.send(:build_markdown, ["一頁目", "二頁目"])

          assert_equal("一頁目\n\n---\n\n二頁目\n", markdown)
        end
      end

      # page_separator が無効な場合、ページチャンクが改行除去で結合されることを検証する
      def test_build_markdown_merges_page_chunks_when_separator_disabled
        cleaner = Object.new
        cleaner.define_singleton_method(:clean) { |text| text.gsub("\n", "") }

        @command.stub :pdf_read_page_separator?, false do
          @command.stub :newline_cleaner, cleaner do
            markdown = @command.send(:build_markdown, ["基本的な理解が必要", "です。"])

            assert_equal("基本的な理解が必要です。\n", markdown)
          end
        end
      end

      # auto モードでプラグインが利用可能な場合、enhanced モードが選択されることを検証する
      def test_resolved_mode_uses_enhanced_when_plugin_is_available_in_auto_mode
        command = PdfReadCommand.new("dummy.pdf", mode: "auto")

        # rake test:standard は VIVLIO_PDF_PLUGIN=disable で走るので、指定の無い状態を作る
        with_plugin_env(nil) do
          command.stub :plugin_available?, true do
            assert_equal(:enhanced, command.send(:resolved_mode))
          end
        end
      end

      # auto モードでプラグインが利用不可な場合、standard モードにフォールバックすることを検証する
      def test_resolved_mode_falls_back_to_standard_when_plugin_is_unavailable_in_auto_mode
        command = PdfReadCommand.new("dummy.pdf", mode: "auto")

        command.stub :plugin_available?, false do
          assert_equal(:standard, command.send(:resolved_mode))
        end
      end

      # convert_enhanced がプラグインの page_texts から Markdown を生成することを検証する
      def test_convert_enhanced_writes_markdown_from_plugin_page_texts
        identity_cleaner = Object.new
        identity_cleaner.define_singleton_method(:clean) { |text| text }
        entry = Data.define(:basename).new("10-sample")
        result_payload = {
          page_texts: ["第1章 プログラミング技術習得の三要素\n本文です。", "- ii -\n続きです。"],
          page_chunks: [
            "第1章 プログラミング技術習得の三要素\n本文です。",
            "![](images/10-sample/page-002-image-01.webp)\n続きです。"
          ],
          pages: 2,
          images: [
            { page: 2, reference_path: "images/10-sample/page-002-image-01.webp" }
          ]
        }

        Dir.mktmpdir do |dir|
          @command.stub :contents_dir, dir do
            @command.stub :enhanced_result, result_payload do
              @command.stub :newline_cleaner, identity_cleaner do
                @command.stub :pdf_read_page_separator?, true do
                  result = @command.send(:convert_enhanced, "dummy.pdf", entry)
                  markdown = File.read(result[:markdown_path], encoding: "UTF-8")

                  assert_equal(File.join(dir, "10-sample.md"), result[:markdown_path])
                  assert_equal(2, result[:pages])
                  assert_equal("第1章 プログラミング技術習得の三要素\n本文です。\n\n---\n\n![](images/10-sample/page-002-image-01.webp)\n\n続きです。\n", markdown)
                end
              end
            end
          end
        end
      end

      # enhanced_command が OCR 設定を正しく JSON 形式で含むことを検証する
      def test_enhanced_command_includes_ocr_settings
        entry = Data.define(:basename).new("10-sample")

        @command.stub :pdf_read_page_separator?, false do
          @command.stub :text_area_margin_points, { top: 1.0, bottom: 2.0, inner: 3.0, outer: 4.0 } do
            @command.stub :line_merge_tolerance, 2.5 do
              @command.stub :enhanced_images_output_dir, "/tmp/images-out" do
                @command.stub :enhanced_images_reference_dir, "images/10-sample" do
                  @command.stub :pdf_read_ocr, { mode: "always", languages: %w[japanese japanese_vertical eng], dpi: 220, psm: 6, inline_image_text: "captionize" } do
                    command = @command.send(:enhanced_command, "dummy.pdf", entry)
                    ocr_token = command.find { it.start_with?("ocr=") }

                    refute_nil(ocr_token)
                    assert_equal(
                      { "mode" => "always", "languages" => ["jpn", "jpn_vert", "eng"], "dpi" => 220, "psm" => 6, "inline_image_text" => "captionize" },
                      JSON.parse(ocr_token.delete_prefix("ocr="))
                    )
                  end
                end
              end
            end
          end
        end
      end

      # normalize_inline_image_text がエイリアスを正規化し、既定値 include にフォールバックすることを検証する
      def test_normalize_inline_image_text_falls_back_to_include
        assert_equal("include", @command.send(:normalize_inline_image_text, nil))
        assert_equal("captionize", @command.send(:normalize_inline_image_text, "caption"))
        assert_equal("captionize", @command.send(:normalize_inline_image_text, "caption_only"))
        assert_equal("exclude", @command.send(:normalize_inline_image_text, "remove"))
      end

      # normalize_ocr_languages がユーザーフレンドリーなエイリアス（japanese 等）を受け入れることを検証する
      def test_normalize_ocr_languages_accepts_user_friendly_aliases
        assert_equal(
          %w[jpn jpn_vert eng],
          @command.send(:normalize_ocr_languages, %w[japanese japanese_vertical english])
        )
      end

      # page_separator 無効時に画像参照が独立ブロックとして正規化されることを検証する
      def test_build_markdown_normalizes_image_reference_as_standalone_block_when_separator_disabled
        identity_cleaner = Object.new
        identity_cleaner.define_singleton_method(:clean) { |text| text }

        @command.stub :pdf_read_page_separator?, false do
          @command.stub :newline_cleaner, identity_cleaner do
            markdown = @command.send(:build_markdown, ["前文", "![](images/10-sample/page-001-image-01.webp)本文"])

            assert_equal("前文\n\n![](images/10-sample/page-001-image-01.webp)\n\n本文\n", markdown)
          end
        end
      end

      # normalize_image_reference_blocks が既存の空行を重複させないことを検証する
      def test_normalize_image_reference_blocks_does_not_duplicate_existing_blank_lines
        markdown = "前文\n\n![](images/10-sample/page-001-image-01.webp)\n\n本文"

        assert_equal(markdown, @command.send(:normalize_image_reference_blocks, markdown))
      end

      # ensure_unique_output_entry が既存カタログエントリに対して新しい basename を割り当てることを検証する
      def test_ensure_unique_output_entry_allocates_new_basename_for_existing_catalog_entry
        entry = VivlioStarter::CLI::TokenResolver::Entry.new(
          number: "10",
          slug: "three-elements-pages",
          kind: :chapter,
          label: "歴史篇",
          path: "contents/10-three-elements-pages.md",
          exists: true,
          in_catalog: true,
          valid: true
        )

        @command.stub :markdown_exists?, true do
          @command.stub :next_available_basename, "11-three-elements-pages" do
            resolved = @command.send(:ensure_unique_output_entry, entry)

            assert_equal("11-three-elements-pages", resolved.basename)
            refute(resolved.exists?)
            refute(resolved.in_catalog?)
          end
        end
      end

      # ensure_unique_output_entry が既存の未カタログエントリに対して新しい basename を割り当てることを検証する
      def test_ensure_unique_output_entry_allocates_new_basename_for_existing_uncatalogued_entry
        entry = VivlioStarter::CLI::TokenResolver::Entry.new(
          number: "10",
          slug: "three-elements-pages",
          kind: :chapter,
          label: "UNCATALOGED",
          path: "contents/10-three-elements-pages.md",
          exists: true,
          in_catalog: false,
          valid: true
        )

        @command.stub :markdown_exists?, true do
          @command.stub :next_available_basename, "11-three-elements-pages" do
            resolved = @command.send(:ensure_unique_output_entry, entry)

            assert_equal("11-three-elements-pages", resolved.basename)
            refute(resolved.exists?)
            refute(resolved.in_catalog?)
          end
        end
      end

      # call が既存 Markdown に対して自動採番を行うことを検証する
      def test_call_auto_numbers_for_chapter_token_input_when_markdown_exists
        entry = VivlioStarter::CLI::TokenResolver::Entry.new(
          number: "10",
          slug: "three-elements-ocr",
          kind: :chapter,
          label: "歴史篇",
          path: "contents/10-three-elements-ocr.md",
          exists: true,
          in_catalog: true,
          valid: true
        )
        new_entry = VivlioStarter::CLI::TokenResolver::Entry.new(
          number: "11",
          slug: "three-elements-ocr",
          kind: :chapter,
          label: nil,
          path: "contents/11-three-elements-ocr.md",
          exists: false,
          in_catalog: false,
          valid: true
        )
        result = { markdown_path: "contents/11-three-elements-ocr.md", pages: 7 }

        @command.stub :resolve_entry_and_pdf, [entry, "sources/three-elements-ocr.pdf"] do
          @command.stub :ensure_unique_output_entry, new_entry do
            @command.stub :add_catalog_entry_if_needed, nil do
              @command.stub :resolved_mode, :enhanced do
                @command.stub :convert_enhanced, result do
                  resolved = @command.call

                  assert_equal("contents/11-three-elements-ocr.md", resolved[:markdown_path])
                  assert_equal("11-three-elements-ocr", resolved[:entry].basename)
                end
              end
            end
          end
        end
      end

      # plugin_available? が vivlio-starter-pdf の --version コマンドで可用性を確認することを検証する
      def test_plugin_available_checks_vivlio_starter_pdf_version_command
        status = Data.define(:success?).new(true)

        Open3.stub :capture2e, ["0.1.0\n", status] do
          @command.instance_variable_set(:@plugin_checked, false)
          @command.instance_variable_set(:@plugin_available, false)

          assert_equal(true, @command.send(:plugin_available?))
        end
      end

      # enhanced_plugin_command がインストール済みの実行ファイルを返すことを検証する
      def test_enhanced_plugin_command_returns_installed_executable
        assert_equal(
          ["vivlio-starter-pdf"],
          @command.send(:enhanced_plugin_command)
        )
      end

      # capture_enhanced_command が Bundler 環境下で with_unbundled_env を使用することを検証する
      def test_capture_enhanced_command_uses_unbundled_env_under_bundler
        status = Data.define(:success?).new(true)
        command = ["vivlio-starter-pdf", "--version"]

        Bundler.stub :with_unbundled_env, proc { |&block| block.call } do
          Open3.stub :capture2e, ->(*args, **options) {
            assert_equal(command, args)
            assert_empty(options) # chdir オプションなし
            ["1.0.1\n", status]
          } do
            stdout, captured_status = @command.send(:capture_enhanced_command, *command)

            assert_equal("1.0.1\n", stdout)
            assert_equal(status, captured_status)
          end
        end
      end


      # strip_fallback_borders がヘッダー・フッターフィルタリング前に bottom マージンを適用することを検証する
      def test_strip_fallback_borders_applies_bottom_margin_before_header_footer_filtering
        page = Data.define(:mediabox).new([0, 0, 100, 100])
        lines = ["第1章 サンプル", "本文1", "本文2", "脚注テキスト"]
        margins = { top: 0.0, bottom: 25.0, inner: 0.0, outer: 0.0 }

        @command.stub :text_area_margin_points, margins do
          filtered = @command.send(:strip_fallback_borders, lines, page)

          assert_equal(["第1章 サンプル", "本文1", "本文2"], filtered)
        end
      end

      # strip_fallback_borders が最初のページでは下部の行を保持することを検証する
      def test_strip_fallback_borders_keeps_bottom_lines_on_first_page
        page = Data.define(:mediabox).new([0, 0, 100, 100])
        lines = ["第1章", "プログラミング技術習得の三要素", "比較しながら考えてみましょう。"]
        margins = { top: 0.0, bottom: 40.0, inner: 0.0, outer: 0.0 }

        @command.stub :text_area_margin_points, margins do
          filtered = @command.send(:strip_fallback_borders, lines, page, index: 0)

          assert_equal(["第1章", "プログラミング技術習得の三要素", "比較しながら考えてみましょう。"], filtered)
        end
      end

      # strip_fallback_borders が2ページ目以降で繰り返される章タイトルヘッダーを除去することを検証する
      def test_strip_fallback_borders_removes_repeated_chapter_title_header_on_later_pages
        page = Data.define(:mediabox).new([0, 0, 100, 100])
        lines = ["第1章 プログラミング技術習得の三要素", "♣ 2. ⽂法：表現のルール", "本文です。"]
        margins = { top: 0.0, bottom: 0.0, inner: 0.0, outer: 0.0 }

        @command.stub :text_area_margin_points, margins do
          filtered = @command.send(:strip_fallback_borders, lines, page, index: 1)

          assert_equal(["♣ 2. ⽂法：表現のルール", "本文です。"], filtered)
        end
      end

      # strip_fallback_borders が最初のページの見出しと一致する数値柱を除去することを検証する
      def test_strip_fallback_borders_removes_numeric_pillar_when_heading_matches_first_page
        page = Data.define(:mediabox).new([0, 0, 100, 100])
        lines = ["1-1 プログラミング技術習得の三要素", "本文です。"]
        margins = { top: 0.0, bottom: 0.0, inner: 0.0, outer: 0.0 }

        @command.instance_variable_set(:@first_page_heading_tokens, ["プログラミング技術習得の三要素"])

        @command.stub :text_area_margin_points, margins do
          filtered = @command.send(:strip_fallback_borders, lines, page, index: 1)

          assert_equal(["本文です。"], filtered)
        end
      end

      # strip_fallback_borders が最初のページと一致しない数値見出しを保持することを検証する
      def test_strip_fallback_borders_keeps_numeric_heading_when_not_matching_first_page
        page = Data.define(:mediabox).new([0, 0, 100, 100])
        lines = ["1-1 別の章タイトル", "本文です。"]
        margins = { top: 0.0, bottom: 0.0, inner: 0.0, outer: 0.0 }

        @command.instance_variable_set(:@first_page_heading_tokens, ["プログラミング技術習得の三要素"])

        @command.stub :text_area_margin_points, margins do
          filtered = @command.send(:strip_fallback_borders, lines, page, index: 1)

          assert_equal(lines, filtered)
        end
      end


      # newline_cleaner が設定なしで MecabNewlineCleaner を使用することを検証する
      def test_newline_cleaner_uses_mecab_cleaner_without_config
        fake_cleaner_class = Class.new do
          class << self
            attr_reader :initialized_with
          end

          def initialize(*args)
            self.class.instance_variable_set(:@initialized_with, args)
          end
        end

        original_cleaner = VivlioStarter::PDF.const_get(:MecabNewlineCleaner)
        VivlioStarter::PDF.send(:remove_const, :MecabNewlineCleaner)
        VivlioStarter::PDF.const_set(:MecabNewlineCleaner, fake_cleaner_class)

        begin
          @command.instance_variable_set(:@newline_cleaner, nil)
          cleaner = @command.send(:newline_cleaner)

          assert_instance_of(fake_cleaner_class, cleaner)
          assert_equal([], fake_cleaner_class.initialized_with)
        ensure
          VivlioStarter::PDF.send(:remove_const, :MecabNewlineCleaner)
          VivlioStarter::PDF.const_set(:MecabNewlineCleaner, original_cleaner)
        end
      end

      # VIVLIO_PDF_PLUGIN=disable なら、プラグインがあっても Standard Mode で読む。
      # 以前は pdf:read だけがこの指定を見ず、94 章の説明と食い違っていた
      def test_should_use_standard_mode_when_plugin_is_disabled_by_env
        with_plugin_env('disable') do
          @command.stub :plugin_available?, true do
            assert_equal(:standard, @command.send(:resolved_mode))
          end
        end
      end

      # 自分から disable で切ったときは、入れてある gem の導入を勧めない
      def test_should_not_suggest_plugin_install_when_plugin_is_disabled_by_env
        logged = []

        with_plugin_env('disable') do
          VivlioStarter::CLI::Common.stub :log_info, ->(message) { logged << message } do
            @command.send(:log_enhanced_install_hint)
          end
        end

        assert_empty(logged)
      end

      # Standard Mode は座標で版面の外を除く。柱とノンブルは落とし、版面の下端近くの
      # 脚注は残す。以前は pdf-reader に無い `text_runs` を問い合わせて毎回 fallback へ
      # 落ち、下端の行を比率で捨てる処理で脚注が消えていた
      def test_should_keep_footnote_and_drop_running_head_when_reading_by_coordinates
        Dir.mktmpdir do |dir|
          pdf_path = File.join(dir, 'book.pdf')
          write_pdf(pdf_path) do |pdf|
            pdf.draw_text 'Front page body', at: [72, 700]
            pdf.start_new_page
            pdf.draw_text 'RUNNING HEAD', at: [72, 815]
            30.times { pdf.draw_text "Body line #{it + 1}", at: [72, 760 - (it * 20)] }
            pdf.draw_text 'Footnote text sits near the bottom', at: [72, 70]
            pdf.draw_text '12', at: [290, 30]
          end
          entry = Data.define(:basename).new('10-book')

          markdown = @command.stub(:contents_dir, dir) do
            @command.stub(:newline_cleaner, identity_cleaner) do
              @command.stub(:pdf_read_page_separator?, false) do
                @command.stub(:text_area_margin_points, { top: 51.0, bottom: 56.7, inner: 42.5, outer: 34.0 }) do
                  File.read(@command.send(:convert_standard, pdf_path, entry)[:markdown_path])
                end
              end
            end
          end

          assert_includes(markdown, 'Body line 30')
          assert_includes(markdown, 'Footnote text sits near the bottom')
          refute_includes(markdown, 'RUNNING HEAD')
          refute_match(/^12$/, markdown)
        end
      end

      # 文字の層が無い PDF（スキャンなど）は、空の原稿を書かずに止めて OCR を案内する。
      # 以前は 0 バイトの Markdown を作って「変換しました」と報告していた
      def test_should_stop_without_writing_markdown_when_pdf_has_no_text
        Dir.mktmpdir do |dir|
          pdf_path = File.join(dir, 'scan.pdf')
          write_pdf(pdf_path) { it.stroke_rectangle([72, 700], 200, 100) }
          entry = Data.define(:basename).new('10-scan')

          error = @command.stub(:contents_dir, dir) do
            assert_raises(PdfReadCommand::Error) { @command.send(:convert_standard, pdf_path, entry) }
          end

          assert_includes(error.message, 'PDF から文字を一つも取り出せませんでした（1 ページ）')
          assert_includes(error.message, 'gem install vivlio-starter-pdf')
          refute(File.exist?(File.join(dir, '10-scan.md')))
        end
      end

      # 変換が失敗したら catalog.yml に章を載せない。中身の無い章が目次に残らないように
      def test_should_not_register_catalog_entry_when_conversion_fails
        entry = VivlioStarter::CLI::TokenResolver::Entry.new(
          number: '10', slug: 'scan', kind: :chapter, label: nil, path: 'contents/10-scan.md',
          exists: false, in_catalog: false, valid: true
        )
        registered = []

        @command.stub :resolve_entry_and_pdf, [entry, 'sources/scan.pdf'] do
          @command.stub :ensure_unique_output_entry, entry do
            @command.stub :add_catalog_entry_if_needed, ->(e) { registered << e } do
              @command.stub :resolved_mode, :standard do
                @command.stub :convert_standard, ->(*) { raise PdfReadCommand::Error, '文字がありません' } do
                  assert_raises(PdfReadCommand::Error) { @command.call }
                end
              end
            end
          end
        end

        assert_empty(registered)
      end

      # `read` を持たない 1.1.x のプラグインが失敗したら、更新の手順と Standard への切り替えを案内する
      def test_should_explain_plugin_update_when_plugin_does_not_know_read
        failed = Data.define(:success?).new(false)
        stderr = "Error: Unknown option 'read'\nUse 'vivlio-starter-pdf --help' for usage information.\n"

        @command.stub :ensure_enhanced_plugin_loaded!, nil do
          @command.stub :enhanced_command, ['vivlio-starter-pdf', 'read', 'dummy.pdf'] do
            Open3.stub :capture3, ['', stderr, failed] do
              error = assert_raises(PdfReadCommand::Error) { @command.send(:enhanced_result, 'dummy.pdf', nil) }

              assert_includes(error.message, 'gem update vivlio-starter-pdf')
              assert_includes(error.message, 'VIVLIO_PDF_PLUGIN=disable vs pdf:read dummy.pdf')
            end
          end
        end
      end

      # JSON は標準出力だけから読む。標準エラーの警告が混ざっても壊れない
      def test_should_parse_json_from_stdout_even_when_plugin_warns_on_stderr
        succeeded = Data.define(:success?).new(true)

        @command.stub :ensure_enhanced_plugin_loaded!, nil do
          @command.stub :enhanced_command, ['vivlio-starter-pdf', 'read', 'dummy.pdf'] do
            Open3.stub :capture3, ['{"pages":3}', "(process:1): GLib-WARNING **: noise\n", succeeded] do
              assert_equal({ 'pages' => 3 }, @command.send(:enhanced_result, 'dummy.pdf', nil))
            end
          end
        end
      end

      # タグ付き PDF は構造ツリーから見出しと段落を戻す（pdf-read-structure-spec.md の経路 A）
      def test_should_rebuild_structure_from_tagged_pdf
        Dir.mktmpdir do |dir|
          pdf_path = File.join(dir, 'tagged.pdf')
          write_tagged_pdf(pdf_path)
          entry = Data.define(:basename).new('10-tagged')

          result = @command.stub(:contents_dir, dir) { @command.send(:convert_structured, pdf_path, entry, :standard) }

          assert_equal({ markdown_path: File.join(dir, '10-tagged.md'), pages: 1 }, result)
          assert_equal("# Tagged Title\n\nBody paragraph.\n", File.read(result[:markdown_path]))
        end
      end

      # タグの無い PDF は、紙面の文字の大きさと位置から見出しと段落を推定する（経路 B）
      def test_should_infer_structure_from_untagged_pdf
        Dir.mktmpdir do |dir|
          pdf_path = File.join(dir, 'plain.pdf')
          write_pdf(pdf_path) do |pdf|
            pdf.draw_text 'Inferred Title', at: [72, 760], size: 24
            pdf.draw_text 'The first line of a paragraph runs across the page.', at: [72, 720]
            pdf.draw_text 'It continues on the second line.', at: [72, 705]
          end
          entry = Data.define(:basename).new('10-plain')

          result = @command.stub(:contents_dir, dir) { @command.send(:convert_structured, pdf_path, entry, :standard) }

          assert_equal(<<~MARKDOWN, File.read(result[:markdown_path]))
            # Inferred Title

            The first line of a paragraph runs across the page. It continues on the second line.
          MARKDOWN
        end
      end

      # 文字の層の無い PDF（スキャン）は構造を戻さず、これまでの読み方（OCR）に任せる
      def test_should_leave_scanned_pdf_to_text_reading
        Dir.mktmpdir do |dir|
          pdf_path = File.join(dir, 'scan.pdf')
          write_pdf(pdf_path) { it.stroke_rectangle([72, 700], 200, 100) }
          entry = Data.define(:basename).new('10-scan')

          result = @command.stub(:contents_dir, dir) { @command.send(:convert_structured, pdf_path, entry, :standard) }

          assert_nil(result)
          refute(File.exist?(File.join(dir, '10-scan.md')))
        end
      end

      # Enhanced Mode の経路 A は、文字を構造ツリーから読むので、プラグインには OCR を切って画像だけを頼む
      def test_should_ask_plugin_for_images_without_ocr_when_reading_structure
        Dir.mktmpdir do |dir|
          pdf_path = File.join(dir, 'tagged.pdf')
          write_tagged_pdf(pdf_path)
          entry = Data.define(:basename).new('10-tagged')
          requested = []
          plugin = lambda do |_path, _entry, ocr:|
            requested << ocr
            { 'images' => [{ 'page' => 1, 'left' => 0, 'bottom' => 0, 'right' => 10, 'top' => 10, 'reference_path' => 'a.webp' }] }
          end

          @command.stub(:contents_dir, dir) do
            @command.stub(:enhanced_result, plugin) { @command.send(:convert_structured, pdf_path, entry, :enhanced) }
          end

          assert_equal([{ mode: 'disable' }], requested)
        end
      end

      private

      # 見出しと段落だけのタグ付き PDF を Prawn で書く。文字を MCID で囲み、構造ツリーを書き込む
      def write_tagged_pdf(path)
        write_pdf(path) do |pdf|
          page = pdf.state.page.dictionary
          kids = [['H1', 'Tagged Title', 760, 20], ['P', 'Body paragraph.', 720, 12]].each_with_index.map do |(type, text, y, size), mcid|
            pdf.add_content("/Span <</MCID #{mcid}>> BDC")
            pdf.draw_text(text, at: [72, y], size:)
            pdf.add_content('EMC')
            pdf.ref!(Type: :StructElem, S: type.to_sym, K: mcid, Pg: page)
          end
          pdf.state.store.root.data[:StructTreeRoot] = pdf.ref!(Type: :StructTreeRoot, K: kids)
        end
      end

      # VIVLIO_PDF_PLUGIN を一時的に設定し、ブロックを抜けたら元へ戻す。nil なら消す
      def with_plugin_env(value)
        original = ENV.fetch('VIVLIO_PDF_PLUGIN', nil)
        ENV['VIVLIO_PDF_PLUGIN'] = value
        yield
      ensure
        ENV['VIVLIO_PDF_PLUGIN'] = original
      end

      def identity_cleaner
        Object.new.tap { it.define_singleton_method(:clean) { |text| text } }
      end

      def write_pdf(path, &)
        require 'prawn'
        Prawn::Document.generate(path, page_size: 'A4', margin: 0, &)
      end
    end
  end
end
