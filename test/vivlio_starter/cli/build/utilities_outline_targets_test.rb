# frozen_string_literal: true

# ================================================================
# Test: build/utilities_outline_targets_test.rb
# ================================================================
# テスト対象:
#   Build::Utilities.outline_target_htmls
#   PDF しおりの抽出対象 HTML を選ぶ。閲覧用（PdfMerger）と入稿用
#   （PrintPdfBuilder）が同じ選び方を共有するための一本化で、以前は
#   両者に同じ絞り込みが二重に書かれていた。
#
# 検証の軸:
#   - 章 HTML はアウトライン対象の章番号のものだけを拾う
#   - 目次・用語集・索引は特殊ページとして拾う（索引は設定で切り替わる）
#   - 前付・奥付は拾わない（OutlineExtractor が page_range_* で別途扱う）
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'fileutils'

require 'vivlio_starter/cli/loader'

class UtilitiesOutlineTargetsTest < Minitest::Test
  Common = VivlioStarter::CLI::Common
  Utilities = VivlioStarter::CLI::Build::Utilities

  LOG_METHODS_TO_SILENCE = %i[log_action log_success log_warn log_error log_info log_debug].freeze

  def setup
    @saved_log_methods = LOG_METHODS_TO_SILENCE.to_h { |name| [name, Common.method(name)] }
    LOG_METHODS_TO_SILENCE.each { |name| Common.define_singleton_method(name) { |*, **| } }
    @saved_index_enabled = Common.method(:index_enabled?)
  end

  def teardown
    @saved_log_methods&.each { |name, m| Common.define_singleton_method(name, m) }
    Common.define_singleton_method(:index_enabled?, @saved_index_enabled) if @saved_index_enabled
  end

  # 索引の有無を差し替える（CONFIG を書き換えずに分岐だけを制御する）。
  def with_index_enabled(enabled)
    Common.define_singleton_method(:index_enabled?) { enabled }
    yield
  end

  # ワークスペースの pdf/ に HTML を並べ、contents/ に章 .md を置いた一時プロジェクト。
  def within_workspace(chapters:, pages:)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(Common::BUILD_PDF_DIR)
        FileUtils.mkdir_p(Common::CONTENTS_DIR)
        chapters.each { File.write(File.join(Common::CONTENTS_DIR, "#{it}.md"), "# #{it}\n") }
        pages.each { File.write(File.join(Common::BUILD_PDF_DIR, "#{it}.html"), '<html></html>') }
        yield
      end
    end
  end

  def basenames(paths) = paths.map { File.basename(it, '.html') }.sort

  # 章 HTML と目次・用語集・索引を拾い、前付・奥付は拾わない。
  def test_should_collect_chapters_and_back_matter_pages
    within_workspace(
      chapters: %w[00-preface 11-sample 99-postface],
      pages: %w[00-preface 11-sample 99-postface _toc _glossarypage _indexpage _titlepage _legalpage _colophon]
    ) do
      targets = with_index_enabled(true) { Utilities.outline_target_htmls }

      assert_equal %w[00-preface 11-sample 99-postface _glossarypage _indexpage _toc].sort,
                   basenames(targets)
    end
  end

  # 索引が無効な本では、用語集・索引ページを拾わない（目次は常に拾う）。
  def test_should_skip_index_pages_when_index_disabled
    within_workspace(chapters: %w[11-sample], pages: %w[11-sample _toc _glossarypage _indexpage]) do
      targets = with_index_enabled(false) { Utilities.outline_target_htmls }

      assert_equal %w[11-sample _toc].sort, basenames(targets)
    end
  end

  # keep 指定（単章ビルド等）では、対象外の章 HTML を拾わない。
  def test_should_honor_keep_numbers
    within_workspace(chapters: %w[11-sample 12-other], pages: %w[11-sample 12-other _toc]) do
      targets = with_index_enabled(false) { Utilities.outline_target_htmls(%w[11-sample]) }

      assert_equal %w[11-sample _toc].sort, basenames(targets)
    end
  end
end
