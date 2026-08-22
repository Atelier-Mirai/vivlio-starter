# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/notation/notation_coverage_test.rb
#
# 記法網羅フィクスチャ（test/vivlio_starter/fixtures/notation/）を隔離した
# 一時プロジェクトで実ビルドし、**記法が生き残っているか**を見る。
# 仕様: markdown-notation-collision-spec.md §13
#
# なぜ VFM 単体と突き合わせるのか:
#   既存の不変条件は「壊れた痕跡を探す」形で、どう壊れるかを先に知っていないと
#   書けない。2026-08-22 に見つかった 3 件（参照リンク・タスクリスト・字下げ
#   コードブロック）はいずれも既存の条件に掛からなかった。VFM が組めたものが
#   パイプラインで消えていれば落ちる、という形にすれば、壊れ方を知らなくてよい。
#
# なぜリポジトリの contents/ を使わないのか:
#   著者の原稿を差し替えると、中断時に壊れた作業ツリーが残る。`vs new` で
#   一時プロジェクトを作り、そこへフィクスチャを置いて回す。
# =============================================================================

require "test_helper"
require "fileutils"
require "tmpdir"
require "yaml"
require "rbconfig"

class NotationCoverageTest < Minitest::Test
  REPO_ROOT   = File.expand_path("../../..", __dir__)
  FIXTURE_DIR = File.join(REPO_ROOT, "test", "vivlio_starter", "fixtures", "notation")

  # 記法ごとの検体。signal は**実ビルド後の HTML**に現れるべきしるし。
  #   :kept        … 生き残らなければ失敗
  #   :known_broken … 既知の破れ。🟡 で報告するが失敗にはしない。
  #                   **実装したらこの印を外す**（外し忘れると直ったことに気づけない）
  NOTATIONS = [
    { name: "インラインリンク",   signal: /<a\s[^>]*href="https:\/\/example\.com"/,        state: :kept },
    { name: "画像",               signal: /<img\s/,                                        state: :kept },
    { name: "表",                 signal: /<table[\s>]/,                                   state: :kept },
    { name: "引用",               signal: /<blockquote[\s>]/,                              state: :kept },
    { name: "フェンスコード",     signal: /<pre[^>]*><code/,                               state: :kept },
    { name: "箇条書き",           signal: /<ul[\s>]/,                                      state: :kept },
    { name: "番号付きリスト",     signal: /<ol[\s>]/,                                      state: :kept },
    { name: "見出し h3",          signal: /<h3[\s>]/,                                      state: :kept },
    { name: "脚注",               signal: /footnote|脚注の中身/,                           state: :kept },
    { name: "参照リンク",         signal: /<a\s[^>]*href="https:\/\/example\.com"[^>]*>(?:(?!<\/a>).)*完全形/m,
                                  state: :kept },
    { name: "タスクリスト",       signal: /task-list-item/,                                state: :kept }
  ].freeze

  class << self
    attr_reader :project_dir, :build_error

    # ビルドは 1 度だけ。7 章で 80 秒ほどかかる。
    def build_once!
      return @built if defined?(@built)

      @built = true
      @work = Dir.mktmpdir("vs-notation")
      at_exit { FileUtils.remove_entry(@work) if @work && Dir.exist?(@work) }
      @project_dir = File.join(@work, "notationbook")
      @build_error = setup_project_and_build
      @built
    end

    private

    def setup_project_and_build
      unless run_vs(@work, "new", "notationbook", "--yes")
        return "vs new に失敗しました"
      end

      install_fixture
      return "vs build に失敗しました" unless run_vs(@project_dir, "build", "--no-clean")

      nil
    end

    def install_fixture
      contents = File.join(@project_dir, "contents")
      FileUtils.rm_f(Dir[File.join(contents, "*.md")])
      Dir[File.join(FIXTURE_DIR, "*.md")].each { FileUtils.cp(it, contents) }
      FileUtils.rm_f(File.join(contents, "README.md"))
      write_catalog(contents)
    end

    # フィクスチャのファイル名から catalog を起こす（番号の約束は Entry と同じ）。
    def write_catalog(contents)
      names = Dir[File.join(contents, "*.md")].map { File.basename(it, ".md") }.sort
      preface   = names.grep(/\A00-/)
      postface  = names.grep(/\A99-/)
      appendix  = names.grep(/\A9[0-8]-/)
      catalog = { "PREFACE" => preface,
                  "CHAPTERS" => names - preface - postface - appendix,
                  "APPENDICES" => appendix,
                  "POSTFACE" => postface }
      File.write(File.join(@project_dir, "config", "catalog.yml"), catalog.to_yaml)
    end

    # **リポジトリの bin/vs を直接叩く。** PATH 上の `vs` は導入済み gem を使うため、
    # 変更が反映されないまま検証してしまう（rake reinstall を要らなくする）。
    def run_vs(dir, *args)
      system(RbConfig.ruby, "-I#{File.join(REPO_ROOT, 'lib')}", File.join(REPO_ROOT, "bin", "vs"),
             *args, chdir: dir, out: File::NULL, err: File::NULL)
    end
  end

  def setup
    self.class.build_once!
    skip("vfm が見つかりません") unless system("which vfm > /dev/null 2>&1")
    flunk(self.class.build_error) if self.class.build_error
  end

  # VFM が組めたものは、パイプラインを通っても残っていること。
  def test_notations_survive_the_pipeline
    base = vfm_baseline
    pipe = built_html

    broken = []
    NOTATIONS.each do |entry|
      assert_match entry[:signal], base,
                   "フィクスチャが「#{entry[:name]}」を含んでいません（検体を足してください）"

      if entry[:state] == :kept
        assert_match entry[:signal], pipe, "「#{entry[:name]}」がビルドで失われました"
      elsif pipe.match?(entry[:signal])
        broken << "#{entry[:name]}（#{entry[:spec]}）"
      end
    end

    return if broken.empty?

    flunk("既知の破れが直っています。NOTATIONS の :known_broken を外してください: #{broken.join(', ')}")
  end

  # 既知の破れを一覧で見せる（失敗にはしない。直ったら上のテストが落ちる）。
  def test_report_known_broken
    pipe = built_html
    still = NOTATIONS.select { it[:state] == :known_broken && !pipe.match?(it[:signal]) }
    still.each { puts "🟡 未実装のため壊れたまま: #{it[:name]}（#{it[:spec]}）" }
    assert true
  end

  # コード領域へ索引タグが注入されていないこと。
  # 字下げコードブロックは既知の破れ（§6 L-2・非対応と決めた記法）なので数から外す。
  # 目印は **ASCII のまま残る文字列**にする。和文の目印は索引タグが語の途中へ
  # 割り込んで分断され（`<dfn>字下げ</dfn>コードブロック…`）、照合できない。
  INDENTED_MARKER = 'indented = "code block"'

  def test_no_index_tags_inside_code_regions
    polluted = built_html.scan(/<pre[^>]*>[\s\S]*?<\/pre>/).select { it.include?("index-term") }
    others   = polluted.reject { it.include?(INDENTED_MARKER) }

    assert_empty others,
                 "字下げコードブロック以外のコード領域に索引タグが入りました（#{others.size} 件）"
    assert_equal 1, polluted.size - others.size,
                 "字下げコードブロックの検体が壊れています（§6 L-2 の再現に使うため、索引語を含めておくこと）"
  end

  private

  def built_html
    @built_html ||= File.read(html_path("01-commonmark"))
  end

  def vfm_baseline
    @vfm_baseline ||= `vfm #{File.join(FIXTURE_DIR, '01-commonmark.md')} 2>/dev/null`
  end

  def html_path(basename)
    File.join(self.class.project_dir, ".cache", "vs", "build", "html", "#{basename}.html")
  end
end
