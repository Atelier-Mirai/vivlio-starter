# frozen_string_literal: true

# ================================================================
# test/vivlio_starter/cli/pdf/print_pdf_compress_guard_test.rb
# ================================================================
# 入稿用 PDF を `vs pdf:compress` にかけようとしたら引き止める
# （`print-pdf-compress-guard-spec.md` §6）。
#
# 判定は 2 つの手掛かりの OR で、どちらか一方では取りこぼす:
#   - ファイル名 … 著者がリネームすると外れる
#   - ページボックス … crop_marks: false の本では MediaBox = TrimBox で効かない
#
# 検証すること:
#   1. 入稿用と判定できること（`_v` 付き / 無し / 過去バージョン）
#   2. 閲覧用を誤検知しないこと
#   3. リネームされていてもボックスで拾えること
#   4. 塗り足しの無い PDF をボックスで拾わないこと
#   5. 引数なしの呼び出しでは判定しないこと（入稿用を選びようがない）
#
# PDF は Prawn で作る（本体リポジトリのテストは AGPL の HexaPDF に依存しない）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'prawn'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pdf'

module VivlioStarter
  module CLI
    class PrintPdfCompressGuardTest < Minitest::Test
      Compressor = PdfCommands::PdfCompressor
      PROJECT = 'vivlio_starter'

      # --- ファイル名で拾う（§3.1） ---

      # include_version: true の既定形
      def test_should_detect_print_pdf_with_version
        assert Compressor.print_pdf_filename?("#{PROJECT}_print_v1.0.0.pdf", PROJECT)
      end

      # include_version: false では _v が付かない。厳密一致では取りこぼす形
      def test_should_detect_print_pdf_without_version
        assert Compressor.print_pdf_filename?("#{PROJECT}_print.pdf", PROJECT)
      end

      # 過去のバージョンでビルドした残り。現在の project.version と一致しなくても入稿用は入稿用
      def test_should_detect_print_pdf_from_older_version
        assert Compressor.print_pdf_filename?("#{PROJECT}_print_v0.9.0.pdf", PROJECT)
      end

      # 閲覧用を誤検知しない（狼少年にならないことが判定を緩めない理由・§3.3）
      def test_should_not_detect_viewing_pdf
        refute Compressor.print_pdf_filename?("#{PROJECT}_v1.0.0.pdf", PROJECT)
        refute Compressor.print_pdf_filename?("#{PROJECT}.pdf", PROJECT)
      end

      # 設定が無い（直接ビルド等）ときは名前で判定しない
      def test_should_not_detect_without_project_name
        refute Compressor.print_pdf_filename?("#{PROJECT}_print_v1.0.0.pdf", nil)
        refute Compressor.print_pdf_filename?("#{PROJECT}_print_v1.0.0.pdf", '')
      end

      # --- ページボックスで拾う（§3.2） ---

      # 塗り足しがあると MediaBox ≠ TrimBox になる
      def test_should_detect_bleed_box
        in_tmpdir do
          make_pdf('bleed.pdf', trim_box: [9, 9, 603, 783])

          assert Compressor.bleed_box?('bleed.pdf')
        end
      end

      # crop_marks: false の本は MediaBox = TrimBox のままなので、この手掛かりは効かない
      def test_should_not_detect_bleed_box_without_trim
        in_tmpdir do
          make_pdf('plain.pdf')

          refute Compressor.bleed_box?('plain.pdf')
        end
      end

      # PDF でないものを渡しても落ちない
      def test_should_survive_broken_pdf
        in_tmpdir do
          File.write('broken.pdf', 'not a pdf')

          refute Compressor.bleed_box?('broken.pdf')
        end
      end

      # --- 2 つの手掛かりの合わせ技（§3） ---

      # 著者がリネームしていてもボックスで拾える
      def test_should_detect_renamed_print_pdf_by_box
        in_tmpdir do
          make_pdf('入稿データ最終版.pdf', trim_box: [9, 9, 603, 783])

          assert Compressor.print_pdf_input?('入稿データ最終版.pdf', PROJECT)
        end
      end

      # crop_marks: false ＋ 既定の名前ならファイル名で拾える
      def test_should_detect_print_pdf_without_crop_marks_by_name
        in_tmpdir do
          make_pdf("#{PROJECT}_print_v1.0.0.pdf")

          assert Compressor.print_pdf_input?("#{PROJECT}_print_v1.0.0.pdf", PROJECT)
        end
      end

      # 閲覧用は両方の手掛かりが外れる
      def test_should_not_detect_viewing_pdf_by_either_clue
        in_tmpdir do
          make_pdf("#{PROJECT}_v1.0.0.pdf")

          refute Compressor.print_pdf_input?("#{PROJECT}_v1.0.0.pdf", PROJECT)
        end
      end

      # --- 引数なしの呼び出しは判定しない（§2） ---

      # book.yml から閲覧用を解決するので、入稿用を選びようがない
      def test_should_skip_guard_without_explicit_input
        compressor = Compressor.new({}, nil, nil)

        assert compressor.send(:confirm_print_pdf_compression),
               '引数なしの呼び出しで引き止めている'
      end

      private

      def in_tmpdir(&) = Dir.mktmpdir('vs-print-guard-') { Dir.chdir(it, &) }

      def make_pdf(path, trim_box: nil)
        Prawn::Document.generate(path, page_size: [612, 792]) do |pdf|
          pdf.text 'guard test'
          pdf.state.page.dictionary.data[:TrimBox] = trim_box if trim_box
        end
      end
    end
  end
end
