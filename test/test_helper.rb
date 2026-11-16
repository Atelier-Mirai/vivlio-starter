require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/pride'
begin
  require 'minitest/mock'
rescue LoadError
  # Some environments (notably minimal Ruby installations) may not ship with minitest/mock.
  # Provide a lightweight fallback so that tests using Object#stub continue to work.
  module MinitestStubFallback
    def stub(method_name, val_or_callable = nil)
      singleton = class << self; self; end

      original_defined = true
      original_method = singleton.instance_method(method_name)
    rescue NameError
      original_defined = false
    ensure
      replacement = if val_or_callable.respond_to?(:call)
                      val_or_callable
                    else
                      ->(*, &) { val_or_callable }
                    end

      singleton.define_method(method_name) do |*args, **kwargs, &block|
        replacement.call(*args, **kwargs, &block)
      end

      begin
        return yield
      ensure
        if original_defined
          singleton.define_method(method_name, original_method)
        else
          singleton.remove_method(method_name)
        end
      end
    end
  end

  Object.include(MinitestStubFallback) unless Object.method_defined?(:stub)
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# 前処理の指摘の集計（IssueRegistry）は、テストごとに空から始める。
# book.yml の値の警告は同じ文言を 1 回だけ出すので、前のテストの記録が残ると
# 後のテストで警告が出なくなる
module ResetIssueRegistryBeforeEachTest
  def before_setup
    super
    return unless defined?(VivlioStarter::CLI::PreProcessCommands::IssueRegistry)

    VivlioStarter::CLI::PreProcessCommands::IssueRegistry.reset!
  end
end

Minitest::Test.include(ResetIssueRegistryBeforeEachTest)

# 変換の段を 1 つだけ、HTML のファイルへ当てる（出力先の宣言の並びを通さずに、1 段の働きを確かめる）
module ApplyTransformHelper
  # @param transform [Module] 変換の段（VivlioStarter::CLI::Build::Transforms の下のモジュール）
  # @param html_files [Array<String>] 書き換える HTML のパス
  # @param target [Symbol] 出力先（:epub / :kindle）
  # @param workspace [String, nil] 出力先のワークスペース（省くと出力先の宣言の値）
  def apply_transform(transform, html_files, target: :kindle, workspace: nil)
    build = VivlioStarter::CLI::Build
    build::Transforms::Runner.apply!([transform], html_files, build::Transforms::Context.for(target, workspace:))
  end

  # 1 ページの DOM を書き換える補助メソッドを、HTML のファイルに当てる（読んで、ブロックへ渡し、書く）
  def rewrite_html_file(path)
    parser = VivlioStarter::CLI::PostProcessCommands::HtmlParser
    doc = parser.parse_html_document(File.read(path, encoding: 'utf-8'))
    yield doc
    parser.save_html_document(path, doc)
  end
end

Minitest::Test.include(ApplyTransformHelper)
