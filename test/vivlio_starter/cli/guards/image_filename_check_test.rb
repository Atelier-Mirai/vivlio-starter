# frozen_string_literal: true

# ================================================================
# Test: guards/image_filename_check_test.rb
# ================================================================
# テスト対象:
#   Guards::ImageFilenameCheck（lib/vivlio_starter/cli/guards/image_filename_check.rb）
#
# 検証内容（docs/specs/epub-kindle-webp-transcode-spec.md §4・§6-1）:
#   - 危険文字（' ( ) & 等）を含む画像名を検出し、警告のみ（非ブロッキング）で報告する
#   - 許可文字・マルチバイト（日本語）は検出しない
#   - 改名案（危険文字→_・連続_畳み）を detail に含む
#   - images/ は contents/*.md の出現行番号、covers/・stylesheets/images/ は固定文言
#   - 3 ディレクトリすべてを走査する
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class ImageFilenameCheckTest < Minitest::Test
      # 危険文字を含む本文画像を検出し、警告（非ブロッキング）として報告する
      def test_should_warn_dangerous_characters_in_content_image
        with_temp_project do
          FileUtils.mkdir_p('images/94-sample')
          File.write("images/94-sample/Einstein's_later_years.webp", 'x')

          violations = Guards::ImageFilenameCheck.new.validate

          assert_equal 1, violations.size
          violation = violations.first
          assert_predicate violation, :warn?
          assert_includes violation.message, "Einstein's_later_years.webp"
          assert_includes violation.message, "'"
        end
      end

      # 改名案（危険文字→_）と本文の出現行番号を detail に含む
      def test_should_include_rename_suggestion_and_md_occurrence
        with_temp_project do
          FileUtils.mkdir_p('images/94-sample')
          FileUtils.mkdir_p('contents')
          File.write("images/94-sample/Einstein's_later_years.webp", 'x')
          File.write('contents/94-sample.md', <<~MD)
            # サンプル
            ![アインシュタイン](images/94-sample/Einstein's_later_years.webp)
            本文
            ![再掲](images/94-sample/Einstein's_later_years.webp)
          MD

          detail = Guards::ImageFilenameCheck.new.validate.first.detail

          assert detail.any? { it.include?('Einsteins_later_years.webp') },
                 '改名案（危険文字を除去したファイル名）を含むべき'
          assert detail.any? { it.include?('contents/94-sample.md') && it.include?('2 行目') && it.include?('4 行目') },
                 '出現箇所として .md ファイルと行番号を含むべき'
        end
      end

      # 許可文字・日本語ファイル名は検出しない
      def test_should_not_warn_safe_or_multibyte_filenames
        with_temp_project do
          FileUtils.mkdir_p('images/10-intro')
          File.write('images/10-intro/photo_01.webp', 'x')
          File.write('images/10-intro/図_実験.png', 'x')

          assert_empty Guards::ImageFilenameCheck.new.validate
        end
      end

      # covers/・stylesheets/images/ も走査し、用途に応じた固定文言を案内する
      def test_should_scan_covers_and_stylesheets_with_usage_hint
        with_temp_project do
          FileUtils.mkdir_p('covers')
          FileUtils.mkdir_p('stylesheets/images')
          File.write("covers/Einstein's_portrait.webp", 'x')
          File.write('stylesheets/images/sakura(1).webp', 'x')

          violations = Guards::ImageFilenameCheck.new.validate

          assert_equal 2, violations.size
          cover = violations.find { it.message.include?('covers/') }
          theme = violations.find { it.message.include?('stylesheets/images/') }
          assert cover.detail.any? { it.include?('表紙・裏表紙として配置されています') }
          assert theme.detail.any? { it.include?('扉絵・節絵として配置されています') }
        end
      end

      # 全違反が警告（:error なし）＝ Guard.run! でビルドを止めない
      def test_should_be_warn_only_non_blocking
        with_temp_project do
          FileUtils.mkdir_p('images')
          File.write('images/bad(name).webp', 'x')

          violations = Guards::ImageFilenameCheck.new.validate

          assert violations.all?(&:warn?), '不正ファイル名検出はすべて警告であるべき（非ブロッキング）'
          refute violations.any?(&:error?)
        end
      end

      private

      # config/book.yml を持つ一時プロジェクトに chdir して実行する
      def with_temp_project
        Dir.mktmpdir('vs-image-filename') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            File.write('config/book.yml', "book:\n  main_title: 'test'\n")
            yield
          end
        end
      end
    end
  end
end
