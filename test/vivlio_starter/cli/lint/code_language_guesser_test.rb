# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../../lib/vivlio_starter/cli/lint/code_language_guesser'

module VivlioStarter
  module CLI
    module Lint
      # 二段目（Guesslang）を実際に呼ぶ結合テスト（code-language-detection-spec.md §5）。
      # Guesslang が入っていない環境では飛ばす。
      class CodeLanguageGuesserTest < Minitest::Test
        Request = CodeLanguageGuesser::Request
        ALL = CodeLanguageGuesser::GUESSLANG_TO_PRISM.values.uniq

        def setup
          @guesser = CodeLanguageGuesser.new
          skip 'Guesslang（@vscode/vscode-languagedetection）が入っていません' unless @guesser.available?
        end

        def test_should_guess_code_with_japanese_comments
          # 日本語をそのまま渡すと Guesslang は ini と判定する。置き換えてから渡していれば当たる
          ruby = <<~RUBY
            # 挨拶する人を表すクラス
            class Greeter
              def initialize(name)
                @name = name
              end

              # 名前を添えて挨拶する
              def greet
                puts "こんにちは、\#{@name}さん"
              end
            end
          RUBY
          css = <<~CSS
            /* 見出しの装飾 */
            .site-header {
              display: flex;
              justify-content: space-between;
              padding: 1rem 2rem;
              background-color: #fafafa;
            }

            /* リンクに重ねたときの色 */
            .site-header nav a:hover {
              color: #c00;
            }
          CSS

          result = @guesser.guess([Request.new(id: 1, body: ruby, candidates: ALL),
                                   Request.new(id: 2, body: css, candidates: %w[html css javascript])])

          assert_equal 'ruby', result[1]&.language
          assert_equal 'css', result[2]&.language
        end

        def test_should_choose_only_from_candidates_and_drop_short_bodies
          ruby = "def hello(name)\n  puts \"Hello, \#{name}\"\nend\n\nhello('world')\n"

          result = @guesser.guess([Request.new(id: 1, body: ruby, candidates: %w[css]),
                                   Request.new(id: 2, body: 'x = 1', candidates: ALL)])

          # 候補の外の言語は返さない。css の確信度は閾値に届かない
          assert_nil result[1]
          # 20 文字未満は Guesslang が判定しない
          assert_nil result[2]
        end
      end
    end
  end
end
