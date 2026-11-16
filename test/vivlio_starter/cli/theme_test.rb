# frozen_string_literal: true

# ================================================================
# Test: theme_test.rb
# ================================================================
# テスト対象:
#   Theme（lib/vivlio_starter/cli/theme.rb）・Theme::Manifest・Theme::Contract
#
# 検証内容（theme-contract-spec.md §3.1・§3.2・§8）:
#   - extends: の読む順: styles: と出力先の CSS は土台 → 自分、tokens: は自分の値が勝つ
#   - supports: の書いていない軸は土台から、土台も書いていなければ既定から補う
#   - extends: は 1 段だけ。土台が無い・さらに extends: を持つなら誤り
#   - theme.yml の誤り（名前の食い違い・契約の版が無い・テーマの外の styles:・書き出せない tokens:）
#   - contract: と requires_vs: をこの vs と突き合わせる
#   - リポジトリの themes/standard/ は、中身の無い宣言として読める
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/theme'

module VivlioStarter
  module CLI
    class ThemeTest < Minitest::Test
      REPO_ROOT = File.expand_path('../../..', __dir__)

      # standard は見出しの 2 枚と、その出力先の CSS を持ち、tokens: は空（theme-contract-spec.md §4・§9 の S6 の決め 12）
      def test_should_read_the_bundled_standard_theme
        theme = Theme.resolve('standard', root: REPO_ROOT)

        assert_pattern do
          theme.manifest => { name: 'standard', title: '標準（技術書）', version: '2.0.0', contract: 1, extends: nil,
                              styles: %w[simple-header.css image-header.css], tokens: {}, warnings: [] }
        end
        assert_nil theme.base
        assert_equal({ writing_mode: %i[horizontal], layout: %i[reflowable], targets: %i[pdf print_pdf epub kindle] },
                     theme.supports)
        # 出力先の CSS は、選択子が vs-header-* を含む規則（S6-6 で stylesheets/targets/ から移した）
        assert_equal %w[themes/standard/epub.css], theme.target_files('chapter', :epub)
        assert_equal %w[themes/standard/epub.css themes/standard/kindle.css], theme.target_files('index', :kindle)
      end

      # 配色のテーマが組版のテーマを土台にする形（theme-contract-spec.md §3.2）
      def test_should_read_the_base_theme_first_and_let_the_own_tokens_win
        with_book do |root|
          write_theme(root, 'base', { 'styles' => %w[head.css body.css],
                                      'tokens' => { 'color-accent' => '#111', 'color-link' => '#222' },
                                      'supports' => { 'writing_mode' => %w[horizontal vertical] } },
                      %w[head.css body.css epub.css kindle-chapter.css])
          write_theme(root, 'mono', { 'extends' => 'base', 'styles' => %w[mono.css],
                                      'tokens' => { 'color-accent' => '#555' } },
                      %w[mono.css epub-chapter.css kindle.css])

          theme = Theme.resolve('mono', root:)

          assert_equal %w[base mono], theme.chain.map(&:name)
          assert_equal %w[themes/base/head.css themes/base/body.css themes/mono/mono.css], theme.styles
          assert_equal({ 'color-accent' => '#555', 'color-link' => '#222' }, theme.tokens)
          assert_equal %w[themes/base/epub.css themes/mono/epub-chapter.css], theme.target_files('chapter', :epub)
          assert_equal %w[themes/base/epub.css themes/base/kindle-chapter.css themes/mono/epub-chapter.css
                          themes/mono/kindle.css],
                       theme.target_files('chapter', :kindle)
          assert_equal %w[themes/base/epub.css themes/mono/kindle.css], theme.target_files('index', :kindle)
          assert_empty theme.target_files('chapter', nil), 'PDF は出力先の CSS を読まない'
          assert_equal %i[horizontal vertical], theme.supports[:writing_mode], '書いていない軸は土台から'
          assert_equal %i[reflowable], theme.supports[:layout], '土台も書いていなければ既定'
        end
      end

      def test_should_allow_only_one_level_of_extends
        with_book do |root|
          write_theme(root, 'root-theme')
          write_theme(root, 'middle', { 'extends' => 'root-theme' })
          write_theme(root, 'leaf', { 'extends' => 'middle' })

          error = assert_raises(Theme::Error) { Theme.resolve('leaf', root:) }
          assert_equal 'テーマ leaf の土台 middle が、さらに extends: root-theme を持っています', error.message
          assert_includes error.detail, 'extends: は 1 段だけです'
        end
      end

      def test_should_report_a_missing_base_theme
        with_book do |root|
          write_theme(root, 'mono', { 'extends' => 'standard' })

          error = assert_raises(Theme::Error) { Theme.resolve('mono', root:) }
          assert_equal 'themes/mono/theme.yml の extends: のテーマ standard が、本の themes/ にありません', error.message
          assert_equal '本にあるテーマ: mono（themes/mono/theme.yml の extends: に書きます）', error.detail
        end
      end

      # 名前はディレクトリの名前に使う。パスの区切りを含む名前は、探す前に誤りにする
      def test_should_not_look_outside_the_themes_directory
        with_book do |root|
          error = assert_raises(Theme::Error) { Theme.resolve('../config', root:) }
          assert_includes error.message, '本の themes/ にありません'
          assert_equal 'themes/../config/theme.yml を置いてください', error.detail
        end
      end

      def test_should_reject_broken_manifests
        with_book do |root|
          {
            { 'name' => 'other' } => 'name: が、ディレクトリの名前と違います',
            { 'contract' => nil } => '契約の版（contract:）が書かれていません',
            { 'styles' => %w[../../stylesheets/custom.css] } => 'テーマの中の CSS でないものが書かれています',
            { 'styles' => %w[missing.css] } => 'styles: のファイルがありません: missing.css',
            { 'tokens' => { 'color-accent' => 'red; } body { color: blue' } } => 'tokens.color-accent の値を CSS に書き出せません',
            { 'tokens' => { '--book-color-accent' => 'red' } } => '--book- を除いた名前で書いてください',
            { 'supports' => { 'writing_mode' => %w[diagonal] } } => 'supports.writing_mode に、知らない値か空の並び'
          }.each do |extra, expected|
            write_theme(root, 'broken', extra)

            error = assert_raises(Theme::Error, extra.inspect) { Theme.resolve('broken', root:) }
            assert_includes error.message, expected
          end
        end
      end

      def test_should_check_the_contract_and_the_required_vs_version
        with_book do |root|
          write_theme(root, 'old', { 'contract' => 0 })
          write_theme(root, 'later', { 'requires_vs' => '>= 2.1' })
          write_theme(root, 'odd', { 'requires_vs' => 'two point one' })

          old = assert_raises(Theme::Error) { Theme.resolve('old', root:) }
          assert_equal ['この vs が読める契約の版: 1', '契約の版 1 に対応した版のテーマに入れ替えてください'], old.detail

          later = Theme::Manifest.load('themes/later', root:)
          error = assert_raises(Theme::Error) { Theme::Contract.check!(later, vs_version: '2.0.0') }
          assert_equal 'テーマ later は vs >= 2.1 を前提にしています（この vs は 2.0.0）', error.message
          Theme::Contract.check!(later, vs_version: '2.1.0')

          odd = Theme::Manifest.load('themes/odd', root:)
          error = assert_raises(Theme::Error) { Theme::Contract.check!(odd, vs_version: '2.1.0') }
          assert_includes error.message, 'requires_vs: を読めません'
        end
      end

      # 読めないテーマは nil（入口の検査が 🔴 で示す）。設定と作業ディレクトリが同じ間は読み直さない
      def test_should_select_the_configured_theme_or_nil
        with_book do |root|
          write_theme(root, 'mono')
          Dir.chdir(root) do
            config = Common.wrap_config({ theme: { name: 'mono' } })

            assert_equal 'mono', Theme.selected(config).name
            assert_same Theme.selected(config), Theme.selected(config)
            assert_nil Theme.selected(Common.wrap_config({ theme: { name: 'missing' } }))
            assert_nil Theme.selected(nil)
            assert_equal 'standard', Theme.selected_name(Common.wrap_config({ theme: { name: ' ' } }))
          end
        end
      end

      private

      def with_book(&) = Dir.mktmpdir('vs-theme', &)

      # @param extra [Hash] theme.yml に足す（上書きする）キー。値が nil のキーは書かない
      # @param files [Array<String>] テーマのディレクトリに置く空の CSS
      def write_theme(root, name, extra = {}, files = [])
        dir = File.join(root, 'themes', name)
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        manifest = { 'name' => name, 'contract' => 1 }.merge(extra).compact
        File.write(File.join(dir, 'theme.yml'), manifest.to_yaml)
        files.each { File.write(File.join(dir, it), "/* #{it} */\n") }
      end
    end
  end
end
