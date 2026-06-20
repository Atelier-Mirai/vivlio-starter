# frozen_string_literal: true

# ================================================================
# Test: build/epub_flavor_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder のフレーバ分岐（epub-kindle-target-split-spec.md §5-1）
#   - generate_epub_entries!(flavor: :epub)   … Kindle 専用 rewrite を行わない（クリーン）
#   - generate_epub_entries!(flavor: :kindle) … 全 rewrite を行う（劣化）
#   - generate_epub_config!(flavor: :kindle)  … 表紙を embed しない（§1-6）
#   - convert_epub_to_kpf!                     … kindlepreviewer 未導入時は graceful skip（DI）
#   - 出力ファイル名                           … kindle → .kpf / 中間 -kindle.epub
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'nokogiri'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/build/epub_builder'

module VivlioStarter
  module CLI
    class EpubFlavorTest < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action log_summary].freeze

      # Kindle 専用 rewrite を一通り誘発する章 HTML（コラム枠・行番号コード・ex 数式）。
      # WebP は外部ツール（magick）依存になるため意図的に含めない。
      FIXTURE_HTML = <<~HTML
        <html><body class="chapter">
        <div class="tip"><p>ヒント本文</p></div>
        <pre class="language-ruby line-numbers"><code class="language-ruby line-numbers">x = 1<span class="line-numbers-rows" aria-hidden="true"><span></span></span></code></pre>
        <p><img class="vs-math vs-math-inline" src="images/math/a.svg" style="height: 1.4ex; width: 1.4ex;" alt="A"></p>
        </body></html>
      HTML

      def setup
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
      end

      # クリーン EPUB（:epub）は Kindle 専用 rewrite を一切行わない
      def test_epub_flavor_keeps_chapter_clean
        doc = build_entries_and_parse(:epub)

        refute_includes doc.at_css('body')['class'].to_s.split, 'vs-kindle',
                        'クリーン EPUB に vs-kindle マーカーは付かない'
        refute_nil doc.at_css('pre.line-numbers'), 'コードはテーブル化されない（pre.line-numbers が残る）'
        assert_nil doc.at_css('table.vs-code-epub'), 'コードテーブルは生成されない'
        assert_includes doc.at_css('img.vs-math-inline')['style'], 'ex', '数式の ex 単位は変換されない'
        assert_nil doc.at_css('.vs-adm-label'), 'admonition ラベルは注入されない'
      end

      # Kindle EPUB（:kindle）は全 rewrite を行う
      def test_kindle_flavor_applies_all_rewrites
        doc = build_entries_and_parse(:kindle)

        assert_includes doc.at_css('body')['class'].to_s.split, 'vs-kindle',
                        'Kindle EPUB に vs-kindle マーカーが付く'
        refute_nil doc.at_css('table.vs-code-epub'), 'コードは 2 列テーブルへ変換される'
        assert_nil doc.at_css('pre.line-numbers'), '元の pre.line-numbers は残らない'
        style = doc.at_css('img.vs-math-inline')['style']
        refute_includes style, 'ex', '数式の ex は em へ変換される'
        assert_includes style, 'em'
        assert_equal '【TIP】', doc.at_css('.tip > .vs-adm-label')&.text, 'admonition ラベルが注入される'
      end

      # 両フレーバとも body に vs-epub マーカーが付く（§6 A案・EPUB リフロー文脈の足場）。
      # Kindle のみ vs-kindle も追加される。
      def test_both_flavors_get_vs_epub_marker
        clean = build_entries_and_parse(:epub)
        assert_includes clean.at_css('body')['class'].to_s.split, 'vs-epub',
                        'クリーン EPUB にも vs-epub マーカーが付く'
        refute_includes clean.at_css('body')['class'].to_s.split, 'vs-kindle'

        kindle = build_entries_and_parse(:kindle)
        kindle_classes = kindle.at_css('body')['class'].to_s.split
        assert_includes kindle_classes, 'vs-epub', 'Kindle EPUB にも vs-epub が付く（基底マーカー）'
        assert_includes kindle_classes, 'vs-kindle', 'Kindle EPUB には vs-kindle も付く'
      end

      # Kindle config は表紙を埋め込まない（§1-6・二重表紙回避）
      def test_kindle_config_disables_cover_embed
        Dir.mktmpdir('vs-epub-config') do |dir|
          Dir.chdir(dir) do
            content = File.read(Builder.generate_epub_config!(flavor: :kindle))
            assert_includes content, 'kindle.embed: false', 'kindle は cover 非埋め込みのコメントを出す'
            refute_match(/^\s*cover: '/, content, 'kindle は cover: 行を出力しない')
          end
        end
      end

      # kindlepreviewer 未導入時は KPF 変換をスキップして false を返す（例外を出さない・DI）
      def test_kpf_conversion_skips_gracefully_when_previewer_missing
        Dir.mktmpdir('vs-kpf-skip') do |dir|
          epub = File.join(dir, 'book-kindle.epub')
          kpf  = File.join(dir, 'book.kpf')
          File.write(epub, 'dummy')

          result = Builder.convert_epub_to_kpf!(epub, kpf, command: 'vs-no-such-previewer-xyz')

          assert_equal false, result, '未導入時は false を返す'
          refute File.exist?(kpf), 'KPF は生成されない'
          assert File.exist?(epub), '中間 EPUB は残す（手動変換のため）'
        end
      end

      # kindlepreviewer_available? は存在しないコマンドに false を返す（DI 用の存在チェック）
      def test_kindlepreviewer_available_is_false_for_missing_command
        refute Builder.kindlepreviewer_available?('vs-no-such-previewer-xyz')
      end

      # 出力ファイル名: kindle → .kpf、中間は -kindle.epub
      def test_kindle_output_filenames
        assert_equal '.kpf', File.extname(Common.generate_output_filename('kindle'))
        assert_equal Common.generate_output_filename('kindle'), Common.generate_kpf_filename
        assert_match(/-kindle\.epub\z/, Common.generate_kindle_epub_filename)
      end

      private

      # FIXTURE_HTML を 1 章として generate_epub_entries! にかけ、結果 DOM を返す。
      # collect_epub_htmls と inject_heading_images_for_epub! は環境依存（章収集・theme.css）を
      # 避けるためスタブし、フレーバ分岐そのものだけを検証する。
      def build_entries_and_parse(flavor)
        Dir.mktmpdir('vs-epub-flavor') do |dir|
          path = File.join(dir, '11-sample.html')
          File.write(path, FIXTURE_HTML, encoding: 'utf-8')

          Builder.stub(:collect_epub_htmls, ->(_base, _entries) { [path] }) do
            Builder.stub(:inject_heading_images_for_epub!, ->(files, **) { files }) do
              Builder.generate_epub_entries!(dir, [], flavor:)
            end
          end

          return Nokogiri::HTML5(File.read(path, encoding: 'utf-8'))
        end
      end
    end
  end
end
