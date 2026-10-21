# frozen_string_literal: true

# ================================================================
# Test: build/chapter_config_test.rb
# ================================================================
# テスト対象:
#   Build::ChapterConfig.htmls_for_kind
#   中間 HTML の置き場から、前書き・本文・付録・後書きのどれかを選ぶ。
#   PDF・EPUB・目次の組み立てがみなここを通るので、ここで落ちた章は本から黙って抜ける。
#
# 検証の軸:
#   - 番号だけの原稿（contents/12.md → 12.html）も章として拾う
#   - 種類は catalog.yml の区分で決まる（PREFACE に書いた 20 番台は前書き）
#   - 特殊ページ（_toc など）は拾わない
#   - 組む章を渡したら、その章だけにする
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'fileutils'

require 'vivlio_starter/cli/loader'

class ChapterConfigTest < Minitest::Test
  Common = VivlioStarter::CLI::Common
  ChapterConfig = VivlioStarter::CLI::Build::ChapterConfig

  # catalog.yml と原稿、中間 HTML を置いた一時プロジェクトで yield する（HTML の置き場を渡す）。
  def within_project(catalog:, chapters:)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(['config', Common::CONTENTS_DIR, 'html'])
        File.write('config/catalog.yml', catalog)
        chapters.each do
          File.write(File.join(Common::CONTENTS_DIR, "#{it}.md"), "# #{it}\n")
          File.write(File.join('html', "#{it}.html"), '<html></html>')
        end
        File.write('html/_toc.html', '<html></html>')
        yield 'html'
      end
    end
  end

  def basenames(paths) = paths.map { File.basename(it, '.html') }

  def test_should_collect_number_only_chapter_with_named_chapters
    catalog = "PREFACE:\n  - 00-preface\nCHAPTERS:\n  - 11-first\n  - 12\n  - 13-third\n"
    within_project(catalog:, chapters: %w[00-preface 11-first 12 13-third]) do |html_dir|
      assert_equal %w[11-first 12 13-third], basenames(ChapterConfig.htmls_for_kind(html_dir, :chapter))
      assert_equal %w[00-preface], basenames(ChapterConfig.htmls_for_kind(html_dir, :preface))
    end
  end

  def test_should_decide_kind_by_catalog_section_rather_than_number
    catalog = "PREFACE:\n  - 00-preface\n  - 20-vol2-intro\nCHAPTERS:\n  - 21-next\n"
    within_project(catalog:, chapters: %w[00-preface 20-vol2-intro 21-next]) do |html_dir|
      assert_equal %w[00-preface 20-vol2-intro], basenames(ChapterConfig.htmls_for_kind(html_dir, :preface))
      assert_equal %w[21-next], basenames(ChapterConfig.htmls_for_kind(html_dir, :chapter))
    end
  end

  def test_should_keep_only_given_chapters_including_number_only_one
    catalog = "CHAPTERS:\n  - 11-first\n  - 12\n  - 13-third\n"
    within_project(catalog:, chapters: %w[11-first 12 13-third]) do |html_dir|
      assert_equal %w[12], basenames(ChapterConfig.htmls_for_kind(html_dir, :chapter, %w[12]))
    end
  end
end
