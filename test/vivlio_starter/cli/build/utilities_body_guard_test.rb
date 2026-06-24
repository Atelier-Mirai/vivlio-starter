# frozen_string_literal: true

# ================================================================
# Test: build/utilities_body_guard_test.rb
# ================================================================
# テスト対象:
#   Build::Utilities.build_pdf_with_body_guard!
#   入稿用/閲覧用本文 PDF の「本文欠落（degenerate）」を検知し、リトライ、
#   回復不能ならビルドを中断するガード。print_pdf 本文が約4ページに化ける
#   flaky を握り潰さず、黙って出荷しないための恒久対策。
#
# MIT 本体のテストは AGPL の HexaPDF に依存しない。PDF 生成は Prawn、
# ページ数検査は Utilities.page_count（pdfinfo→MIT Provider）で行う。
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/utilities'

class UtilitiesBodyGuardTest < Minitest::Test
  Utilities = VivlioStarter::CLI::Build::Utilities

  LOG_METHODS_TO_SILENCE = %i[log_action log_success log_warn log_error log_info log_debug].freeze

  def setup
    common = VivlioStarter::CLI::Common
    @saved_log_methods = LOG_METHODS_TO_SILENCE.to_h { |name| [name, common.method(name)] }
    LOG_METHODS_TO_SILENCE.each { |name| common.define_singleton_method(name) { |*, **| } }
  end

  def teardown
    common = VivlioStarter::CLI::Common
    @saved_log_methods.each { |name, m| common.define_singleton_method(name, m) }
  end

  # 指定ページ数の PDF を path に生成する
  def write_pdf(path, pages)
    Prawn::Document.generate(path, skip_page_creation: true) do
      pages.times { start_new_page }
    end
  end

  # 本文相応のページ数を 1 回で生成できれば、リトライせず true を返す
  def test_should_pass_without_retry_when_body_is_substantial
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'out.pdf')
      calls = 0

      result = Utilities.build_pdf_with_body_guard!(out, min_pages: 10) do
        calls += 1
        write_pdf(out, 30)
        true
      end

      assert result
      assert_equal 1, calls, 'ページ数が十分なら 1 回で確定しリトライしないこと'
    end
  end

  # 初回 degenerate（本文欠落）→ 2 回目で正常なら、リトライして true を返す
  def test_should_retry_and_recover_after_degenerate_build
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'out.pdf')
      calls = 0

      result = Utilities.build_pdf_with_body_guard!(out, min_pages: 10, attempts: 3) do
        calls += 1
        write_pdf(out, calls == 1 ? 4 : 30) # 初回は4ページの degenerate、次回で回復
        true
      end

      assert result
      assert_equal 2, calls, '初回 degenerate なら再ビルドして 2 回目で確定すること'
    end
  end

  # ビルド自体が失敗（success=false）なら、ファイルが十分でもリトライ対象
  def test_should_retry_when_build_reports_failure
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'out.pdf')
      calls = 0

      result = Utilities.build_pdf_with_body_guard!(out, min_pages: 10, attempts: 3) do
        calls += 1
        write_pdf(out, 30)
        calls > 1 # 初回は失敗報告、2 回目で成功
      end

      assert result
      assert_equal 2, calls
    end
  end

  # 規定回数すべて degenerate なら、黙って出荷せずビルドを中断する（exit 1）
  def test_should_abort_when_degenerate_persists
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'out.pdf')
      calls = 0

      error = assert_raises(SystemExit) do
        Utilities.build_pdf_with_body_guard!(out, min_pages: 10, attempts: 3) do
          calls += 1
          write_pdf(out, 4) # 毎回 degenerate
          true
        end
      end

      refute_predicate error, :success?, '回復不能時は異常終了（exit 1）すること'
      assert_equal 3, calls, '規定回数ぶん試行してから中断すること'
    end
  end
end
