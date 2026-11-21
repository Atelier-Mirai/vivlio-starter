# frozen_string_literal: true

require 'test_helper'
require 'tempfile'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 縦書きの本は、どのページの body にも組方向のクラス vs-vertical を付ける（theme-contract-spec.md §2.2）。
      # 横に組む奥付にも付ける（本の軸なので）。横書きの本には付けない
      class BodyClassInjectorTest < Minitest::Test
        Entry = Data.define(:kind)

        def test_should_add_the_vertical_class_only_to_a_vertical_book
          assert_equal 'preface vs-vertical', body_class(:preface, 'vertical')
          assert_equal 'colophon vs-vertical', body_class(:colophon, 'vertical')
          assert_equal 'preface', body_class(:preface, 'horizontal')
        end

        private

        def body_class(kind, writing_mode)
          original = Common::CONFIG
          Common.install_configuration!(Common.wrap_config({ page: { writing_mode: } }))
          Tempfile.create(['vs_body_', '.html']) do |f|
            f.write("<html><body>\n<p>本文</p>\n</body></html>\n")
            f.flush
            BodyClassInjector.inject_body_class(f.path, Entry.new(kind:))
            return File.read(f.path)[/<body class="([^"]*)">/, 1]
          end
        ensure
          Common.install_configuration!(original)
        end
      end
    end
  end
end
