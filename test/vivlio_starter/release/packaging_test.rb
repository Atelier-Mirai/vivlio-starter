# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/release/packaging_test.rb
#
# パッケージング E2E（PK）
# docs/specs/test-suite-expansion-spec.md §6
#
# 【検証内容】
#   PK-01: .gem に lib/project_scaffold/ の全ファイルと bin/ が含まれる
#   PK-02: 隔離 GEM_HOME へインストールした vs が起動する
#   PK-03: インストール物の scaffold だけで一時プロジェクトを構成し vs build が通る
#   PK-04: 開発用ファイル（test/ docs/ .claude/ ほか）が混入していない
#
# 【実行方法】
#   rake test:package   （gem build + 隔離インストール + 実ビルドで数分かかる）
#
# 【注意】
#   `vs new` は内部で `vs doctor --fix` を自動実行し brew install 等が走る
#   危険があるため使わない（spec §6.3）。scaffold の直接コピー +
#   プレースホルダの既定値展開でプロジェクトを構成する。
# =============================================================================

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "rubygems/package"

class PackagingTest < Minitest::Test
  REPO_ROOT = File.expand_path("../../..", __dir__)

  # gem に含まれてはならない開発用エントリ（PK-04。混入の再発防止）
  FORBIDDEN_PREFIXES = %w[test/ docs/ contents/ covers/ stylesheets/ .claude/ .github/ config/].freeze
  FORBIDDEN_BASENAMES = %w[.DS_Store].freeze
  FORBIDDEN_PATTERNS = [/\.bak(\.|$)/].freeze

  class << self
    # gem build は数十秒かかるため 1 回だけ実行し、全テストで共有する
    def built_gem_path
      @built_gem_path ||= build_gem_once
    end

    def gem_contents
      @gem_contents ||= Gem::Package.new(built_gem_path).contents
    end

    # 隔離 GEM_HOME へのインストールも 1 回だけ行い、PK-02 / PK-03 で共有する
    def isolated_gem_home
      @isolated_gem_home ||= install_gem_once
    end

    private

    def build_gem_once
      out_dir = Dir.mktmpdir("vs-pkg-gem")
      gem_path = File.join(out_dir, "vivlio-starter-under-test.gem")
      ok = system("gem build vivlio-starter.gemspec -o #{gem_path}",
                  chdir: REPO_ROOT, out: File::NULL, err: File::NULL)
      raise "gem build に失敗しました" unless ok && File.file?(gem_path)

      gem_path
    end

    def install_gem_once
      gem_home = Dir.mktmpdir("vs-pkg-home")
      # --ignore-dependencies: 検証対象は「本体 gem の同梱物の完全性」であり
      # 依存 gem の取得可能性ではない。依存（samovar / natto 等）は実行時に
      # GEM_PATH 経由でホスト環境のものを参照する（ネットワークを起動しない / spec §16-2）
      ok = system("gem install #{built_gem_path} --install-dir #{gem_home} " \
                  "--no-document --local --ignore-dependencies",
                  out: File::NULL, err: File::NULL)
      raise "隔離 GEM_HOME へのインストールに失敗しました" unless ok

      gem_home
    end
  end

  # PK-01: scaffold の全ファイルと bin/ が gem に含まれる（ホワイトリスト退行の検知）
  def test_should_package_entire_scaffold_and_binaries
    contents = self.class.gem_contents

    scaffold_files = Dir.glob("lib/project_scaffold/**/*", File::FNM_DOTMATCH, base: REPO_ROOT)
                        .select { File.file?(File.join(REPO_ROOT, it)) }
                        .reject { File.basename(it) == ".DS_Store" }
    missing = scaffold_files - contents

    assert_empty missing, "scaffold のファイルが gem に含まれていません:\n  #{missing.first(20).join("\n  ")}"
    assert_includes contents, "bin/vs"
    assert_includes contents, "bin/vivlio-starter"
    assert_includes contents, "README.md"
    assert_includes contents, "THIRD-PARTY-LICENSES.md"
  end

  # PK-04: 開発用ファイルが混入していない（430MB 事故の再発防止）
  def test_should_not_package_development_files
    contraband = self.class.gem_contents.select do |path|
      FORBIDDEN_PREFIXES.any? { path.start_with?(it) } ||
        FORBIDDEN_BASENAMES.include?(File.basename(path)) ||
        FORBIDDEN_PATTERNS.any? { path.match?(it) }
    end

    assert_empty contraband, "開発用ファイルが gem に混入しています:\n  #{contraband.first(20).join("\n  ")}"
  end

  # PK-02: 隔離環境へインストールした vs が起動する（require 漏れ・bin 同梱漏れの検知）
  def test_should_run_installed_vs_in_isolated_gem_home
    gem_home = self.class.isolated_gem_home

    output = run_installed_vs(gem_home, "--version", chdir: Dir.tmpdir)

    assert_predicate $?, :success?, "インストール版 vs --version が失敗しました:\n#{output}"
    assert_match(/\d+\.\d+\.\d+/, output, "バージョン文字列が出力されるべき")
  end

  # PK-03: インストール物の scaffold だけでプロジェクトを構成しビルドが通る
  # （gem 同梱物のみで完結することの最終確認。実ビルドのため遅い）
  def test_should_build_project_made_from_installed_scaffold
    missing = %w[node vivliostyle qpdf gs].reject { system("which #{it} >/dev/null 2>&1") }
    skip "ビルドに必要なツールが不足しています: #{missing.join(', ')}" unless missing.empty?

    gem_home = self.class.isolated_gem_home
    scaffold = Dir.glob(File.join(gem_home, "gems", "vivlio-starter-*", "lib", "project_scaffold")).first
    refute_nil scaffold, "インストール先に project_scaffold が見つかりません"

    Dir.mktmpdir("vs-pkg-project") do |project|
      FileUtils.cp_r("#{scaffold}/.", project)
      expand_book_yml_placeholders!(File.join(project, "config", "book.yml"))

      output = run_installed_vs(gem_home, "build", chdir: project)

      assert_predicate $?, :success?,
                       "インストール版 vs build が失敗しました:\n#{output.lines.last(20).join}"
      pdf = Dir.glob(File.join(project, "**", "*.pdf")).max_by { File.mtime(it) }
      refute_nil pdf, "PDF が生成されませんでした"
    end
  end

  private

  # 隔離 GEM_HOME の vs をサブプロセスで実行する（ホストの gem 環境を汚さない）。
  # 本体 gem は隔離側から、依存 gem はホスト側から解決する（install_gem_once 参照）
  def run_installed_vs(gem_home, args, chdir:)
    env = {
      "GEM_HOME" => gem_home,
      "GEM_PATH" => "#{gem_home}#{File::PATH_SEPARATOR}#{`gem env gempath`.strip}",
      "PATH" => "#{File.join(gem_home, 'bin')}:#{ENV.fetch('PATH')}"
    }
    IO.popen(env, "#{File.join(gem_home, 'bin', 'vs')} #{args} 2>&1", chdir: chdir, &:read)
  end

  # vs new を経由しないため、book.yml のプレースホルダを既定値で静的展開する
  def expand_book_yml_placeholders!(path)
    content = File.read(path, encoding: "utf-8")
                  .gsub("{{MAIN_TITLE}}", "パッケージング検証の本")
                  .gsub("{{SUBTITLE}}", "")
                  .gsub("{{AUTHOR}}", "テスト太郎")
                  .gsub("{{PUBLISHER}}", "")
                  .gsub("{{PROJECT_NAME}}", "pkg_test")
    File.write(path, content, encoding: "utf-8")
  end
end
