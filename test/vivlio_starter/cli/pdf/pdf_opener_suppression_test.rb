# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/cli/pdf/pdf_opener_suppression_test.rb
#
# PdfOpener が「自動実行のときだけプレビューを抑える」ことを確かめる。
#
# 著者が `vs build` を打ったあとに成果物が開くのは正しい振る舞いなので、
# 既定は開く側。抑えるのはリリースゲートのように機械が検査する場面だけで、
# 判定の窓口は環境変数 1 つに閉じている（Rakefile の test:no_preview が立てる）。
# =============================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pdf'

module VivlioStarter
  module CLI
    module PdfCommands
      class PdfOpenerSuppressionTest < Minitest::Test
        ENV_KEY = PdfOpener::SUPPRESS_ENV

        def setup
          @original = ENV.fetch(ENV_KEY, nil)
        end

        def teardown
          ENV[ENV_KEY] = @original
        end

        # 立っていれば開かない。存在しない PDF を渡しても、パスの解決まで
        # 進まないので例外にならない——抑止は call の入口で効く。
        def test_should_not_open_when_suppressed
          ENV[ENV_KEY] = '1'
          opener = PdfOpener.new({}, '/nonexistent/never-opened.pdf')

          assert_nil opener.call
        end

        # 既定（未設定）では抑えない。著者の vs build は従来どおり開く。
        def test_should_not_suppress_by_default
          ENV.delete(ENV_KEY)

          refute PdfOpener.new({}, nil).send(:suppressed?)
        end

        # Common.truthy? の綴りをそのまま受ける（0 や空文字では抑えない）。
        def test_should_follow_the_project_wide_truthy_spelling
          opener = PdfOpener.new({}, nil)

          %w[1 true yes on].each do |value|
            ENV[ENV_KEY] = value
            assert opener.send(:suppressed?), "#{value} は真として扱う"
          end

          ['0', 'false', ''].each do |value|
            ENV[ENV_KEY] = value
            refute opener.send(:suppressed?), "#{value} は偽として扱う"
          end
        end
      end
    end
  end
end
