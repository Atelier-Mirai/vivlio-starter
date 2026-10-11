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

      # --- 読む PDF と章の名前（pdf-read-file-naming-spec.md §2〜§5） ---

      # `/` を含まなければ sources/ の中を探す。`.pdf` は省ける。`/` を含めばそのパス（§2.1）
      def test_should_look_in_sources_unless_the_argument_has_a_slash
        in_project do
          File.write('sources/gitlab.pdf', '')
          File.write('gitlab.pdf', '')

          %w[gitlab gitlab.pdf sources/gitlab.pdf].each do |typed|
            assert_equal(['01-gitlab', 'sources/gitlab.pdf'], resolve(typed), typed)
          end
          assert_equal('./gitlab.pdf', resolve('./gitlab.pdf').last)
        end
      end

      # 大文字・日本語の名前も打ったとおりに探す。小文字に整えた名前で探すと、大文字と小文字を区別する
      # ファイルシステム（Linux・WSL）で見つからず、日本語の名前は整えると消えていた（§1 の 5・6）
      def test_should_look_up_the_file_name_as_typed
        in_project do
          File.write('sources/Hajimete_no_Rust.pdf', '')
          File.write('sources/GPUの育てかた.pdf', '')

          assert_equal(['01-hajimete-no-rust', 'sources/Hajimete_no_Rust.pdf'], resolve('Hajimete_no_Rust.pdf'))
          assert_equal(['01-gpu-book', 'sources/GPUの育てかた.pdf'], resolve('GPUの育てかた.pdf', chapter_name: 'gpu-book'))
        end
      end

      # `/` を含まない指定は、今いるディレクトリを探さない。同じ名前があれば `./` を付けたコマンドを示す（論点 5）
      def test_should_not_read_the_current_directory_without_a_slash
        in_project do
          File.write('gitlab.pdf', '')

          error = assert_raises(PdfReadCommand::MissingPdfError) { resolve('gitlab.pdf') }

          assert_equal("PDF が見つかりません: sources/gitlab.pdf\n" \
                       '→ 今いるディレクトリの PDF なら: vs pdf:read ./gitlab.pdf', error.message)
          error = assert_raises(PdfReadCommand::MissingPdfError) { resolve('missing') }
          assert_equal('PDF が見つかりません: sources/missing.pdf', error.message)
        end
      end

      # `&` を含む名前は、シェルが `&` の所で分けて前の部分だけを渡す。打った名前に `&` が続く PDF があれば、
      # それを示して名前を変えるよう案内する（§2.3）。macOS では、ファイル名の濁点が分かれた形（NFD）のこともある
      def test_should_explain_a_file_name_split_at_an_ampersand
        in_project do
          File.write('sources/データ構造&アルゴリズム.pdf'.unicode_normalize(:nfd), '')

          error = assert_raises(PdfReadCommand::MissingPdfError) { resolve('データ構造') }

          assert_equal(<<~MESSAGE.chomp, error.message.unicode_normalize(:nfc))
            PDF が見つかりません: sources/データ構造.pdf
            sources/データ構造&アルゴリズム.pdf があります。& を含むファイル名は、シェルが & の所で分けて渡すので読み込めません
            ファイル名を、英字で始まる半角の英小文字・数字・ハイフン（-）・アンダースコア（_）だけの名前に変えてから読んでください
            （例: awesome.pdf、my-reference_2047.pdf）
          MESSAGE
        end
      end

      # 二つ目の引数で章の名前を決める。番号を省けば本文の末尾の次、大文字と `_` は整える（§2.2）
      def test_should_name_the_chapter_from_the_second_argument
        in_project do
          File.write('sources/gitlab.pdf', '')
          File.write('contents/61-developer.md', "# developer\n")

          assert_equal('21-git', resolve('gitlab', chapter_name: '21-git').first)
          assert_equal('62-git', resolve('gitlab', chapter_name: 'git').first)
          assert_equal('05-git-basics', resolve('gitlab', chapter_name: '5-Git_Basics').first)
          assert_equal('21-gitlab', resolve('gitlab', chapter_name: '21').first)
        end
      end

      # 点・日本語・数字だけの名前は整えずに止め、使える名前の決まりと例を示す
      def test_should_refuse_a_second_argument_outside_the_rule
        in_project do
          File.write('sources/gitlab.pdf', '')

          { '21-git.v2' => '21-awesome', 'ギット' => '01-awesome', '21-245' => '21-awesome' }.each do |name, example|
            error = assert_raises(PdfReadCommand::InvalidInputError, name) { resolve('gitlab', chapter_name: name) }

            assert_includes(error.message, "#{name} は章の名前に使えません")
            assert_includes(error.message, '（例: awesome、my-reference_2047）')
            assert_includes(error.message, "→ vs pdf:read gitlab #{example}")
          end
        end
      end

      # 複製・ダウンロードの印は、章の名前から外す。PDF を探すときは、ファイル名をそのまま使う（§3.2）
      def test_should_strip_copy_marks_from_the_chapter_name
        in_project do
          ['IPSJ-MGN621105 (1)', 'IPSJ-MGN621105のコピー 2', 'IPSJ-MGN621105 copy 2', 'IPSJ-MGN621105 - Copy (2)',
           'IPSJ-MGN621105 (1)のコピー'].each do |name|
            File.write("sources/#{name}.pdf", '')

            assert_equal(['01-ipsj-mgn621105', "sources/#{name}.pdf"], resolve("#{name}.pdf"), name)
          end
        end
      end

      # 印を外して既にある章と同じ名前になれば、別の章は作らず、読み直しとして止める
      def test_should_treat_a_copy_of_a_read_pdf_as_a_reread
        in_project do
          File.write('sources/IPSJ-MGN621105 (1).pdf', '')
          File.write('contents/62-ipsj-mgn621105.md', "# paper\n")

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('IPSJ-MGN621105 (1).pdf') }

          assert_includes(error.message, '62-ipsj-mgn621105 は既にあります')
          assert_includes(error.message, '→ 読み直して置き換えるなら: vs pdf:read IPSJ-MGN621105\ \(1\).pdf --force')
        end
      end

      # 整った名前でないファイル名からは章を作らず、名前を変える道と名前を添える道を、打った形で示す（§3.1・§2.4）
      def test_should_ask_for_a_name_when_the_file_name_cannot_make_one
        in_project do
          File.write('contents/61-developer.md', "# developer\n")
          %w[245 Vol.53_09_482 コンピュータネットワークのエッセンス].each { File.write("sources/#{it}.pdf", '') }

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('コンピュータネットワークのエッセンス.pdf') }

          assert_equal(<<~MESSAGE.chomp, error.message)
            ファイル名から章の名前を作れません: sources/コンピュータネットワークのエッセンス.pdf
            使える名前: 英字で始まる半角の英小文字・数字・ハイフン（-）・アンダースコア（_）（例: awesome、my-reference_2047）
            → ファイル名を変える: awesome.pdf にしてから vs pdf:read awesome.pdf
            → 章の名前を添える:   vs pdf:read コンピュータネットワークのエッセンス.pdf 62-awesome
            （番号を省くと 62 番になります）
          MESSAGE
          %w[245 Vol.53_09_482].each do |name|
            error = assert_raises(PdfReadCommand::InvalidInputError, name) { resolve(name) }
            assert_includes(error.message, "→ 章の名前を添える:   vs pdf:read #{name} 62-awesome")
          end
        end
      end

      # 案内のコマンドは打った形で返す。sources/ 付きで打てば sources/ 付き、パスで打てば同じパス（§2.4）
      def test_should_echo_the_pdf_as_typed_in_suggested_commands
        in_project do
          dir = Dir.pwd
          File.write('sources/講座.pdf', '')
          FileUtils.mkdir_p('downloads')
          File.write('downloads/講座.pdf', '')

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('sources/講座.pdf') }
          assert_includes(error.message, '→ ファイル名を変える: awesome.pdf にしてから vs pdf:read sources/awesome.pdf')
          assert_includes(error.message, '→ 章の名前を添える:   vs pdf:read sources/講座.pdf 01-awesome')

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve("#{dir}/downloads/講座.pdf") }
          assert_includes(error.message, "ファイル名から章の名前を作れません: downloads/講座.pdf")
          assert_includes(error.message, "→ 章の名前を添える:   vs pdf:read #{dir}/downloads/講座.pdf 01-awesome")
        end
      end

      # 番号を別の章が使っていれば止め、同じ区分の空いている番号で読むコマンドを示す（§4.1）。
      # `vs pdf:read 97-sample-ocr` が 97-sample と同じ番号で章を作り、ビルドを止めていた
      def test_should_refuse_a_number_used_by_another_chapter
        in_project do
          File.write('sources/97-sample-ocr.pdf', '')
          File.write('contents/97-sample.md', "# sample\n")

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('97-sample-ocr') }

          assert_equal("97 番は 97-sample が使っています\n" \
                       "→ 空いている付録の番号: 90\n" \
                       '→ vs pdf:read 97-sample-ocr 90-sample-ocr', error.message)
        end
      end

      # 名前を別の章が使っていれば、番号が違っても止める。その章を読み直すコマンドと、別の名前を示す
      def test_should_refuse_a_name_used_by_another_chapter
        in_project do
          File.write('sources/sample.pdf', '')
          File.write('contents/97-sample.md', "# sample\n")

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('sample', chapter_name: '01-sample') }

          assert_equal("スラッグ sample は 97-sample が使っています\n" \
                       "→ その章を読み直すなら: vs pdf:read sample 97-sample --force\n" \
                       '→ 別の章として読むなら: vs pdf:read sample 01-sample-2', error.message)
        end
      end

      # 番号を省けば本文の一番大きい番号の次。89 まで使われていれば、空いている一番小さい番号（§4.2）
      def test_should_number_after_the_last_body_chapter
        in_project do
          File.write('sources/gitlab.pdf', '')
          %w[01-intro 30-guide 97-sample].each { File.write("contents/#{it}.md", "# #{it}\n") }
          assert_equal('31-gitlab', resolve('gitlab').first)

          File.write('contents/89-last.md', "# last\n")
          assert_equal('02-gitlab', resolve('gitlab').first)
        end
      end

      # 空白で分かれて届いた引数はつなぎ直さず、つなげた名前と使える名前の決まりを示して止める（§2.3）
      def test_should_stop_on_a_file_name_split_by_spaces
        in_project do
          error = assert_raises(PdfReadCommand::InvalidInputError) do
            resolve('2026-06-10', chapter_name: 'at', stray_arguments: %w[10-08-42 AI活用講座.pdf])
          end
          assert_equal(<<~MESSAGE.chomp, error.message)
            ファイル名に空白があるため、読み込めません: sources/2026-06-10 at 10-08-42 AI活用講座.pdf
            ファイル名を、英字で始まる半角の英小文字・数字・ハイフン（-）・アンダースコア（_）だけの名前に変えてから読んでください
            （例: awesome.pdf、my-reference_2047.pdf）
          MESSAGE

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('my', chapter_name: 'notes.pdf') }
          assert_includes(error.message, 'ファイル名に空白があるため、読み込めません: sources/my notes.pdf')
        end
      end

      # 同じ章を読み直すときは止める。--force で置き換え、前回の画像を消す。原稿の頭にどの PDF から読んだかを
      # 残し、二度目の案内に出す（§5）
      def test_should_replace_a_chapter_only_with_force
        in_project do
          write_pdf('sources/gitlab.pdf') { it.draw_text 'First reading', at: [72, 700] }
          read_pdf('gitlab')
          FileUtils.mkdir_p('images/01-gitlab')
          File.write('images/01-gitlab/old.png', '')

          error = assert_raises(PdfReadCommand::InvalidInputError) { read_pdf('gitlab') }
          assert_includes(error.message, '01-gitlab は既にあります（前回 sources/gitlab.pdf から読みました）')
          assert_includes(error.message, '→ 読み直して置き換えるなら: vs pdf:read gitlab --force')
          assert_includes(error.message, '→ 別の章として読むなら: vs pdf:read gitlab 02-gitlab-2')

          read_pdf('gitlab', force: true)

          digest = Digest::SHA256.file('sources/gitlab.pdf').hexdigest
          assert_equal("<!-- pdf:read: sources/gitlab.pdf（sha256: #{digest}） -->", File.readlines('contents/01-gitlab.md', chomp: true).first)
          refute(File.exist?('images/01-gitlab/old.png'))
          assert_equal(['01-gitlab'], File.read('config/catalog.yml').scan(/01-gitlab/))
        end
      end

      # 中身が同じ PDF を別の章として読むときは知らせる。名前を変えて読むのは意図してのことなので、止めない
      def test_should_warn_when_the_same_pdf_was_read_as_another_chapter
        in_project do
          write_pdf('sources/gitlab.pdf') { it.draw_text 'Same content', at: [72, 700] }
          FileUtils.cp('sources/gitlab.pdf', 'sources/copied.pdf')
          read_pdf('gitlab')

          out = read_pdf('copied')

          assert_includes(out, 'この PDF は 01-gitlab として読み込み済みです（中身が同じです）')
          assert(File.exist?('contents/02-copied.md'))
        end
      end

      # --- ページを指定して読む（pdf-read-file-naming-spec.md §10） ---

      # 指定のページだけを原稿に入れる。1 ページだけでも、前後のページを手がかりに柱とノンブルを落とす（§10.3）
      def test_should_read_only_the_given_pages
        in_project do
          write_book_pdf('sources/book.pdf')

          read_pdf('book', chapter_name: 'second', pages: '2')

          text = File.read('contents/01-second.md')
          assert_match(/\A<!-- pdf:read: sources\/book\.pdf p\.2（sha256: \h{64}） -->/, text)
          assert_includes(text, 'Body text of page 2.')
          refute_match(/page [13]\.|RUNNING HEAD|^2$/, text)
        end
      end

      # 飛んだ範囲の境目では段落をつながない。間のページを読んでいないので、続きかどうか分からない
      def test_should_not_join_a_paragraph_across_skipped_pages
        in_project do
          write_book_pdf('sources/book.pdf')

          read_pdf('book', chapter_name: 'skipped', pages: '3,5')
          read_pdf('book', chapter_name: 'joined', pages: '3-4')

          assert_includes(File.read('contents/01-skipped.md'), "This sentence continues\n\nBody text of page 5.")
          assert_includes(File.read('contents/02-joined.md'), 'This sentence continues on the next page and ends here.')
        end
      end

      # ページを指定したときは章の名前を求める。ファイル名から作ると、同じ PDF のどの範囲も同じ名前になる（§10.2）
      def test_should_ask_for_a_chapter_name_when_pages_are_given
        in_project do
          write_book_pdf('sources/book.pdf')
          File.write('contents/61-developer.md', "# developer\n")

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('book.pdf', pages: '31-48,52') }

          assert_equal(<<~MESSAGE.chomp, error.message)
            ページを指定して読むときは、章の名前を添えてください: sources/book.pdf
            使える名前: 英字で始まる半角の英小文字・数字・ハイフン（-）・アンダースコア（_）（例: awesome、my-reference_2047）
            → vs pdf:read book.pdf 62-awesome --pages 31-48,52
            （番号を省くと 62 番になります）
          MESSAGE
        end
      end

      # 範囲の端は省ける。最後のページを越えた分は外して読み、知らせる（§10.1・§10.2）
      def test_should_open_ranges_and_drop_pages_beyond_the_last
        in_project do
          write_book_pdf('sources/book.pdf')

          read_pdf('book', chapter_name: 'head', pages: '-2')
          read_pdf('book', chapter_name: 'tail', pages: '5-')
          out = read_pdf('book', chapter_name: 'beyond', pages: '5-9')

          assert_includes(File.read('contents/01-head.md'), 'p.1-2（')
          assert_includes(File.read('contents/02-tail.md'), 'p.5-6（')
          assert_includes(File.read('contents/03-beyond.md'), 'p.5-6（')
          assert_includes(out, 'ページ 7〜9 はありません。5〜6 を読みます（sources/book.pdf は 6 ページです）')
        end
      end

      # 読めるページが残らないときと、書き方の誤りは、読む前に止める
      def test_should_stop_when_no_given_page_can_be_read
        in_project do
          write_book_pdf('sources/book.pdf')

          error = assert_raises(PdfReadCommand::InvalidInputError) { resolve('book', chapter_name: 'none', pages: '7-9') }
          assert_equal('ページ 7〜9 はありません（sources/book.pdf は 6 ページです）', error.message)

          { '5-3' => 'ページ範囲が逆順です', '0' => '1 以上', 'a' => 'ページ指定が不正です', '-' => 'ページ指定が不正です' }.each do |spec, reason|
            error = assert_raises(PdfReadCommand::InvalidInputError, spec) { resolve('book', chapter_name: 'bad', pages: spec) }
            assert_includes(error.message, "--pages #{spec} を読めません")
            assert_includes(error.message, reason)
          end
          refute(File.exist?('contents/01-none.md'))
        end
      end

      # 同じ PDF から読んだ章があっても、ページが重ならなければ知らせない。章ごとに分けて読むのはふつうの使い方（§10.4）
      def test_should_warn_only_when_pages_of_the_same_pdf_overlap
        in_project do
          write_book_pdf('sources/book.pdf')
          read_pdf('book', chapter_name: 'first', pages: '1-2')

          refute_includes(read_pdf('book', chapter_name: 'second', pages: '3-4'), '読み込み済み')
          assert_includes(read_pdf('book', chapter_name: 'third', pages: '2-3'), 'この PDF は 01-first として読み込み済みです')
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

        in_project do
          File.write('sources/scan.pdf', '')
          @command.stub :resolve_entry_and_pdf, [entry, 'sources/scan.pdf'] do
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
            @command.stub :run_plugin, ['', stderr, failed] do
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
            @command.stub :run_plugin, ['{"pages":3}', "(process:1): GLib-WARNING **: noise\n", succeeded] do
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
          plugin = lambda do |_path, _entry, ocr:, pages: nil|
            requested << ocr
            requested << pages
            { 'images' => [{ 'page' => 1, 'left' => 0, 'bottom' => 0, 'right' => 10, 'top' => 10, 'reference_path' => 'a.webp' }] }
          end

          @command.stub(:contents_dir, dir) do
            @command.stub(:enhanced_result, plugin) { @command.send(:convert_structured, pdf_path, entry, :enhanced) }
          end

          assert_equal([{ mode: 'disable' }, nil], requested)
        end
      end

      # プラグインの経過の行（progress: ocr 5/24）は中継し、失敗の知らせには混ぜない。標準出力は JSON のまま受ける
      def test_should_relay_plugin_progress_and_keep_other_stderr
        script = '$stderr.puts "progress: ocr 1/2"; $stderr.puts "GLib-WARNING"; $stderr.puts "progress: ocr 2/2"; print "{}"'
        logged = []

        stdout, stderr, status = CLI::Common.stub(:log_info, ->(message) { logged << message }) do
          @command.send(:run_plugin, ['ruby', '-e', script])
        end

        assert(status.success?)
        assert_equal('{}', stdout)
        assert_equal("GLib-WARNING\n", stderr)
        assert_equal(['[pdf:read] OCR しています（1/2 ページ）', '[pdf:read] OCR しています（2/2 ページ）'], logged)
      end

      # プラグインが OCR の語を返したら、語の大きさと位置から見出しと段落を戻す（経路 B・§6）
      def test_should_infer_structure_from_ocr_words
        Dir.mktmpdir do |dir|
          pdf_path = File.join(dir, 'scan.pdf')
          write_pdf(pdf_path) { it.stroke_rectangle([72, 700], 200, 100) }
          entry = Data.define(:basename).new('10-scan')
          words = [
            { 'text' => '章の題名', 'x' => 72, 'y' => 760, 'width' => 96, 'size' => 30, 'conf' => 90 },
            *%w[本文の一行目です 続きの二行目です。].each_with_index.map do |text, index|
              { 'text' => text, 'x' => 72, 'y' => 700 - (index * 17), 'width' => text.size * 10.0, 'size' => 12, 'conf' => 90 }
            end
          ]
          result = { 'pages' => 1, 'page_words' => [words], 'page_sizes' => [[595.0, 842.0]], 'images' => [] }

          markdown = @command.stub(:contents_dir, dir) do
            @command.stub(:enhanced_result, result) do
              File.read(@command.send(:convert_enhanced, pdf_path, entry)[:markdown_path])
            end
          end

          assert_equal("# 章の題名\n\n本文の一行目です続きの二行目です。\n", markdown)
        end
      end

      # --images-from を渡すと、抜き出した図のうち見た目の一致したものを元の画像に差し替える。元の画像を
      # 同じ名前で章の画像のフォルダへ写し、参照をその名前にして、抜き出した画像は消す。一致しない図は
      # 抜き出したまま残し、どの図とも結び付かなかった元の画像は名前を挙げて知らせる
      def test_should_substitute_extracted_figures_with_original_images
        skip 'ImageMagick が無い' unless system('which magick >/dev/null 2>&1')

        Dir.mktmpdir do |dir|
          originals = File.join(dir, 'originals')
          extracted = File.join(dir, 'images', '97-sample-ocr')
          FileUtils.mkdir_p([originals, extracted])
          system('magick', '-size', '300x150', 'xc:white', '-fill', 'black', '-draw', 'rectangle 0,0 150,150', File.join(originals, 'half.png'))
          system('magick', '-size', '300x150', 'xc:white', '-fill', 'black', '-draw', 'circle 150,75 150,20', File.join(originals, 'circle.png'))
          # 印刷とスキャンを経た図（半分の大きさで、コントラストが落ち、ぼやける）と、どれとも似ていない図
          system('magick', File.join(originals, 'half.png'), '-resize', '50%', '+level', '15%,85%', '-blur', '0x1', File.join(extracted, 'page-001-image-01.webp'))
          system('magick', '-size', '300x150', 'gradient:white-black', File.join(extracted, 'page-001-image-02.webp'))
          images = %w[page-001-image-01.webp page-001-image-02.webp].map do |name|
            { 'page' => 1, 'left' => 72, 'bottom' => 500, 'right' => 372, 'top' => 650, 'reference_path' => name, 'output_path' => File.join(extracted, name) }
          end
          command = PdfReadCommand.new('97-sample-ocr.pdf', images_from: originals)
          warnings = []

          placements = VivlioStarter::CLI::Common.stub(:log_warn, ->(message, **) { warnings << message }) do
            command.send(:image_placements, { 'images' => images })
          end

          assert_equal(%w[half.png page-001-image-02.webp], placements.map(&:path))
          assert_equal(%w[half.png page-001-image-02.webp], Dir.children(extracted).sort)
          assert_match(/結び付かなかったものが 1 枚.*circle\.png/, warnings.join)
        end
      end

      # 元の画像のフォルダが無ければ、読み始める前に止める
      def test_should_stop_when_images_from_folder_is_missing
        command = PdfReadCommand.new('97-sample-ocr.pdf', images_from: 'no/such/folder')

        error = assert_raises(PdfReadCommand::InvalidInputError) { command.send(:check_images_from!, :enhanced) }
        assert_match(%r{--images-from のフォルダが見つかりません: no/such/folder}, error.message)
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

      # contents/ と sources/ を備えた一時プロジェクトで実行する
      def in_project(&)
        Dir.mktmpdir('vs-pdf-read') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p(%w[config contents sources])
            yield
          end
        end
      end

      # 6 ページの PDF。どのページにも柱（RUNNING HEAD）とノンブルがある。3 ページの末尾の文が 4 ページへ続く
      def write_book_pdf(path)
        write_pdf(path) do |pdf|
          6.times do |index|
            pdf.start_new_page unless index.zero?
            pdf.draw_text 'RUNNING HEAD', at: [72, 800]
            pdf.draw_text "Body text of page #{index + 1}.", at: [72, 700]
            pdf.draw_text 'This sentence continues', at: [72, 100] if index == 2
            pdf.draw_text 'on the next page and ends here.', at: [72, 740] if index == 3
            pdf.draw_text (index + 1).to_s, at: [290, 30]
          end
        end
      end

      # 読む PDF と章の名前を決めるところまで（変換はしない）
      # @return [Array(String, String)] 章の basename と PDF のパス
      def resolve(typed, **options)
        entry, pdf_path = PdfReadCommand.new(typed, options).send(:resolve_entry_and_pdf)
        [entry.basename, pdf_path]
      end

      # Standard Mode で読み、表示を返す
      def read_pdf(typed, **options)
        command = PdfReadCommand.new(typed, options)
        out, = capture_io do
          command.stub(:resolved_mode, :standard) { command.stub(:newline_cleaner, identity_cleaner) { command.call } }
        end
        out
      end
    end
  end
end
