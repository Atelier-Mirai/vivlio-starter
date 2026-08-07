# frozen_string_literal: true

# ================================================================
# Test: direct_build_test.rb
# ================================================================
# 検証内容（direct-build-spec.md §3）:
#   - CONFIG 組み立て: 既定値の全セクション・版面プリセット・--theme の反映
#   - 章 basename の導出: 番号なし / 01–89 保持 / 00・90–99 の付け替え
#   - タイトル抽出: 先頭 h1 / コードフェンス内の # を拾わない / 無ければファイル名
#   - ワークスペース組み立て: 最小プロジェクトの構成と参照画像の同伴（実在/不在）
#   - --theme の検証: 未知の色は 🔴 で中断し、CONFIG を書き換えない
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/startup'

module VivlioStarter
  module CLI
    module BuildCommands
      class DirectBuildTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir('direct-build-test-')
        end

        def teardown
          FileUtils.remove_entry(@tmpdir)
        end

        # ------------------------------------------------------------
        # CONFIG 組み立て（Common.build_direct_configuration）
        # ------------------------------------------------------------

        def test_should_build_configuration_without_reading_book_yml
          config = Common.build_direct_configuration(
            book: { main_title: 'テスト原稿' },
            theme: { style: 'simple', color: 'blue' },
            output: { targets: ['pdf'] }
          )

          assert_equal 'テスト原稿', config.book.main_title
          assert_equal 'simple', config.theme.style
          assert_equal 'blue', config.theme.color
          assert_equal ['pdf'], config.output.targets
          # 既定値スキーマの全セクションが存在し、ドット記法が安全であること
          assert_equal 'contents', config.directories.contents
          assert_equal '.cache/vs', config.cache.dir
          assert_nil config.lint.disabled_rules
          assert config.frozen?, 'CONFIG は frozen であるべきです'
        end

        def test_should_fill_page_settings_from_preset
          page = Common.build_direct_configuration.page

          assert_equal Common::DIRECT_PAGE_PRESET, page.use
          assert_equal 'JIS-B5', page.size
          assert_equal '10.5pt', page.base_font_size
          # 行送りは倍率ではなく絶対 pt へ解決済み（page-unit-conversion-spec §3.3）
          assert_equal '17.85pt', page.base_line_height
        end

        def test_should_install_and_restore_configuration
          original = Common::CONFIG
          replacement = Common.build_direct_configuration(book: { main_title: '差し替え' })

          Common.install_configuration!(replacement)
          assert_equal '差し替え', Common::CONFIG.book.main_title

          Common.install_configuration!(original)
          assert_same original, Common::CONFIG
        end

        # ------------------------------------------------------------
        # 章 basename とタイトルの導出
        # ------------------------------------------------------------

        def test_should_derive_chapter_basename_from_filename
          assert_equal '10-myawesome', direct_build_for('myawesome.md').basename,
                       '番号なしは 10 を割り当てるはずです'
          assert_equal '05-note', direct_build_for('05-note.md').basename,
                       '01–89 の番号は保持するはずです'
          assert_equal '10-preface', direct_build_for('00-preface.md').basename,
                       '00 は本章扱いへ付け替えるはずです'
          assert_equal '10-afterword', direct_build_for('99-afterword.md').basename,
                       '99 は本章扱いへ付け替えるはずです'
          assert_equal '10-document', direct_build_for('企画メモ.md').basename,
                       'ASCII に落とせない名前は既定 slug へ寄せるはずです'
        end

        def test_should_extract_title_from_first_heading
          build = direct_build_for('idea.md', <<~MD)
            前書き相当の一文。

            # 本当の見出し

            ```ruby
            # コードのコメント
            ```
          MD

          assert_equal '本当の見出し', build.title
        end

        def test_should_fall_back_to_filename_when_heading_is_absent
          build = direct_build_for('idea.md', "見出しのない本文だけの原稿。\n")

          assert_equal 'idea', build.title
        end

        # ------------------------------------------------------------
        # ワークスペースの組み立て
        # ------------------------------------------------------------

        def test_should_assemble_minimal_project_workspace
          build = direct_build_for('myawesome.md', "# 見出し\n\n本文。\n")
          workspace = File.join(@tmpdir, 'ws')
          FileUtils.mkdir_p(workspace)

          build.send(:prepare_workspace!, workspace)

          assert_path_exists File.join(workspace, 'contents/10-myawesome.md')
          assert_path_exists File.join(workspace, 'config/page_presets.yml')
          assert_path_exists File.join(workspace, 'package.json')
          assert Dir.exist?(File.join(workspace, 'stylesheets')), 'stylesheets が参照できるはずです'
          assert_path_exists File.join(workspace, 'stylesheets/chapter.css')
          assert_equal "CHAPTERS:\n  - 10-myawesome\n", File.read(File.join(workspace, 'config/catalog.yml'))
          refute_path_exists File.join(workspace, 'config/book.yml'), 'book.yml は置かないはずです'
        end

        # stylesheets は参照（symlink）で持ち込むが、ビルドが唯一書き込む
        # fonts/google-fonts.css だけは実体コピーにして、著者のプロジェクトや
        # gem 同梱 scaffold を書き換えさせない
        def test_should_shield_the_generated_font_bundle_from_the_symlink_target
          build = direct_build_for('myawesome.md')
          workspace = File.join(@tmpdir, 'ws')
          FileUtils.mkdir_p(workspace)

          build.send(:prepare_workspace!, workspace)

          source = build.send(:stylesheets_source)
          bundle = File.join(workspace, 'stylesheets/fonts/google-fonts.css')
          skip '実体側に google-fonts.css が無い環境' unless File.file?(File.join(source, 'fonts/google-fonts.css'))

          refute File.symlink?(File.join(workspace, 'stylesheets')), 'stylesheets 直下は実体ディレクトリのはずです'
          assert File.symlink?(File.join(workspace, 'stylesheets/chapter.css')), 'CSS は参照で持ち込むはずです'
          refute File.symlink?(bundle), 'google-fonts.css は実体コピーのはずです'

          before = File.read(File.join(source, 'fonts/google-fonts.css'), encoding: 'utf-8')
          File.write(bundle, "/* rewritten by build */\n", encoding: 'utf-8')

          assert_equal before, File.read(File.join(source, 'fonts/google-fonts.css'), encoding: 'utf-8'),
                       'ワークスペースへの書き込みが symlink 先へ波及しないはずです'
        end

        def test_should_copy_referenced_images_preserving_relative_layout
          FileUtils.mkdir_p(File.join(@tmpdir, 'assets'))
          File.write(File.join(@tmpdir, 'assets/figure.svg'), '<svg xmlns="http://www.w3.org/2000/svg"/>')
          build = direct_build_for('myawesome.md', <<~MD)
            # 見出し

            ![ある図](assets/figure.svg)
            ![ない図](assets/missing.svg)
            ![外部](https://example.com/x.png)
          MD

          workspace = File.join(@tmpdir, 'ws')
          FileUtils.mkdir_p(workspace)
          build.send(:prepare_workspace!, workspace)

          # ImagePathNormalizer は images/<章>/<参照文字列> へ正規化するため、
          # 参照の相対構造ごと持ち込まれている必要がある
          assert_path_exists File.join(workspace, 'images/10-myawesome/assets/figure.svg')
          refute_path_exists File.join(workspace, 'images/10-myawesome/assets/missing.svg')
          refute_path_exists File.join(workspace, 'images/10-myawesome/x.png')
        end

        # プロジェクトの章を直接指定したとき、章の図版は contents/ ではなく
        # images/<章>/ にある。推敲プレビュー用途で図版が全滅しないよう探索する。
        def test_should_copy_chapter_images_when_building_a_project_chapter
          FileUtils.mkdir_p(File.join(@tmpdir, 'contents'))
          FileUtils.mkdir_p(File.join(@tmpdir, 'images/00-preface'))
          File.write(File.join(@tmpdir, 'images/00-preface/logo.svg'), '<svg xmlns="http://www.w3.org/2000/svg"/>')
          File.write(File.join(@tmpdir, 'contents/00-preface.md'), "# まえがき\n\n![ロゴ](logo.svg)\n")
          build = DirectBuild.new(File.join(@tmpdir, 'contents/00-preface.md'))

          workspace = File.join(@tmpdir, 'ws')
          FileUtils.mkdir_p(workspace)
          build.send(:prepare_workspace!, workspace)

          assert_path_exists File.join(workspace, 'images/10-preface/logo.svg')
        end

        # ------------------------------------------------------------
        # --theme の検証
        # ------------------------------------------------------------

        def test_should_reject_unknown_theme_color_without_touching_configuration
          build = direct_build_for('myawesome.md', "# 見出し\n", theme: 'bluu')
          original = Common::CONFIG

          status = capture_io { assert_equal 1, build.call }

          assert_match(/無効な色名/, status.join)
          assert_same original, Common::CONFIG, 'エラー時に CONFIG を差し替えないはずです'
        end

        def test_should_accept_hex_theme_color
          build = direct_build_for('myawesome.md', "# 見出し\n", theme: '#e91e63')

          assert build.send(:valid_theme?), 'HEX 記法は受理するはずです'
          assert_equal '#e91e63', build.send(:direct_configuration).theme.color
        end

        private

        def direct_build_for(filename, content = "# 見出し\n", theme: nil)
          path = File.join(@tmpdir, filename)
          File.write(path, content, encoding: 'utf-8')
          DirectBuild.new(path, theme: theme)
        end
      end
    end
  end
end
