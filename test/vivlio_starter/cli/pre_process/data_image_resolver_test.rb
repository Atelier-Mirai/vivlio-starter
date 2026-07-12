# frozen_string_literal: true

# ================================================================
# Test: data_image_resolver_test.rb
# ================================================================
# 検証内容（querystream-data-images-spec.md §4）:
#   - 探索順: 章ローカル最優先 / data/<名>/ が data/images/ に優先
#   - 書き換え形: images/data/<相対>（無 prefix・実在変種の拡張子）
#   - コピー先: BUILD_HTML_DIR/images/data/… に実体が生まれ、2 回目は再コピーしない
#   - 変種解決: cover: foo.png でも data/…/foo.webp があれば .webp を採る。.svg は完全一致
#   - 対象外素通し: URL・data:・"/" 含み・images/ 始まり
#   - ミス時: 🟡 警告に探索 3 パスが含まれ、テキストは不変
#   - HTML <img src> の書き換え
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/pre_process/data_image_resolver'

class DataImageResolverTest < Minitest::Test
  DIR = VivlioStarter::CLI::PreProcessCommands::DataImageResolver
  BUILD_DATA_DIR = File.join(VivlioStarter::CLI::Common::BUILD_HTML_DIR, 'images', 'data')

  # データ画像解決の post_render コンテキスト（data_file から basename を採る）。
  def ctx(data_file: 'data/physics_books.yml', query: '= physics_books', location: '22-ext.md:10')
    { data_file:, query:, location: }
  end

  def in_tmp
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield }
    end
  end

  # data/<データ名>/ にある画像を images/data/… へ書き換え、実体をワークスペースへコピーする
  def test_should_rewrite_and_stage_data_folder_image
    in_tmp do
      FileUtils.mkdir_p('data/physics_books')
      File.write('data/physics_books/relativity.webp', 'WEBP')

      result = DIR.rewrite('![相対論](relativity.webp){width=40%}', ctx, chapter_slug: '22-ext')

      assert_equal '![相対論](images/data/physics_books/relativity.webp){width=40%}', result
      assert File.exist?(File.join(BUILD_DATA_DIR, 'physics_books/relativity.webp')),
             'ワークスペースへ実体がコピーされるべき'
    end
  end

  # 章ローカルに画像があれば書き換えず従来経路（normalizer）に委ねる
  def test_should_not_rewrite_when_chapter_local_exists
    in_tmp do
      FileUtils.mkdir_p('images/22-ext')
      File.write('images/22-ext/relativity.webp', 'WEBP')
      FileUtils.mkdir_p('data/physics_books')
      File.write('data/physics_books/relativity.webp', 'WEBP')

      result = DIR.rewrite('![](relativity.webp)', ctx, chapter_slug: '22-ext')

      assert_equal '![](relativity.webp)', result, '章ローカル優先で書き換えないべき'
      refute File.exist?(File.join(BUILD_DATA_DIR, 'physics_books/relativity.webp'))
    end
  end

  # data/<名>/ が data/images/ に優先する
  def test_should_prefer_data_folder_over_shared_pool
    in_tmp do
      FileUtils.mkdir_p('data/physics_books')
      File.write('data/physics_books/note.webp', 'FOLDER')
      FileUtils.mkdir_p('data/images')
      File.write('data/images/note.webp', 'POOL')

      result = DIR.rewrite('![](note.webp)', ctx, chapter_slug: '22-ext')

      assert_equal '![](images/data/physics_books/note.webp)', result
      assert_equal 'FOLDER', File.read(File.join(BUILD_DATA_DIR, 'physics_books/note.webp'))
    end
  end

  # 共有プール data/images/ から解決できる
  def test_should_resolve_from_shared_pool
    in_tmp do
      FileUtils.mkdir_p('data/images')
      File.write('data/images/badge.webp', 'WEBP')

      result = DIR.rewrite('![](badge.webp)', ctx, chapter_slug: '22-ext')

      assert_equal '![](images/data/images/badge.webp)', result
    end
  end

  # cover: foo.png でも data/…/foo.webp があれば .webp を採る（変種優先解決）
  def test_should_prefer_webp_variant
    in_tmp do
      FileUtils.mkdir_p('data/physics_books')
      File.write('data/physics_books/relativity.webp', 'WEBP')

      result = DIR.rewrite('![](relativity.png)', ctx, chapter_slug: '22-ext')

      assert_equal '![](images/data/physics_books/relativity.webp)', result
    end
  end

  # .svg は完全一致のみ（.webp へ寄せない）
  def test_should_resolve_svg_by_exact_match
    in_tmp do
      FileUtils.mkdir_p('data/physics_books')
      File.write('data/physics_books/diagram.svg', '<svg/>')

      result = DIR.rewrite('![](diagram.svg)', ctx, chapter_slug: '22-ext')

      assert_equal '![](images/data/physics_books/diagram.svg)', result
      assert File.exist?(File.join(BUILD_DATA_DIR, 'physics_books/diagram.svg'))
    end
  end

  # 2 回目の呼び出しでは再コピーしない（mtime を保持）
  def test_should_not_recopy_on_second_call
    in_tmp do
      FileUtils.mkdir_p('data/physics_books')
      File.write('data/physics_books/relativity.webp', 'WEBP')

      DIR.rewrite('![](relativity.webp)', ctx, chapter_slug: '22-ext')
      dest = File.join(BUILD_DATA_DIR, 'physics_books/relativity.webp')
      first_mtime = File.mtime(dest)

      DIR.rewrite('![](relativity.webp)', ctx, chapter_slug: '22-ext')

      assert_equal first_mtime, File.mtime(dest), '2 回目は再コピーしないべき'
    end
  end

  # 対象外（URL・data:・"/" 含み・images/ 始まり）は素通しする
  def test_should_pass_through_non_plain_filenames
    in_tmp do
      %w[
        https://example.com/a.webp
        data:image/svg+xml;charset=utf-8,%3Csvg%3E
        sub/dir/a.webp
        images/22-ext/a.webp
        images/data/physics_books/a.webp
      ].each do |src|
        input = "![](#{src})"
        assert_equal input, DIR.rewrite(input, ctx, chapter_slug: '22-ext'),
                     "#{src} は素通しされるべき"
      end
    end
  end

  # HTML <img src> も書き換える
  def test_should_rewrite_html_img_src
    in_tmp do
      FileUtils.mkdir_p('data/physics_books')
      File.write('data/physics_books/relativity.webp', 'WEBP')

      result = DIR.rewrite('<img src="relativity.webp" alt="x">', ctx, chapter_slug: '22-ext')

      assert_includes result, 'src="images/data/physics_books/relativity.webp"'
    end
  end

  # ミス時は素通し＋探索 3 パスを列挙した警告を出す
  def test_should_warn_with_three_search_paths_on_miss
    in_tmp do
      warnings = capture_warnings do
        result = DIR.rewrite('![](missing.webp)', ctx, chapter_slug: '22-ext')
        assert_equal '![](missing.webp)', result, 'ミス時はテキスト不変'
      end

      joined = warnings.join("\n")
      assert_includes joined, 'images/22-ext/missing.webp'
      assert_includes joined, 'data/physics_books/missing.webp'
      assert_includes joined, 'data/images/missing.webp'
    end
  end

  private

  # Common.log_warn の出力を捕捉する（puts＝$stdout 経由・detail 込み）。
  def capture_warnings
    original = $stdout
    io = StringIO.new
    $stdout = io
    yield
    io.string.lines
  ensure
    $stdout = original
  end
end
