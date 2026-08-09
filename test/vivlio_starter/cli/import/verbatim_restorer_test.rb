# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/verbatim_restorer'
require 'vivlio_starter/cli/common'
require 'fileutils'
require 'tmpdir'

module VivlioStarter
  module CLI
    module Import
      class VerbatimRestorerTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir('verbatim_restorer_test')
          @original_pwd = Dir.pwd
        end

        def teardown
          Dir.chdir(@original_pwd)
          FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
        end

        # ================================================================
        # directive_names テスト
        # ================================================================
        # markdownbuilder は //list も //output も同じフェンスへ落とすので、
        # 「.re に現れた順」だけが両者を見分ける手がかりになる
        def test_directive_names_lists_verbatim_directives_in_order
          re = ['//list[a][A][c]{', 'int a;', '//}', '//output{', '結果', '//}'].map { "#{it}\n" }

          assert_equal %w[list output], VerbatimRestorer.directive_names(re)
        end

        def test_directive_names_skips_commented_out_and_unrelated_directives
          re = ['#@# //output{', '//sideimage[x][30mm][]{', '//blankline'].map { "#{it}\n" }

          assert_empty VerbatimRestorer.directive_names(re)
        end

        # ================================================================
        # restore_chapter! テスト
        # ================================================================
        # 実行結果に行番号が付かないよう :::{.output} で囲む（22 章の決まり）。
        # ソースコードの //list は素のフェンスのまま残す
        def test_restore_chapter_wraps_only_output_blocks
          re_path = write('11-x.re', <<~RE)
            //list[hello][Hello][c]{
            int a;
            //}

            //output{
            結果です
            //}
          RE
          md_path = write('11-x.md', <<~MD)
            ```c:Hello
            int a;
            ```

            ```text
            結果です
            ```
          MD

          assert_equal 1, VerbatimRestorer.restore_chapter!(md_path, re_path)

          assert_equal <<~EXPECTED, File.read(md_path)
            ```c:Hello
            int a;
            ```

            :::{.output}
            ```text
            結果です
            ```
            :::
          EXPECTED
        end

        # //cmd は端末操作なので .terminal へ
        def test_restore_chapter_wraps_cmd_as_terminal
          re_path = write('12-x.re', "//cmd{\n$ ls\n//}\n")
          md_path = write('12-x.md', "```terminal\n$ ls\n```\n")

          VerbatimRestorer.restore_chapter!(md_path, re_path)

          assert_equal ":::{.terminal}\n```terminal\n$ ls\n```\n:::\n", File.read(md_path)
        end

        # 数が合わない章は当て推量をせず、丸ごと見送って著者に知らせる
        def test_restore_chapter_skips_the_whole_chapter_when_counts_disagree
          re_path = write('13-x.re', "//output{\n結果\n//}\n\n//output{\nもう一つ\n//}\n")
          md_path = write('13-x.md', "```text\n結果\n```\n")
          original = File.read(md_path)

          out, = capture_io { assert_equal 0, VerbatimRestorer.restore_chapter!(md_path, re_path) }

          assert_match(/原稿 2 \/ 変換後 1/, out)
          assert_equal original, File.read(md_path)
        end

        # 逐語系の命令が無い章は触らない
        def test_restore_chapter_leaves_chapters_without_output_untouched
          re_path = write('14-x.re', "//list[a][A][c]{\nint a;\n//}\n")
          md_path = write('14-x.md', "```c:A\nint a;\n```\n")

          assert_equal 0, VerbatimRestorer.restore_chapter!(md_path, re_path)
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
