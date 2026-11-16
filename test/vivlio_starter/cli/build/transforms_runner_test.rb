# frozen_string_literal: true

# ================================================================
# Test: build/transforms_runner_test.rb
# ================================================================
# テスト対象:
#   Build::Transforms::Runner と Build::Transforms::Context（v2-architecture-spec.md §4.3）
#   - 段の順が外側・ページの順が内側で当たる
#   - call(doc, ctx) の段は DOM を、rewrite(html, ctx) の段は文字列を書き換える
#   - ページは最後に一度だけ書く
#   - ctx.pages でほかのページの今の DOM が読め、ctx.remember は本で一度だけ求める
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/build/epub_flow'

module VivlioStarter
  module CLI
    class TransformsRunnerTest < Minitest::Test
      Runner = Build::Transforms::Runner

      # 当たった順を記録し、body に印の段落を足す段
      def dom_step(name, log)
        Module.new do
          define_singleton_method(:call) do |doc, ctx|
            log << [name, ctx.page_name]
            doc.at_css('body').add_child("<p class=\"#{name}\">#{name}</p>")
          end
        end
      end

      def with_pages(*names)
        Dir.mktmpdir('vs-runner') do |dir|
          paths = names.map { File.join(dir, it) }
          paths.each { File.write(it, "<html><head><title>t</title></head><body><p>#{File.basename(it)}</p></body></html>") }
          yield paths, Build::Transforms::Context.for(:kindle, workspace: dir)
        end
      end

      def test_should_apply_each_step_to_every_page_before_the_next_step
        with_pages('a.html', 'b.html') do |paths, ctx|
          log = []

          result = Runner.apply!([dom_step('first', log), dom_step('second', log)], paths, ctx)

          assert_equal paths, result
          assert_equal [%w[first a.html], %w[first b.html], %w[second a.html], %w[second b.html]], log
          paths.each { assert_match(%r{<p class="first">first</p><p class="second">second</p>}, File.read(it)) }
        end
      end

      def test_should_write_each_page_once_after_all_steps
        with_pages('a.html') do |paths, ctx|
          seen = []
          peek = Module.new
          peek.define_singleton_method(:call) { |_doc, step_ctx| seen << File.read(step_ctx.path) }

          Runner.apply!([dom_step('first', []), peek], paths, ctx)

          refute_includes seen.first, 'class="first"', '段の途中では、ファイルはまだ書き換わっていない'
          assert_includes File.read(paths.first), 'class="first"'
        end
      end

      def test_should_rebuild_the_dom_only_when_a_rewrite_step_changes_the_html
        with_pages('a.html', 'b.html') do |paths, ctx|
          docs = Hash.new { |hash, key| hash[key] = [] }
          remember = Module.new
          remember.define_singleton_method(:call) { |doc, step_ctx| docs[step_ctx.page_name] << doc }
          # a.html だけ、閉じタグを足して段落を二つに分ける（途中の形は HTML として不正）
          split = Module.new
          split.define_singleton_method(:rewrite) do |html, step_ctx|
            step_ctx.page_name == 'a.html' ? html.sub('a.html', 'a</p><p>html') : html
          end

          Runner.apply!([remember, split, remember], paths, ctx)

          refute_same docs['a.html'][0], docs['a.html'][1], '書き換わったページは DOM を作り直す'
          assert_equal 2, docs['a.html'][1].css('body > p').size
          assert_same docs['b.html'][0], docs['b.html'][1], '変わらなかったページは同じ DOM のまま'
        end
      end

      def test_should_show_other_pages_current_dom_through_the_context
        with_pages('a.html', 'b.html') do |paths, ctx|
          counts = {}
          count = Module.new
          count.define_singleton_method(:call) do |_doc, step_ctx|
            counts[step_ctx.page_name] = step_ctx.pages.values.sum { it.css('p.first').size }
          end

          Runner.apply!([dom_step('first', []), count], paths, ctx)

          assert_equal({ 'a.html' => 2, 'b.html' => 2 }, counts, '前の段が全部のページに当たった後の DOM が見える')
        end
      end

      def test_should_compute_a_remembered_value_once_per_run
        with_pages('a.html', 'b.html') do |paths, ctx|
          computed = 0
          step = Module.new
          step.define_singleton_method(:call) { |_doc, step_ctx| step_ctx.remember(:value) { computed += 1 } }

          Runner.apply!([step], paths, ctx)
          Runner.apply!([step], paths, ctx)

          assert_equal 2, computed, '1 回の実行につき 1 度（実行をまたいでは持ち越さない）'
        end
      end
    end
  end
end
