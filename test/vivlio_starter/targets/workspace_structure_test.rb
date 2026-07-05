# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/targets/workspace_structure_test.rb
#
# ワークスペース構造保証テスト（WS）— 実ビルドを伴う構造検証
# docs/specs/vivlioverso-p4-investigation.md §5.5
#
# 【背景】
#   P4（ビルドワークスペース分離）で、ビルドの中間物はすべて
#   .cache/vs/build/{html,pdf,epub,kindle}/ の 4 消費者 dir に閉じ、
#   プロジェクトルートには最終成果物（PDF/EPUB/KPF）だけが着地する構造へ
#   移行した。本テストはその構造自体を保証する（P3 の「stylesheets/ 無差分」
#   ＝ manual_build_test MB-04 の拡張版）。
#
# 【検証内容】
#   WS-01: --no-clean ビルドが成功する（前提ガード）
#   WS-02: 4 消費者 dir が生成され、各用途の中間物が正しく配置される
#          （html=共有原本 / pdf=ステージ HTML＋用途別 config / epub・kindle=
#            ローカライズ資産＋生成 config、workspaceDir もワークスペース内）
#   WS-03: ビルドがプロジェクトルートへ旧方式の中間物を残さない
#   WS-04: ビルドが git 作業ツリーを汚さない（gitignore 漏れ・著者 dir 書き込み）
#
# 【実行方法】
#   rake test:targets   （--no-clean フルビルド 1 回。中間物を残して構造を検査する）
#   ※ リポジトリルートで実行すること。ルート直下の成果物は再生成される。
# =============================================================================

require "minitest/autorun"
require "fileutils"
require_relative "../support/build_helper"

class WorkspaceStructureTest < Minitest::Test
  REQUIRED_TOOLS = %w[node vivliostyle qpdf gs].freeze

  BUILD_DIR = File.join(".cache", "vs", "build")
  CONSUMER_DIRS = %w[html pdf epub kindle].map { File.join(BUILD_DIR, it) }.freeze

  # ビルドがルートへ残してはいけない旧方式（P4/P4b 以前）の生成物パターン。
  # images/math/ と _index_matches.yml も workspace 化済み（P4b）のため、
  # --no-clean でもルートには現れない（残るのは workspace 配下のみ）。
  ROOT_POLLUTION_GLOBS = %w[
    *.html
    _toc.md [0-9][0-9]-*.md _titlepage.md _legalpage.md _colophon.md _part*.md
    .vivliostyle
    book-settings.css vivliostyle.config.epub.js entries.epub.js
    _*.pdf output_tmp*.pdf blank_*.pdf
    _index_matches.yml
    images/_epub_assets images/headings images/math
  ].freeze

  # build が book.yml から再生成する派生ファイル（ビルド後に元へ戻し、
  # WS-04 の git 差分検査から除外する）
  GENERATED_FILES = [File.join("stylesheets", "page-settings.css")].freeze

  # MB-04 と同じ規約: ビルドが書き込み得る著者領域。追跡済み開発ファイル
  # （lib/ test/ docs/ 等）の変更はビルド中の開発者編集と区別できないため対象外。
  CONTENT_PREFIXES = %w[contents/ config/ images/ stylesheets/ covers/ codes/ templates/ data/ sources/].freeze

  def setup
    skip "config/book.yml が見つかりません（リポジトリルートで実行してください）" \
      unless File.exist?("config/book.yml")

    missing = REQUIRED_TOOLS.reject { system("which #{it} >/dev/null 2>&1") }
    skip "ビルドに必要なツールが不足しています: #{missing.join(', ')}" unless missing.empty?
  end

  # WS-01: --no-clean フルビルドが成功する（以降の構造検査の前提）
  def test_should_build_with_workspace_successfully
    result = self.class.build_result

    assert result[:success],
           "vs build --no-clean（targets: pdf, epub, kindle）が失敗しました\n#{result[:output].lines.last(20).join}"
  end

  # WS-02: 4 消費者 dir が生成され、各用途の中間物が配置される（P4 §3.2 / §5.2 / §5.3）
  def test_should_populate_four_consumer_dirs
    skip_unless_built!

    CONSUMER_DIRS.each do |dir|
      assert File.directory?(dir), "消費者 dir #{dir}/ が生成されていません"
    end

    # html/: VFM 変換済みの章 HTML（全消費者の共有原本）
    refute_empty Dir.glob(File.join(BUILD_DIR, "html", "[0-9][0-9]-*.html")),
                 "html/ に変換済みの章 HTML がありません"

    # pdf/: ステージ HTML ＋ 用途別 entries/config（固定名単一資源の廃止・P4 §3.2）
    refute_empty Dir.glob(File.join(BUILD_DIR, "pdf", "[0-9][0-9]-*.html")),
                 "pdf/ にステージされた章 HTML がありません"
    refute_empty Dir.glob(File.join(BUILD_DIR, "pdf", "vivliostyle.config.*.js")),
                 "pdf/ に用途別の生成 config がありません"
    refute_empty Dir.glob(File.join(BUILD_DIR, "pdf", "entries.*.js")),
                 "pdf/ に用途別の entries がありません"

    # epub/・kindle/: ステージ HTML ＋ ローカライズ資産 ＋ 生成 config（E2 確定案・§5.2/§5.3）
    %w[epub kindle].each do |consumer|
      dir = File.join(BUILD_DIR, consumer)
      refute_empty Dir.glob(File.join(dir, "[0-9][0-9]-*.html")),
                   "#{consumer}/ にステージされた章 HTML がありません"
      assert File.directory?(File.join(dir, "images")),
             "#{consumer}/ に画像資産がローカライズされていません"
      assert File.directory?(File.join(dir, "stylesheets")),
             "#{consumer}/ にスタイルシート資産がローカライズされていません"
      assert File.exist?(File.join(dir, "vivliostyle.config.epub.js")),
             "#{consumer}/ に生成 config（vivliostyle.config.epub.js）がありません"
      assert File.exist?(File.join(dir, "entries.epub.js")),
             "#{consumer}/ に entries.epub.js がありません"
    end

    # kindle/ は WebP を除外してローカライズする（Kindle 非対応・transcode 済み・§5.3）
    assert_empty Dir.glob(File.join(BUILD_DIR, "kindle", "**", "*.webp")),
                 "kindle/ に WebP が混入しています（Kindle は WebP 非対応）"

    # Vivliostyle の workspaceDir もワークスペース内（ルート .vivliostyle/ の撤去・§5.6）
    assert File.directory?(File.join(BUILD_DIR, ".vivliostyle")),
           "workspaceDir（#{BUILD_DIR}/.vivliostyle/）が生成されていません"
  end

  # WS-02b: 数式 SVG はワークスペース html/images/math/ に生成され、
  #         pdf/ へミラー・epub/kindle/ へローカライズされる（P4b §2.1〜2.3）
  def test_should_workspace_math_svgs_and_stage_to_consumers
    skip_unless_built!

    html_math = Dir.glob(File.join(BUILD_DIR, "html", "images", "math", "**", "*.svg"))
    skip "この原稿には数式 SVG が無いため検査対象なし" if html_math.empty?

    # pdf/ へミラーされ、消費者 dir 相対の images/math/… 参照が解決される（§2.2）
    refute_empty Dir.glob(File.join(BUILD_DIR, "pdf", "images", "math", "**", "*.svg")),
                 "数式 SVG が pdf/ へミラーされていません（P4b §2.2）"
    # epub/・kindle/ へもローカライズされる（EPUB 内部パスは images/math/… で現行と同一・§2.3）
    %w[epub kindle].each do |consumer|
      refute_empty Dir.glob(File.join(BUILD_DIR, consumer, "images", "math", "**", "*.svg")),
                   "#{consumer}/ に数式 SVG がローカライズされていません（P4b §2.3）"
    end
  end

  # WS-03: ビルド後もプロジェクトルートに旧方式の中間物が現れない
  def test_should_not_pollute_project_root
    skip_unless_built!

    pollution = ROOT_POLLUTION_GLOBS.flat_map { Dir.glob(it) }
    assert_empty pollution, <<~MSG
      ビルドがプロジェクトルートへ中間物を残しました（P4: 中間物は #{BUILD_DIR}/ に閉じるべき）:
      #{pollution.join("\n")}
    MSG
  end

  # WS-04: ビルドが git 作業ツリーを汚さない
  # (a) 新たな未追跡エントリの出現 = 成果物・中間物の gitignore 漏れ
  # (b) 著者領域（原稿・設定・素材）の変更 = ビルドによる破壊
  def test_should_keep_git_working_tree_clean
    result = self.class.build_result
    new_dirt = result[:dirt_after].lines - result[:dirt_before].lines

    offending = new_dirt.select do |line|
      status = line[0, 2].to_s
      path = line[3..].to_s.strip
      status.include?("?") || CONTENT_PREFIXES.any? { path.start_with?(it) }
    end

    assert_empty offending, <<~MSG
      ビルドによって git 作業ツリーが汚れました（gitignore 漏れ、または著者領域への書き込み）:
      #{offending.join}
    MSG
  end

  private

  # 構造検査はビルド成功が前提。失敗時は WS-01 に失敗を集約し、他はスキップで沈黙させる
  def skip_unless_built!
    skip "ビルドが失敗したため構造検査をスキップします" unless self.class.build_result[:success]
  end

  # === ビルド実行（クラスレベルで 1 回だけ） ===

  class << self
    def build_result
      @build_result ||= run_build_once
    end

    private

    # --no-clean で 1 回だけフルビルドし、ワークスペースを残したまま構造を検査する。
    # targets は 4 消費者 dir すべてが実際に使われる最小構成（pdf, epub, kindle）。
    # print_pdf は pdf/ を共有するだけで構造上の新情報がないため含めない。
    def run_build_once
      dirt_before = `git status --porcelain`
      generated = GENERATED_FILES.to_h { [it, (File.read(it) if File.exist?(it))] }
      success = output = nil
      VsTestSupport::BookYmlPatcher.rewrite_line(/^(\s*)targets:\s*[^\n]*$/, "\\1targets: pdf, epub, kindle") do
        success, output = VsTestSupport::VsBuilder.build!(
          vs_command: VsTestSupport::VsBuilder.repo_vs_command, extra_args: "--no-clean"
        )
      end
      restore_generated(generated)
      { success:, output:, dirt_before:, dirt_after: `git status --porcelain` }
    end

    # book.yml から再生成された派生ファイルを退避内容へ戻す（WS-04 のノイズ排除）
    def restore_generated(snapshot)
      snapshot.each do |path, content|
        if content
          File.write(path, content)
        elsif File.exist?(path)
          File.delete(path)
        end
      end
    end
  end
end
