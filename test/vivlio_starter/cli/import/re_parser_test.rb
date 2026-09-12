# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/re_parser'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module Import
      # .re の文法（re-direct-import-spec.md §2）
      class ReParserTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir('re_parser_test')
          @report = ReReport.new
        end

        def teardown
          FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
        end

        def parse(source, name: 'chap.re')
          path = File.join(@tmpdir, name)
          File.write(path, source, encoding: 'utf-8')
          ReParser.parse(path, report: @report)
        end

        # ================================================================
        # 見出し
        # ================================================================
        def test_should_read_heading_level_label_and_tag
          nodes = parse("= 章\n\n=={sec-a} 節\n\n===[column] コラム\n===[/column]\n")

          assert_equal [1, 2, 3, 3], nodes.map(&:level)
          assert_equal 'sec-a', nodes[1].id
          assert_equal 'column', nodes[2].tag
          assert_equal '/column', nodes[3].tag
        end

        # ================================================================
        # リスト（同 §2.2 の落とし穴）
        # ================================================================
        def test_should_read_unordered_list_with_nesting
          nodes = parse(" * 項目1\n * 項目2\n ** 入れ子\n")

          assert_instance_of ReParser::UList, nodes.first
          assert_equal [1, 1, 2], nodes.first.items.map(&:level)
          assert_equal '入れ子', nodes.first.items.last.text
        end

        # Starter では `-` が番号つきリスト。マーカー直後の最初のトークンが番号になる
        def test_should_read_hyphen_as_ordered_list
          nodes = parse(" - 1. 最初\n - (A) 次\n")

          assert_instance_of ReParser::OList, nodes.first
          assert_equal ['1.', '(A)'], nodes.first.items.map(&:marker)
          assert_equal %w[最初 次], nodes.first.items.map(&:text)
        end

        def test_should_attach_continuation_lines_to_item
          nodes = parse(" - 1. 最初\n      折り返した続き\n")

          assert_equal ['折り返した続き'], nodes.first.items.first.continuation
        end

        def test_should_read_definition_list
          nodes = parse(" : 用語\n    説明1。\n    説明2。\n")

          assert_instance_of ReParser::DList, nodes.first
          assert_equal '用語', nodes.first.items.first.term
          assert_equal ['説明1。', '説明2。'], nodes.first.items.first.description
        end

        # ================================================================
        # ブロック命令（同 §2.4）
        # ================================================================
        def test_should_read_block_arguments_and_body
          nodes = parse("//list[id][説明][file=a.c,1]{\nputs 1\n//}\n")

          block = nodes.first
          assert_equal 'list', block.name
          assert_equal ['id', '説明', 'file=a.c,1'], block.args
          assert_equal ['puts 1'], block.body
        end

        # 引数の中の `]` は `\]` でエスケープする（`[` はそのまま書ける）
        def test_should_unescape_bracket_in_argument
          nodes = parse("//footnote[fn1][配列は a[0\\] と書きます]\n")

          assert_equal ['fn1', '配列は a[0] と書きます'], nodes.first.args
        end

        def test_should_read_command_without_body
          nodes = parse("//clearpage\n//vspace[latex][7mm]\n")

          assert_equal %w[clearpage vspace], nodes.map(&:name)
          assert_equal ['latex', '7mm'], nodes.last.args
        end

        # Starter ではブロックを入れ子にできる
        def test_should_nest_blocks
          nodes = parse("//note[題]{\n本文。\n//list[][コード]{\nputs 1\n//}\n//}\n")

          note = nodes.first
          assert_equal 'note', note.name
          assert_equal 2, note.children.size
          assert_equal 'list', note.children.last.name
        end

        # 逐語ブロックの中身は構文として読まない——コードに ` - ` や ` : ` があっても
        # 箇条書き・定義リストにしてはいけない
        def test_should_keep_raw_block_body_verbatim
          nodes = parse("//list[][コード]{\n - if x\n : name\n//}\n")

          assert_equal [' - if x', ' : name'], nodes.first.body
          assert_empty nodes.first.children
        end

        # ================================================================
        # 段落・コメント（同 §2.1）
        # ================================================================
        def test_should_drop_line_comments
          nodes = parse("#@# コメント\n本文。\n")

          assert_equal 1, nodes.size
          assert_equal ['本文。'], nodes.first.lines
        end

        # 行頭の空白は Re:VIEW では意味を持たない
        def test_should_strip_leading_spaces_of_paragraph
          nodes = parse("   字下げした地の文。\n   続きの行。\n")

          assert_equal ['字下げした地の文。', '続きの行。'], nodes.first.lines
        end

        def test_should_split_paragraphs_by_blank_line
          nodes = parse("前の段落。\n\n次の段落。\n")

          assert_equal 2, nodes.size
          assert_equal [['前の段落。'], ['次の段落。']], nodes.map(&:lines)
        end

        # ================================================================
        # //include
        # ================================================================
        def test_should_expand_include_before_parsing
          File.write(File.join(@tmpdir, 'part.re'), "取り込まれた本文。\n", encoding: 'utf-8')
          nodes = parse("//include[part]\n")

          assert_equal ['取り込まれた本文。'], nodes.first.lines
        end

        def test_should_report_missing_include_target
          nodes = parse("//include[missing]\n")

          assert_empty nodes
          assert_equal :degraded, @report.findings.first.level
        end
      end
    end
  end
end
