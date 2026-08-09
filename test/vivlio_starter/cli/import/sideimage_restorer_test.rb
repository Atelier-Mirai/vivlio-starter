# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/sideimage_restorer'
require 'vivlio_starter/cli/common'
require 'fileutils'
require 'tmpdir'

module VivlioStarter
  module CLI
    module Import
      class SideimageRestorerTest < Minitest::Test
        # B5 標準の版面幅（182 − ノド 25 − 小口 20）
        B5_TEXT_MM = 137.0

        def setup
          @tmpdir = Dir.mktmpdir('sideimage_restorer_test')
          @original_pwd = Dir.pwd
        end

        def teardown
          Dir.chdir(@original_pwd)
          FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
        end

        # ================================================================
        # parse_directives テスト
        # ================================================================
        def test_parse_directives_reads_image_width_and_side
          re = <<~RE.lines
            = 章

            //sideimage[kauplan][30mm][sep=5mm,side=R]{
            御礼申し上げます。
            //}

            //sideimage[logo_l][40mm][sep=5mm]{
            著者紹介です。
            //}
          RE

          directives = SideimageRestorer.parse_directives(re)

          assert_equal 2, directives.size
          assert_equal({ image: 'kauplan', width_mm: 30.0, klass: 'sideimage-right', blocks: 1 }, directives[0])
          assert_equal({ image: 'logo_l', width_mm: 40.0, klass: 'sideimage', blocks: 1 }, directives[1])
        end

        # Re:VIEW のコメント（#@#）で無効化された行は指示ではない。
        # 拾うと、実在しない画像を探して 🟡 を出すことになる
        def test_parse_directives_skips_commented_out_lines
          re = ['#@# //sideimage[gold_table2][35mm][sep=5mm,side=R]{', '本文', '//}'].map { "#{it}\n" }

          assert_empty SideimageRestorer.parse_directives(re)
        end

        # ================================================================
        # text_block_count テスト
        # ================================================================
        # //blankline は Markdown では空行にしかならない。ブロックとして数えると
        # 画像の脇へ本文を 1 つ多く巻き込む
        def test_text_block_count_ignores_directive_only_blocks
          body = ['一段落め。', '', '//blankline', '', '二段落め。']

          assert_equal 2, SideimageRestorer.text_block_count(body)
        end

        # ================================================================
        # width_percent テスト
        # ================================================================
        # Vivlio では {width=NN%} がそのまま画像列の比率になる（post_process が
        # --sideimage-img-fr へ写す）ので、版面幅に対する割合へ直す
        def test_width_percent_converts_millimetres_against_the_text_area
          assert_equal 22, SideimageRestorer.width_percent(30.0, B5_TEXT_MM)
          assert_equal 36, SideimageRestorer.width_percent(50.0, B5_TEXT_MM)
        end

        def test_width_percent_clamps_extremes
          assert_equal 60, SideimageRestorer.width_percent(200.0, B5_TEXT_MM)
          assert_equal 10, SideimageRestorer.width_percent(1.0, B5_TEXT_MM)
        end

        # ================================================================
        # restore_chapter! テスト
        # ================================================================
        def test_restore_chapter_wraps_image_and_body_in_a_sideimage_block
          re_path = write(@tmpdir, '00-preface.re', <<~RE)
            = まえがき

            //sideimage[kauplan][30mm][sep=5mm,side=R]{
            御礼申し上げます。
            //}

            続きの本文。
          RE
          md_path = write(@tmpdir, '00-preface.md', <<~MD)
            # まえがき

            ![](kauplan.webp)

            御礼申し上げます。

            続きの本文。
          MD

          assert_equal 1, SideimageRestorer.restore_chapter!(md_path, re_path, B5_TEXT_MM)

          assert_equal <<~EXPECTED, File.read(md_path)
            # まえがき

            :::{.sideimage-right}
            ![](kauplan.webp){width=22%}

            御礼申し上げます。
            :::

            続きの本文。
          EXPECTED
        end

        # 原稿にあったぶんだけ巻き込む。Re:VIEW の markdownbuilder は囲みの終わりを
        # 示す印を残さないので、.re のブロック数が唯一の手がかりになる
        def test_restore_chapter_takes_only_as_many_blocks_as_the_source_had
          re_path = write(@tmpdir, '01-intro.re', <<~RE)
            //sideimage[logo][30mm][sep=5mm]{
            一段落め。

            二段落め。
            //}
          RE
          md_path = write(@tmpdir, '01-intro.md', <<~MD)
            ![](logo.webp)

            一段落め。

            二段落め。

            囲みの外の段落。
          MD

          SideimageRestorer.restore_chapter!(md_path, re_path, B5_TEXT_MM)
          written = File.read(md_path)

          assert_includes written, "二段落め。\n:::\n"
          refute_includes written, "囲みの外の段落。\n:::"
        end

        # 同じ章に複数あるときは、.re に現れた順で前から当てる
        def test_restore_chapter_matches_directives_in_order
          re_path = write(@tmpdir, '91-books.re', <<~RE)
            //sideimage[first][30mm][sep=5mm]{
            一冊め。
            //}

            //sideimage[second][35mm][sep=5mm,side=R]{
            二冊め。
            //}
          RE
          md_path = write(@tmpdir, '91-books.md', <<~MD)
            ![](first.webp)

            一冊め。

            ![](second.webp)

            二冊め。
          MD

          assert_equal 2, SideimageRestorer.restore_chapter!(md_path, re_path, B5_TEXT_MM)
          written = File.read(md_path)

          assert_includes written, ":::{.sideimage}\n![](first.webp){width=22%}"
          assert_includes written, ":::{.sideimage-right}\n![](second.webp){width=26%}"
        end

        # 画像が見つからないときは黙って諦めず、章と画像名を挙げて著者に渡す
        def test_restore_chapter_warns_and_skips_when_the_image_is_absent
          re_path = write(@tmpdir, '11-x.re', "//sideimage[missing][30mm][sep=5mm]{\n本文。\n//}\n")
          md_path = write(@tmpdir, '11-x.md', "本文。\n")

          out, = capture_io { assert_equal 0, SideimageRestorer.restore_chapter!(md_path, re_path, B5_TEXT_MM) }

          assert_match(/missing/, out)
          assert_equal "本文。\n", File.read(md_path)
        end

        private

        def write(dir, name, content)
          path = File.join(dir, name)
          File.write(path, content, encoding: 'utf-8')
          path
        end
      end
    end
  end
end
