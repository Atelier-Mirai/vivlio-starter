# frozen_string_literal: true

# ================================================================
# Test: css/css_layer_test.rb
# ================================================================
# テスト対象:
#   同梱の CSS（stylesheets/ と themes/）が、層で優先を決める設計の決まりを守っていること
#   （css-layer-restructure-spec.md §2.4）。
#
# 検証方法:
#   ファイルを読み、コメントを外した宣言の中に `!important` が無いことを見る。
#   層の中の !important は層の順を逆にする（前の層が後の層に勝つ）ので、vs とテーマの CSS では
#   使わない。著者の custom.css は層の外にあり、今と同じに働くので対象にしない（§7.1）。
# ================================================================

require 'test_helper'

module VivlioStarter
  module CLI
    module Css
      class CssLayerTest < Minitest::Test
        ROOT = File.expand_path('../../../..', __dir__)
        AUTHOR_FILES = %w[stylesheets/custom.css].freeze

        def test_should_not_use_important_in_bundled_stylesheets
          files = bundled_css_files
          refute_empty files, 'stylesheets/ の CSS が見つからない'

          offenders = files.flat_map do |path|
            important_lines(File.read(path, encoding: 'utf-8')).map { "#{relative(path)}:#{it}" }
          end
          assert_empty offenders, "層の中では !important を使わない（css-layer-restructure-spec.md §2.4）:\n" \
                                  "#{offenders.join("\n")}"
        end

        # 検査が空振りしないこと（コメントの中は数えず、宣言の中は数える）
        def test_should_find_important_only_outside_comments
          css = <<~CSS
            /* 以前は !important で打ち消していた */
            .a { color: red; }
            .b {
              display: none ! important;
            }
          CSS

          assert_equal [4], important_lines(css)
        end

        private

        def bundled_css_files
          Dir.glob(File.join(ROOT, '{stylesheets,themes}', '**', '*.css'))
             .reject { AUTHOR_FILES.include?(relative(it)) }
             .sort
        end

        # !important を含む行の番号（1 始まり）。コメントは同じ行数の空白に置き換えて外す
        def important_lines(css)
          stripped = css.gsub(%r{/\*.*?\*/}m) { it.gsub(/[^\n]/, ' ') }
          stripped.each_line.with_index(1).filter_map { |line, number| number if line.match?(/!\s*important/i) }
        end

        def relative(path) = path.delete_prefix("#{ROOT}/")
      end
    end
  end
end
