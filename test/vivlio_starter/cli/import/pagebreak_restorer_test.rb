# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/pagebreak_restorer'
require 'vivlio_starter/cli/common'
require 'fileutils'
require 'tmpdir'

module VivlioStarter
  module CLI
    module Import
      class PagebreakRestorerTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir('pagebreak_restorer_test')
          @original_pwd = Dir.pwd
        end

        def teardown
          Dir.chdir(@original_pwd)
          FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
        end

        # ================================================================
        # clearpage_anchors テスト
        # ================================================================
        # //clearpage 自身に中身が無いので、直後にくる素のテキストを目印にする
        def test_clearpage_anchors_takes_the_next_plain_text
          re = ['本文。', '//clearpage', '', '//blankline', '=== 次の節', '続き。'].map { "#{it}\n" }

          assert_equal ['次の節'], PagebreakRestorer.clearpage_anchors(re)
        end

        # Re:VIEW のインライン記法は表示テキストだけ残す（`@<href>{url, 表示}`）
        def test_plain_text_unwraps_review_inline_markup
          assert_equal 'アトリヱ未來', PagebreakRestorer.plain_text('@<href>{https://example.com, アトリヱ未來}')
          assert_equal '盤上の夢 百万石', PagebreakRestorer.plain_text('====[column] 盤上の夢 百万石')
          assert_equal '', PagebreakRestorer.plain_text('//blankline')
          assert_equal '', PagebreakRestorer.plain_text('#@# コメント')
        end

        # ================================================================
        # restore_chapter! テスト
        # ================================================================
        def test_restore_chapter_inserts_pagebreak_before_the_anchor
          re_path = write('00-preface.re', "本文。\n//clearpage\n\n=== 次の節\n続き。\n")
          md_path = write('00-preface.md', "本文。\n\n### 次の節\n\n続き。\n")

          assert_equal 1, PagebreakRestorer.restore_chapter!(md_path, re_path)

          assert_equal <<~EXPECTED, File.read(md_path)
            本文。

            @pagebreak

            ### 次の節

            続き。
          EXPECTED
        end

        # 目印が囲みの中にあるときは囲みの外へ出す。中に入れると改ページが
        # 囲みの内側で起き、枠が 2 ページに割れる
        def test_restore_chapter_hoists_the_pagebreak_out_of_a_container
          re_path = write('01-x.re', "本文。\n//clearpage\n\n====[column] 盤上の夢\n中身。\n====[/column]\n")
          md_path = write('01-x.md', "本文。\n\n:::{.column}\n**盤上の夢**\n中身。\n:::\n")

          PagebreakRestorer.restore_chapter!(md_path, re_path)

          assert_equal <<~EXPECTED, File.read(md_path)
            本文。

            @pagebreak

            :::{.column}
            **盤上の夢**
            中身。
            :::
          EXPECTED
        end

        # 目印が見つからない章は黙って諦めず、目印を挙げて著者に渡す
        def test_restore_chapter_warns_when_the_anchor_is_absent
          re_path = write('02-x.re', "//clearpage\n\n=== どこにも無い見出し\n")
          md_path = write('02-x.md', "別の本文。\n")

          out, = capture_io { assert_equal 0, PagebreakRestorer.restore_chapter!(md_path, re_path) }

          assert_match(/どこにも無い見出し/, out)
          assert_equal "別の本文。\n", File.read(md_path)
        end

        def test_restore_chapter_leaves_chapters_without_clearpage_untouched
          re_path = write('03-x.re', "=== 節\n本文。\n")
          md_path = write('03-x.md', "### 節\n\n本文。\n")

          assert_equal 0, PagebreakRestorer.restore_chapter!(md_path, re_path)
        end

        private

        def write(name, content)
          path = File.join(@tmpdir, name)
          File.write(path, content, encoding: 'utf-8')
          path
        end
      end
    end
  end
end
