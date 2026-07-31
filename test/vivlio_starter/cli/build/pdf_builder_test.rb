# frozen_string_literal: true

# ================================================================
# Test: pdf_builder_test.rb
# ================================================================
# テスト対象:
#   PdfBuilder（lib/vivlio_starter/cli/build/pdf_builder.rb）
#
# 検証内容:
#   - Step 8: 全体PDF生成（build_overall_pdf_from_dir!）
#   - Step 9: 表紙・奥付PDF生成（build_front_pages_and_tail!）
#   - PDF分割スキップの確認（内部リンク維持のため）
#
# 設計方針:
#   - PDF分割をスキップし、全体を1つのPDFとして生成
#   - 索引から前書きへのリンクなど内部リンクが維持される
#   - ローマ数字ノンブルはCSSの @page front で対応
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader' # sections_entry_htmls は TokenResolver / IndexCommands を辿る
require 'vivlio_starter/cli/build'

module VivlioStarter
  module CLI
    module Build
      class PdfBuilderTest < Minitest::Test
        # 章レンジ定数が正しく定義されていることを確認
        def test_chapter_ranges_are_defined
          assert_equal (0..0), PdfBuilder::PREFACE_RANGE, '前書きは 00 のみ'
          assert_equal (1..89), PdfBuilder::MAIN_RANGE, '本文は 01-89'
          assert_equal (90..98), PdfBuilder::APPX_RANGE, '付録は 90-98'
          assert_equal (99..99), PdfBuilder::POSTFACE_RANGE, '後書きは 99 のみ'
        end

        # compile_overall_pdf! が対象HTMLなしの場合に早期リターンすることを確認
        def test_compile_overall_pdf_returns_early_when_no_targets
          # 空の配列を渡すと警告を出して早期リターン
          logged_warnings = []
          Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
            PdfBuilder.compile_overall_pdf!([])
          end

          assert logged_warnings.any? { it.include?('対象HTMLが見つかりません') },
                 '対象HTMLが空の場合は警告を出すべき'
        end

        # _preface_toc.pdf は生成されなくなったことを確認
        def test_preface_toc_pdf_is_no_longer_generated
          # PDF分割をスキップしたため、_preface_toc.pdf は生成されない
          # compile_overall_pdf! は _sections.pdf のみを生成する
          refute File.exist?('_preface_toc.pdf'),
                 '_preface_toc.pdf は新しい設計では生成されない'
        end
      end

      # ================================================================
      # PDF 結合（PdfMerger）のテスト
      # ================================================================
      # 注: かつてクラス冒頭の `private` が test_ メソッドの定義まで巻き込んでおり、
      #     Minitest は public な test_ しか集めないため、本クラスは 1 件も実行されて
      #     いなかった。ヘルパを末尾へ寄せて可視性の巻き込みを断ってある。
      class PdfMergerTest < Minitest::Test
        def setup
          @original_config = Common::CONFIG
        end

        def teardown
          Common.install_configuration!(@original_config)
        end

        # 結合対象はカバー設定と targets に応じて組み立てられる
        def test_should_wrap_the_body_with_front_and_back_covers_when_pdf_is_targeted
          install_config(targets: ['pdf'], cover: 'master', combined: true)

          assert_equal [cover_path('frontcover'), *matter_paths, cover_path('backcover')],
                       segment_paths(existing: [cover_path('frontcover'), cover_path('backcover')]),
                       'front/back カバーが結合対象に含まれるべき'
        end

        # pdf ターゲットが無ければ表紙は綴じない（EPUB 用の表紙は別経路）
        def test_should_omit_covers_when_pdf_is_not_targeted
          install_config(targets: ['epub'], cover: 'master', combined: true)

          assert_equal matter_paths, segment_paths, 'pdf 対象でない場合はカバーを含めない'
        end

        # output.pdf.combined: false は「表紙を別ファイルで入稿する」意思表示
        def test_should_omit_covers_when_combining_is_disabled
          install_config(targets: ['pdf'], cover: 'master', combined: false)

          assert_equal matter_paths, segment_paths, 'combined=false の場合は front/back を結合しない'
        end

        # 生成されていない表紙は黙って飛ばす（ビルドは止めない）
        def test_should_skip_covers_that_were_not_generated
          install_config(targets: ['pdf'], cover: 'master', combined: true)

          assert_equal [*matter_paths, cover_path('backcover')],
                       segment_paths(existing: [cover_path('backcover')]),
                       '存在する表紙だけを結合対象にするべき'
        end

        # add_outline_to_output_pdf! が output.pdf なしの場合に早期リターンすることを確認
        def test_add_outline_returns_early_when_no_output_pdf
          logged_warnings = []
          Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
            File.stub :exist?, false do
              result = PdfMerger.add_outline_to_output_pdf!(nil)
              assert_equal false, result, 'output.pdf がない場合は false を返すべき'
            end
          end
        end

        private

        # book.yml 相当を CONFIG として差し込む。CONFIG は Data なので、生の Hash を
        # const_set するとドット記法が壊れる——必ず wrap_config を通すこと。
        def install_config(targets:, cover:, combined:)
          Common.install_configuration!(
            Common.wrap_config(
              output: { targets:, cover:, pdf: { combined: } },
              page: { use: 'a4_standard' },
              cache: { dir: Common::CACHE_DIR, enabled: true },
              directories: { covers: 'covers' }
            ).freeze
          )
        end

        # 生成済み表紙の置き場は キャッシュ dir（final clean を生き延びる）
        def cover_path(kind) = File.join(Common.cover_cache_dir, "#{kind}_master_a4_rgb.pdf")

        # 前付・奥付が本文へ相乗りできなかったときの 3 分割（フォールバック経路）。
        # 相乗り判定は _sections.pdf の実在が前提なので、存在しない環境ではこちらを通る。
        def matter_paths
          %w[_titlepage_legalpage.pdf _sections.pdf _colophon.pdf].map { File.join(Common::BUILD_PDF_DIR, it) }
        end

        # @param existing [Array<String>] 実在するものとして扱うファイル（表紙など）
        def segment_paths(existing: [])
          available = existing + matter_paths
          Build::Utilities.stub(:page_count, 1) do
            File.stub(:exist?, ->(path) { available.include?(path) }) do
              Build::PdfMerger.send(:cover_enhanced_segments).map(&:path)
            end
          end
        end
      end

      # ================================================================
      # 前付・奥付の本文相乗り（front-back-matter-single-render-spec.md）
      # ================================================================
      class SpecialPageEmbeddingTest < Minitest::Test
        def test_should_append_special_pages_at_the_end_of_the_spine
          # 先頭に足すと本文のページ番号がずれて目次の target-counter が動く。
          # 末尾であることを固定する。
          Dir.mktmpdir do |dir|
            %w[00-preface _toc _titlepage _legalpage _colophon].each do
              File.write(File.join(dir, "#{it}.html"), '<html></html>')
            end

            htmls = Build::PdfBuilder.sections_entry_htmls(dir, [])

            assert_equal %w[_titlepage.html _legalpage.html _colophon.html], htmls.last(3).map { File.basename(it) },
                         '特殊ページはスパインの末尾に、綴じ順どおり並ぶこと'
            assert_equal '00-preface.html', File.basename(htmls.first), '先頭は従来どおり前書きであること'
          end
        end

        def test_should_not_append_special_pages_when_any_is_missing
          # 欠けたまま相乗りさせると結合時のページ範囲を決められない。
          Dir.mktmpdir do |dir|
            %w[00-preface _titlepage _colophon].each do
              File.write(File.join(dir, "#{it}.html"), '<html></html>')
            end

            assert_empty Build::PdfBuilder.special_page_htmls(dir),
                         '3 つ揃っていなければ相乗りさせないこと'
          end
        end

        # 「末尾 3 ページ」と決め打ちせず /Dests から実測するため、
        # 権利ページが 2 ページに溢れても正しく割れる。
        def test_should_split_ranges_from_measured_document_positions
          ranges = ranges_for(first_pages: { '_titlepage' => 511, '_colophon' => 514 }, total: 515)

          assert_equal (1..510),   ranges[:body],     '本扉の手前までが本文'
          assert_equal (511..513), ranges[:front],    '本扉から奥付の手前までが前付（権利ページ 2 ページ）'
          assert_equal (514..515), ranges[:colophon], '奥付から末尾まで'
        end

        def test_should_refuse_to_split_when_positions_are_inconsistent
          # 順序が逆・本文が空・末尾を超える、のいずれも個別レンダへ退避する。
          # 中途半端な範囲で切ると、静かに隣のページを切り出す壊れ方をする。
          assert_nil ranges_for(first_pages: { '_titlepage' => 514, '_colophon' => 511 }, total: 515),
                     '奥付が本扉より前なら相乗りとみなさないこと'
          assert_nil ranges_for(first_pages: { '_titlepage' => 1, '_colophon' => 2 }, total: 515),
                     '本文が空になる位置なら相乗りとみなさないこと'
          assert_nil ranges_for(first_pages: { '_titlepage' => 511 }, total: 515),
                     '奥付が見つからなければ相乗りとみなさないこと'
        end

        # vivliostyle が /Dests へ書き出すのは「リンクの飛び先になっている id」だけで、
        # id を持つだけの要素は出てこない（実測: <body id> は出ず、自己参照リンクは出る）。
        # 前付・奥付はどこからもリンクされないため、目印の自己参照リンクが要る。
        def test_should_inject_a_self_referencing_anchor_into_staged_matter_pages
          Dir.mktmpdir do |dir|
            path = File.join(dir, '_colophon.html')
            File.write(path, '<html><body class="colophon"><h1>奥付</h1></body></html>')

            stub_const_build_pdf_dir(dir) { Build::PdfBuilder.inject_matter_anchors! }

            html = File.read(path)
            assert_includes html, '<a id="vs-matter-colophon" href="#vs-matter-colophon"',
                            '自分自身を指す空リンクが埋まること'
            assert_includes html, 'style="position:absolute"',
                            'grid の行割り当てを崩さないよう流れから外すこと'
            assert_match(/<body[^>]*><a id="vs-matter-colophon"/, html, 'body の直後に置かれること')
          end
        end

        def test_should_not_inject_the_anchor_twice
          Dir.mktmpdir do |dir|
            path = File.join(dir, '_colophon.html')
            File.write(path, '<html><body><h1>奥付</h1></body></html>')

            stub_const_build_pdf_dir(dir) do
              Build::PdfBuilder.inject_matter_anchors!
              Build::PdfBuilder.inject_matter_anchors!
            end

            assert_equal 1, File.read(path).scan('<a id="vs-matter-colophon"').size,
                         '二重ステージングでも目印は 1 つであること'
          end
        end

        private

        # BUILD_PDF_DIR を一時ディレクトリへ差し替える
        def stub_const_build_pdf_dir(dir)
          common = VivlioStarter::CLI::Common
          original = common::BUILD_PDF_DIR
          common.send(:remove_const, :BUILD_PDF_DIR)
          common.const_set(:BUILD_PDF_DIR, dir)
          yield
        ensure
          common.send(:remove_const, :BUILD_PDF_DIR)
          common.const_set(:BUILD_PDF_DIR, original)
        end

        # document_first_pages と page_count を差し替えて範囲計算だけを検証する
        def ranges_for(first_pages:, total:)
          fake = Object.new
          fake.define_singleton_method(:document_first_pages) { first_pages }

          Build::PdfPageMapExtractor.stub(:new, fake) do
            Build::Utilities.stub(:page_count, total) do
              Build::PdfBuilder.compute_special_page_ranges('dummy.pdf')
            end
          end
        end
      end

    end
  end
end
