# frozen_string_literal: true

# ================================================================
# Test: image_path_normalizer_test.rb
# ================================================================
# 検証内容（querystream-data-images-spec.md §3.4 / §4-3）:
#   DataImageResolver が確定させた images/data/… 参照は、
#   asset_prefix 前置・.webp 寄せ・プレースホルダー化のいずれも受けず素通しされる。
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/pre_process/image_path_normalizer'

class ImagePathNormalizerTest < Minitest::Test
  NORMALIZER = VivlioStarter::CLI::PreProcessCommands::ImagePathNormalizer

  def in_tmp
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield } }
  end

  # images/data/… 参照は asset_prefix 前置も .webp 寄せもされず、そのまま保たれる
  def test_should_pass_through_data_build_reference_untouched
    in_tmp do
      # 実体は無くてもよい（resolver がコピー済みという前提。normalizer は存在チェックしない）
      input = '![相対論](images/data/physics_books/relativity.webp)'
      result = NORMALIZER.fix_image_paths(input, '22-ext.md')

      assert_equal input, result
    end
  end

  # .png 拡張子の images/data/… でも .webp へ寄せない（resolver が実在変種で確定済み）
  def test_should_not_coerce_extension_for_data_build_reference
    in_tmp do
      input = '![](images/data/images/badge.png)'
      result = NORMALIZER.fix_image_paths(input, '22-ext.md')

      assert_equal input, result
    end
  end

  # プレースホルダー data URI へ置換されない（存在チェックを走らせない）
  def test_should_not_placeholder_data_build_reference
    in_tmp do
      input = '![](images/data/physics_books/relativity.webp)'
      result = NORMALIZER.fix_image_paths(input, '22-ext.md')

      refute_includes result, 'data:image/svg+xml', 'プレースホルダー化されないべき'
    end
  end
end
