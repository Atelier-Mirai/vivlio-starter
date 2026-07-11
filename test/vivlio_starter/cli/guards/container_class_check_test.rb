# frozen_string_literal: true

# ================================================================
# Test: guards/container_class_check_test.rb
# ================================================================
# テスト対象:
#   Guards::ContainerClassCheck（lib/vivlio_starter/cli/guards/container_class_check.rb）
#
# 検証内容:
#   - 未知クラスを警告（停止しない）で検出し、修正候補を before → after で示す
#   - stylesheets/*.css に定義されたクラスは警告しない
#   - 経路 A（Ruby 前処理）のクラスは CSS が無くても警告しない
#   - 複数クラスの各々を照合し、属性トークンは照合対象にしない
#   - allowed_classes で追加許可したクラスは警告しない
#   - 候補が無い場合は「もしかして」行を出さない
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class ContainerClassCheckTest < Minitest::Test
      # 未知クラスは警告（エラーではない）で報告し、出現箇所と修正候補を添える。
      # 行番号を持つ警告は `path:line - 内容`（LinkImageValidator と同形）。
      def test_should_warn_on_unknown_class_with_suggestion
        with_temp_project do
          File.write('contents/11-install.md', ":::{.notion}\n本文\n:::\n")

          violations = Guards::ContainerClassCheck.new(allowed_classes: []).validate

          assert_equal 1, violations.size
          violation = violations.first
          assert_predicate violation, :warn?
          assert_equal "contents/11-install.md:1 - 未知のコンテナクラス '.notion' を検出しました", violation.message
          assert_includes violation.detail, '現状: :::{.notion}'
          assert_includes violation.detail, '候補: :::{.notice}'
        end
      end

      # 複数の候補は Jaro-Winkler 類似度の降順（DidYouMean の並び）で列挙する
      def test_should_list_multiple_candidates_best_first
        css = ".column { color: red; }\n.col-num { color: red; }\n"
        with_temp_project(css:) do
          File.write('contents/11-install.md', ":::{.colunm}\n:::\n")

          detail = Guards::ContainerClassCheck.new(allowed_classes: []).validate.first.detail

          assert_includes detail, '候補: :::{.column}, :::{.col-num}'
        end
      end

      # 複数クラスのうち誤りのものだけを候補で差し替えた、貼り替え可能な形で示す
      def test_should_replace_only_the_offending_class_in_candidate
        with_temp_project do
          File.write('contents/11-install.md', "::: {.notice .colunm}\n:::\n")

          detail = Guards::ContainerClassCheck.new(allowed_classes: []).validate.first.detail

          assert_includes detail, '現状: :::{.notice .colunm}'
          assert_includes detail, '候補: :::{.notice .column}'
        end
      end

      # CSS に定義されたクラスは警告しない
      def test_should_not_warn_on_class_defined_in_css
        with_temp_project do
          File.write('contents/11-install.md', ":::{.notice}\n本文\n:::\n")

          assert_empty Guards::ContainerClassCheck.new(allowed_classes: []).validate
        end
      end

      # 経路 A（convert_container_blocks）のクラスは CSS が無くても許可される
      def test_should_not_warn_on_preprocessed_classes_without_css
        with_temp_project(css: '') do
          File.write('contents/11-install.md', ":::{.book-card}\n本文\n:::\n")

          assert_empty Guards::ContainerClassCheck.new(allowed_classes: []).validate
        end
      end

      # 複数クラスは各々を照合する（既知のものは警告せず、未知のものだけ警告する）
      def test_should_validate_each_class_of_multiple_classes
        with_temp_project do
          File.write('contents/11-install.md', "::: {.notice .unknwn}\n:::\n")

          violations = Guards::ContainerClassCheck.new(allowed_classes: []).validate

          assert_equal 1, violations.size
          assert_includes violations.first.message, "'.unknwn'"
        end
      end

      # 属性トークン（scale=60%）はクラス名として照合しない
      def test_should_not_validate_attribute_tokens
        with_temp_project do
          File.write('contents/11-install.md', ":::{.rotate-table scale=60%}\n:::\n")

          assert_empty Guards::ContainerClassCheck.new(allowed_classes: []).validate
        end
      end

      # book.yml の preflight.allowed_classes で追加許可したクラスは警告しない
      def test_should_not_warn_on_explicitly_allowed_class
        with_temp_project do
          File.write('contents/11-install.md', ":::{.talk}\n本文\n:::\n")

          assert_empty Guards::ContainerClassCheck.new(allowed_classes: ['talk']).validate
        end
      end

      # 候補が得られない場合は「候補:」行を出さず、現状と対処方法のみを示す
      def test_should_omit_candidates_when_no_close_match
        with_temp_project do
          File.write('contents/11-install.md', ":::{.zzzzzzzzzz}\n:::\n")

          detail = Guards::ContainerClassCheck.new(allowed_classes: []).validate.first.detail

          refute(detail.any? { it.start_with?('候補:') })
          assert_includes detail, '現状: :::{.zzzzzzzzzz}'
          assert(detail.any? { it.include?('custom.css') })
        end
      end

      # CSS のコメント・文字列リテラル内の .foo はクラスセレクタとして拾わない
      def test_should_ignore_class_like_tokens_in_css_comments_and_strings
        css = <<~CSS
          /* .commented-out は無効化されたクラス */
          .real { content: ".fake"; margin: 0.5em; }
        CSS
        with_temp_project(css:) do
          File.write('contents/11-install.md', ":::{.commented-out}\n:::\n")

          violations = Guards::ContainerClassCheck.new(allowed_classes: []).validate

          assert_equal 1, violations.size
          assert_includes violations.first.message, "'.commented-out'"
        end
      end

      private

      DEFAULT_CSS = <<~CSS
        .notice { border: 1px solid #ccc; }
        .column { border: 1px solid #ccc; }
        .note   { border: 1px solid #ccc; }
        .img-text { display: flex; }
        .align-center { text-align: center; }
      CSS

      def with_temp_project(css: DEFAULT_CSS)
        Dir.mktmpdir('vs-container-class') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            FileUtils.mkdir_p('stylesheets')
            File.write('config/book.yml', "book:\n  main_title: 'test'\n")
            File.write('stylesheets/custom.css', css)
            yield
          end
        end
      end
    end
  end
end
