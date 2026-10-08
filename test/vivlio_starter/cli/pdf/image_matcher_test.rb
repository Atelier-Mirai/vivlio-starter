# frozen_string_literal: true

require "tmpdir"

require "test_helper"
require "vivlio_starter/cli/pdf/image_matcher"

module VivlioStarter
  module PDF
    # 抜き出した図と元の画像の突き合わせ（pdf-read-ocr-improvement-notes.md §4.18）
    class ImageMatcherTest < Minitest::Test
      # 印刷とスキャンで明るさ・コントラスト・大きさが変わっても一致する。図の一部を欠いた切り出し
      # （縦横比が違う）と、どの元の画像とも似ていない図は採らない
      def test_should_match_scanned_figure_but_not_partial_or_unrelated_one
        skip 'ImageMagick が無い' unless system('which magick >/dev/null 2>&1')

        Dir.mktmpdir do |dir|
          originals = File.join(dir, 'originals')
          Dir.mkdir(originals)
          half = File.join(originals, 'half.png')
          system('magick', '-size', '300x150', 'xc:white', '-fill', 'black', '-draw', 'rectangle 0,0 150,150', half)
          system('magick', '-size', '300x150', 'xc:white', '-fill', 'black', '-draw', 'circle 150,75 150,20', File.join(originals, 'circle.png'))
          scanned, partial, unrelated = %w[scanned.png partial.png unrelated.png].map { File.join(dir, it) }
          system('magick', half, '-resize', '50%', '+level', '15%,85%', '-blur', '0x1', scanned)
          system('magick', half, '-crop', '300x75+0+0', partial)
          system('magick', '-size', '300x150', 'gradient:white-black', unrelated)

          matcher = ImageMatcher.new(originals)

          assert_equal(%w[circle.png half.png], matcher.names)
          assert_equal(['half.png', half], matcher.match(scanned))
          assert_nil(matcher.match(partial))
          assert_nil(matcher.match(unrelated))
        end
      end
    end
  end
end
