# frozen_string_literal: true

# ================================================================
# Test: image_filename_sanitizer_test.rb
# ================================================================
# テスト対象:
#   ImageFilenameSanitizer（lib/vivlio_starter/cli/image_filename_sanitizer.rb）
#   検出（Guards::ImageFilenameCheck）と取り込み正規化（vs import）の共有基準。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/image_filename_sanitizer'

module VivlioStarter
  module CLI
    class ImageFilenameSanitizerTest < Minitest::Test
      S = ImageFilenameSanitizer

      # 危険文字は削除方式で正規化する（Einstein's → Einsteins）
      def test_should_delete_dangerous_characters
        assert_equal 'Einsteins_later_years', S.sanitize("Einstein's_later_years")
        assert_equal 'sakura1', S.sanitize('sakura(1)')
        assert_equal 'chapter1', S.sanitize('chapter#1')
      end

      # 連続アンダースコアは 1 つに畳む
      def test_should_collapse_consecutive_underscores
        assert_equal 'a_b', S.sanitize('a__b')
      end

      # 許可文字・マルチバイトは変更しない
      def test_should_keep_safe_and_multibyte_names
        assert_equal 'photo_01-final', S.sanitize('photo_01-final')
        assert_equal '図_実験', S.sanitize('図_実験')
      end

      # すべて危険文字なら 'image' へフォールバックする
      def test_should_fallback_to_image_when_empty
        assert_equal 'image', S.sanitize('()')
        assert_equal 'image', S.sanitize('')
      end

      # 危険文字の有無判定と抽出
      def test_should_detect_and_extract_offending_characters
        assert S.unsafe?("Einstein's")
        refute S.unsafe?('safe_name')
        assert_equal ['(', ')'], S.offending_characters('a(b)c')
      end
    end
  end
end
