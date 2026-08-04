# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/term_line'

module VivlioStarter
  module CLI
    module IndexCommands
      # レビューファイルの用語行（index-main-reference-section-spec.md R6）
      #
      # 起票の経緯: フラグを読む正規表現が 9 箇所に散っており、`m33` を足すと
      # すべてが軒並みマッチしなくなる状態だった。綴りをここへ集約した。
      class TermLineTest < Minitest::Test
        def parse(line) = TermLine.parse(line)

        # --- phase: フラグの解釈 ---

        def test_parses_a_plain_line
          line = parse('- [ig] **用語集** (ようごしゅう) - スコア: 353.0')

          assert_equal 'ig', line.flags
          assert_equal '用語集', line.term
          assert_equal 'ようごしゅう', line.yomi
          assert_nil line.main
          assert_in_delta 353.0, line.score
        end

        def test_parses_the_new_label
          assert_equal 'NEW!', parse('- [ ] `NEW!` **候補** (こうほ)').label
        end

        def test_pending_line
          assert_predicate parse('- [ ] **候補** (こうほ)'), :pending?
        end

        # --- phase: 主要参照 ---

        def test_parses_a_main_reference
          line = parse('- [im33] **用語集** (ようごしゅう)')

          assert_equal 'i', line.flags
          assert_equal ['33'], line.main
          refute line.suggested
        end

        # `m?` は機械の推測。著者が自分で決めたものと見分けられないと、
        # レビューが「全部確認し直す」作業になる。
        def test_question_mark_marks_a_suggestion
          line = parse('- [igm?21,22] **Markdown** (まーくだうん)')

          assert_equal 'ig', line.flags
          assert_equal %w[21 22], line.main
          assert line.suggested
        end

        # 値に m を含む章名でも壊れない（最初の m で分けるため）
        def test_chapter_name_containing_m
          assert_equal ['21-markdown-tutorial'], parse('- [im21-markdown-tutorial] **X** (x)').main
        end

        def test_negative_flag_with_main
          line = parse('- [-im33] **X** (x)')

          assert_equal '-i', line.flags
          assert_equal ['33'], line.main
        end

        # --- phase: 判定 ---

        def test_flag_predicates
          assert_predicate parse('- [i] **X** (x)'), :index?
          assert_predicate parse('- [ig] **X** (x)'), :index?
          assert_predicate parse('- [ig] **X** (x)'), :glossary?
          assert_predicate parse('- [g] **X** (x)'), :glossary?
          refute_predicate parse('- [g] **X** (x)'), :index?
          assert_predicate parse('- [r] **X** (x)'), :reject_both?
          assert_predicate parse('- [-i] **X** (x)'), :reject_index?
          assert_predicate parse('- [-g] **X** (x)'), :reject_glossary?
        end

        # 主要参照が付いても判定は変わらない（9 パーサの回帰）
        def test_predicates_ignore_the_main_part
          assert_predicate parse('- [igm33] **X** (x)'), :index?
          assert_predicate parse('- [igm33] **X** (x)'), :glossary?
          assert_predicate parse('- [-im?21,22] **X** (x)'), :reject_index?
        end

        # --- phase: 組み立て ---

        def test_builds_a_flag_field
          assert_equal '[ig]', TermLine.build('ig')
          assert_equal '[im33]', TermLine.build('i', main: %w[33])
          assert_equal '[igm?21,22]', TermLine.build('ig', main: %w[21 22], suggested: true)
        end

        # 章名や節指定はフラグ欄に収めない（`[igm21#Markdown とは]` は読めない）
        def test_long_values_do_not_go_into_the_flag_field
          assert_equal '[i]', TermLine.build('i', main: ['21-markdown-tutorial'])
          assert_equal '[i]', TermLine.build('i', main: ['21#Markdown とは'])
          refute TermLine.in_flag?(['21#見出し'])
          assert TermLine.in_flag?(%w[21 22])
        end

        # 組み立てたものは読み戻せる
        def test_round_trips
          built = TermLine.build('ig', main: %w[21 22], suggested: true)
          line = parse("- #{built} **X** (x)")

          assert_equal 'ig', line.flags
          assert_equal %w[21 22], line.main
          assert line.suggested
        end

        # --- phase: 用語行でないもの ---

        def test_returns_nil_for_non_term_lines
          ['  - 主要参照: 21', '## 2. 推奨候補', '本文です。', ''].each do |line|
            assert_nil parse(line), line.inspect
          end
        end

        def test_scans_a_document
          doc = <<~MD
            ## 1. 登録済み用語の確認

            - [im33] **用語集** (ようごしゅう)
              - 12-quickstart: 抜粋
            - [g] **CLI** (CLI)
          MD

          assert_equal %w[用語集 CLI], TermLine.scan(doc).map(&:term)
        end
      end
    end
  end
end
