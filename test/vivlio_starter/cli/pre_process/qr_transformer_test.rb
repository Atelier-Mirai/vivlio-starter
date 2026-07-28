# frozen_string_literal: true

# ================================================================
# Test: qr_transformer_test.rb
# ================================================================
# 検証内容（at-directive-tier1-spec.md §2.5 / §3-3）:
#   - @qr:URL が <img class="vs-qr"> へ置換され、SVG がワークスペースへ生まれる
#   - SVG は intrinsic size（width/height）と viewBox の両方を持つ
#     （どちらか欠けると Vivliostyle/EPUB で寸法が崩れる・拡縮できない）
#   - 同一 URL は全章で 1 ファイルを共有する（内容ハッシュ命名・冪等）
#   - コードフェンス／インラインコード内の @qr: は変換しない
#   - 生成に失敗した URL は記法のまま残し、出現位置つきで警告する（縮退）
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/pre_process/qr_transformer'

class QrTransformerTest < Minitest::Test
  QT = VivlioStarter::CLI::PreProcessCommands::QrTransformer
  QR_DIR = File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, 'images', 'qr')

  def in_tmp
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield } }
  end

  def test_should_replace_qr_directive_with_img_and_generate_svg
    in_tmp do
      out = QT.transform("サンプル: @qr:https://example.com/repo\n", source_filename: '31-usage.md')

      assert_match(%r{<img class="vs-qr" src="images/qr/[0-9a-f]{12}\.svg" alt="https://example\.com/repo">}, out)

      files = Dir.glob(File.join(QR_DIR, '*.svg'))

      assert_equal 1, files.size

      svg = File.read(files.first, encoding: 'utf-8')

      assert_match(/<svg[^>]*\bwidth="\d+"/, svg)
      assert_match(/<svg[^>]*\bheight="\d+"/, svg)
      assert_match(/<svg[^>]*\bviewBox="0 0 \d+ \d+"/, svg)
    end
  end

  # 同一 URL は 2 回書いても 1 ファイル（内容ハッシュ命名なので章を跨いでも共有される）
  def test_should_share_single_file_for_duplicate_urls
    in_tmp do
      QT.transform("@qr:https://example.com/a\n", source_filename: '31-usage.md')
      QT.transform("@qr:https://example.com/a\n@qr:https://example.com/b\n", source_filename: '32-more.md')

      assert_equal 2, Dir.glob(File.join(QR_DIR, '*.svg')).size
    end
  end

  # URL の切れ目は空白か ) の手前（リンク記法の中に置いても壊さない）
  def test_should_stop_url_at_closing_paren
    in_tmp do
      out = QT.transform("(@qr:https://example.com/x) の QR。\n", source_filename: '31-usage.md')

      assert_includes out, 'alt="https://example.com/x">'
      assert_includes out, ') の QR。'
    end
  end

  def test_should_not_convert_inside_code_fence
    in_tmp do
      content = "```markdown\n@qr:https://example.com/repo\n```\n"
      out = QT.transform(content, source_filename: '31-usage.md')

      assert_equal content, out
      assert_empty Dir.glob(File.join(QR_DIR, '*.svg'))
    end
  end

  def test_should_not_convert_inside_inline_code
    in_tmp do
      content = "記法は `@qr:https://example.com/repo` と書きます。\n"
      out = QT.transform(content, source_filename: '31-usage.md')

      assert_equal content, out
    end
  end

  # @qr: を含まない本文は 1 文字も変えない（前置きフィルタの回帰ゲート）
  def test_should_return_content_untouched_without_directive
    in_tmp do
      content = "ふつうの本文。\n\n```ruby\nputs 1\n```\n"

      assert_equal content, QT.transform(content, source_filename: '31-usage.md')
    end
  end
end
