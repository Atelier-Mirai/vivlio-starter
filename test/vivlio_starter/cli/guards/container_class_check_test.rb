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
#   - 候補が無い場合は「もしかして」行を出さない
#
# 既知クラスの登録手段は「CSS を書くこと」だけ（book.yml の preflight.allowed_classes は廃止）。
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

          violations = Guards::ContainerClassCheck.new.validate

          assert_equal 1, violations.size
          violation = violations.first
          assert_predicate violation, :warn?
          assert_equal "contents/11-install.md:1 - 未知のコンテナクラス '.notion' を検出しました", violation.message
          assert_includes violation.detail, '現状: :::{.notion}'
          assert_includes violation.detail, '候補: :::{.notice}'
        end
      end

      # 行内の属性 `[文字]{.class}` も同じ許可リストで照合する。コードの中と、行末の段落に付けるクラスは見ない。
      # 色の名前は短いので、隣り合う 2 字の入れ替え（rde → red）も候補にする
      def test_should_warn_on_unknown_inline_attribute_class
        css = ".sesame { text-emphasis-style: filled sesame; }\n.red { color: red; }\n"
        with_temp_project(css:) do
          File.write('contents/11-install.md', <<~MD)
            [傍点]{.sesame}と[傍点]{.sesami}と[字]{.rde}
            `[コード]{.x}` と右に寄せる[用語]{.text-right}
          MD

          violations = Guards::ContainerClassCheck.new.validate

          assert_equal ["contents/11-install.md:1 - 未知の行内のクラス '.sesami' を検出しました",
                        "contents/11-install.md:1 - 未知の行内のクラス '.rde' を検出しました"], violations.map(&:message)
          assert_predicate violations.first, :warn?
          assert_includes violations.first.detail, '現状: [傍点]{.sesami}'
          assert_includes violations.first.detail, '候補: [傍点]{.sesame}'
          assert_includes violations.last.detail, '候補: [字]{.red}'
        end
      end

      # 色の値・キーの点検（inline-color-mark-spec.md §2.3 の表）。蛍光ペンの `==…=={…}` も同じに見る
      def test_should_warn_on_unreadable_colors_unknown_keys_and_repeats
        with_temp_project do
          File.write('contents/11-install.md', <<~MD)
            [字]{color=rde} [字]{color=rgb(0,0,0)} [字]{colour=red} [字]{bg=red}
            [字]{color=red color=blue} ==字=={background=#ffff0080} [字]{color=#abc background=theme}
          MD

          violations = Guards::ContainerClassCheck.new.validate
          by_message = violations.to_h { [it.message, it.detail] }

          assert_equal 6, violations.size
          assert_includes by_message["contents/11-install.md:1 - 読めない色の値 'color=rde' を検出しました"],
                          '候補: [字]{color=red}'
          assert_includes by_message["contents/11-install.md:1 - まだ受けない色の書き方 'color=rgb(0,0,0)' を検出しました"],
                          '候補: [字]{color=#000000}'
          assert_includes by_message["contents/11-install.md:1 - 知らないキー 'colour=' を検出しました"],
                          '候補: [字]{color=red}'
          assert_includes by_message["contents/11-install.md:1 - 知らないキー 'bg=' を検出しました"],
                          '候補: [字]{background=red}'
          assert_includes by_message["contents/11-install.md:2 - 同じキー 'color=' を 2 回書いています"],
                          '→ 後ろの値（color=blue）で組まれます。どちらか一つにしてください'
          assert_includes by_message["contents/11-install.md:2 - まだ受けない色の書き方 'background=#ffff0080' を検出しました"],
                          '候補: ==字=={background=#ffff00}'
        end
      end

      # コードのコメントの `[!]{…}`。クラスはテーマ色の 13 個・キーは color= だけ。
      # 記法の説明（```markdown の中）は紙面で色にしないので見ない
      def test_should_warn_on_unreadable_alert_comment_colors
        with_temp_project do
          File.write('contents/11-install.md', <<~MD)
            本文

            ```ruby
            a # [!]{.blu} 注意
            b # [!]{color=reed}
            c # [!]{.blue} [!]{color=#3a9d5d}
            ```

            ````markdown
            ```ruby
            d # [!]{.nope}
            ```
            ````
          MD

          violations = Guards::ContainerClassCheck.new.validate

          assert_equal ["contents/11-install.md:4 - コメントの [!] の知らない色のクラス '.blu' を検出しました",
                        "contents/11-install.md:5 - 読めない色の値 'color=reed' を検出しました"], violations.map(&:message)
          assert_includes violations.first.detail, '候補: [!]{.blue}'
          assert_includes violations.first.detail, '→ 既定の赤（#eb0000）で組まれます'
        end
      end

      # 複数の候補は Jaro-Winkler 類似度の降順（DidYouMean の並び）で列挙する
      def test_should_list_multiple_candidates_best_first
        css = ".column { color: red; }\n.col-num { color: red; }\n"
        with_temp_project(css:) do
          File.write('contents/11-install.md', ":::{.colunm}\n:::\n")

          detail = Guards::ContainerClassCheck.new.validate.first.detail

          assert_includes detail, '候補: :::{.column}, :::{.col-num}'
        end
      end

      # 複数クラスのうち誤りのものだけを候補で差し替えた、貼り替え可能な形で示す
      def test_should_replace_only_the_offending_class_in_candidate
        with_temp_project do
          File.write('contents/11-install.md', "::: {.notice .colunm}\n:::\n")

          detail = Guards::ContainerClassCheck.new.validate.first.detail

          assert_includes detail, '現状: :::{.notice .colunm}'
          assert_includes detail, '候補: :::{.notice .column}'
        end
      end

      # CSS に定義されたクラスは警告しない
      def test_should_not_warn_on_class_defined_in_css
        with_temp_project do
          File.write('contents/11-install.md', ":::{.notice}\n本文\n:::\n")

          assert_empty Guards::ContainerClassCheck.new.validate
        end
      end

      # 経路 A（convert_container_blocks）のクラスは CSS が無くても許可される
      def test_should_not_warn_on_preprocessed_classes_without_css
        with_temp_project(css: '') do
          File.write('contents/11-install.md', ":::{.book-card}\n本文\n:::\n")

          assert_empty Guards::ContainerClassCheck.new.validate
        end
      end

      # showcase は ShowcaseTransformer がブロックごと消費するため、
      # CSS に `.showcase` セレクタが無くても警告しない
      def test_should_not_warn_on_showcase_without_css
        with_temp_project(css: '') do
          File.write('contents/11-install.md', ":::{.showcase}\n![shot](a.png)\nrect:1 0,0,10,10\n:::\n")

          assert_empty Guards::ContainerClassCheck.new.validate
        end
      end

      # 複数クラスは各々を照合する（既知のものは警告せず、未知のものだけ警告する）
      def test_should_validate_each_class_of_multiple_classes
        with_temp_project do
          File.write('contents/11-install.md', "::: {.notice .unknwn}\n:::\n")

          violations = Guards::ContainerClassCheck.new.validate

          assert_equal 1, violations.size
          assert_includes violations.first.message, "'.unknwn'"
        end
      end

      # 属性トークン（scale=60%）はクラス名として照合しない
      def test_should_not_validate_attribute_tokens
        with_temp_project do
          File.write('contents/11-install.md', ":::{.rotate-table scale=60%}\n:::\n")

          assert_empty Guards::ContainerClassCheck.new.validate
        end
      end

      # 候補が得られない場合は「候補:」行を出さず、現状と対処方法のみを示す
      def test_should_omit_candidates_when_no_close_match
        with_temp_project do
          File.write('contents/11-install.md', ":::{.zzzzzzzzzz}\n:::\n")

          detail = Guards::ContainerClassCheck.new.validate.first.detail

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

          violations = Guards::ContainerClassCheck.new.validate

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
