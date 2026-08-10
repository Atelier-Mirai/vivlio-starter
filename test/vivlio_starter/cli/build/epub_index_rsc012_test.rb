# frozen_string_literal: true

# ================================================================
# Test: build/epub_index_rsc012_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder の索引・用語集 EPUB 後処理における RSC-012 恒常対策
#   （epub-kindle-target-split-spec.md 付録 A-2 / KNOWN_ISSUES.md）。
#
#   epubcheck の RSC-012（「フラグメント識別子が定義されていません」）は、
#   索引リンク（#idx-…）・用語集バックリンク（#gls-src-…）が当該 EPUB に
#   存在しない id を指すと発生する。post_process_index_glossary_for_epub! は
#   全 HTML から実在 id を収集し、参照先 id が無いリンクを素のテキストへ
#   フォールバック（リンク解除）して RSC-012 を恒常的に出さないことを検査する。
#
#   加えて、そもそもアンカーを消さないための手当て（apply_image_heading! が
#   見出し・章リードの索引アンカーを空 span として残すこと）も検査する。
#   リンク解除は最後の砦で、解除されたぶん索引は行き先を失う——主要参照が
#   落ちると索引の値そのものが下がるため、消さない側が本筋。
#
#   なお「収集を最後に走らせる」順序そのものは実ビルドでしか担保できないため、
#   release/epub_validation_test.rb（EP-02・epubcheck）が受け持つ。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/build/epub_builder'

module VivlioStarter
  module CLI
    class EpubIndexRsc012Test < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action log_summary].freeze

      def setup
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
        @dir = Dir.mktmpdir('rsc012')
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
        FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
      end

      # 実在しない索引リンク（#idx-…）は解除され、実在リンクは章番号付きで残る
      def test_index_unlinks_missing_fragment_and_keeps_existing
        write_file('00-preface.html', <<~HTML)
          <html><body><p><dfn id="idx-aaa-1" class="index-term">用語A</dfn></p></body></html>
        HTML
        write_file('11-basics.html', <<~HTML)
          <html><body><p><span id="idx-bbb-1" class="index-term">用語B</span></p></body></html>
        HTML
        # 用語A: 実在(00) ＋ 実在しない(11) の 2 リンク／用語B: 実在(11) の 1 リンク
        index_path = write_file('_indexpage.html', <<~HTML)
          <section class="index">
          <dl class="index-list">
          <dt>用語A</dt><dd><a href="00-preface.html#idx-aaa-1"></a><a href="11-basics.html#idx-missing-9"></a></dd>
          <dt>用語B</dt><dd><a href="11-basics.html#idx-bbb-1"></a></dd>
          </dl>
          </section>
        HTML

        Builder.post_process_index_glossary_for_epub!(html_files)
        result = File.read(index_path, encoding: 'utf-8')

        refute_includes result, 'idx-missing-9', '実在しない索引リンクは解除され href から消える'
        assert_includes result, 'href="00-preface.html#idx-aaa-1"', '実在する索引リンクは残る'
        assert_includes result, 'href="11-basics.html#idx-bbb-1"', '実在する索引リンクは残る'
        # 残ったリンクは連番章番号（00→0, 11→1）が挿入される
        assert_match(%r{<a href="00-preface.html#idx-aaa-1">0</a>}, result, '実在リンクに連番章番号が入る')
        assert_match(%r{<a href="11-basics.html#idx-bbb-1">1</a>}, result, '実在リンクに連番章番号が入る')
      end

      # コード例として本文に載ったエスケープ済み id（&lt;span id="…"&gt;）は実在 id と見なさず、
      # それを指す索引リンクは解除される（実 DOM を見ない正規表現収集の偽陽性回帰・本番 RSC-012 残存の真因）
      def test_index_unlinks_link_to_escaped_id_in_code
        # idx-eee-1 は実要素ではなく、コードブロック内のエスケープテキストとしてのみ存在する
        write_file('22-extentions.html', <<~HTML)
          <html><body>
          <pre><code>puts "Hello" # &lt;span id="idx-eee-1" class="index-term"&gt;用語E&lt;/span&gt;</code></pre>
          </body></html>
        HTML
        index_path = write_file('_indexpage.html', <<~HTML)
          <section class="index">
          <dl class="index-list">
          <dt>用語E</dt><dd><a href="22-extentions.html#idx-eee-1"></a></dd>
          </dl>
          </section>
        HTML

        Builder.post_process_index_glossary_for_epub!(html_files)
        result = File.read(index_path, encoding: 'utf-8')

        refute_includes result, 'href="22-extentions.html#idx-eee-1"',
                        'エスケープ済みコード内の id を指す索引リンクは実在しない扱いで解除される'
      end

      # 実在しない用語集バックリンク（#gls-src-…）も解除される
      def test_glossary_unlinks_missing_backlink
        write_file('11-basics.html', <<~HTML)
          <html><body><p><a id="gls-src-11-basics-foo-1" class="glossary-link" href="_glossarypage.html#gls-foo"><sup>†</sup></a></p></body></html>
        HTML
        glossary_path = write_file('_glossarypage.html', <<~HTML)
          <section class="glossarypage">
          <dl class="glossary-list">
          <div class="glossary-group-header" role="heading" aria-level="2">F</div>
          <dt id="gls-foo" class="glossary-term">foo</dt>
          <dd class="glossary-definition"><p class="glossary-backlinks"><a href="11-basics.html#gls-src-11-basics-foo-1" class="glossary-backlink"></a> <a href="11-basics.html#gls-src-11-basics-foo-99" class="glossary-backlink"></a></p></dd>
          </dl>
          </section>
        HTML

        Builder.post_process_index_glossary_for_epub!(html_files)
        result = File.read(glossary_path, encoding: 'utf-8')

        refute_includes result, 'gls-src-11-basics-foo-99', '実在しないバックリンクは解除される'
        assert_includes result, 'href="11-basics.html#gls-src-11-basics-foo-1"', '実在するバックリンクは残る'
      end

      # href のフラグメントは URL エンコードされるが id 属性は素の UTF-8。素で突き合わせると
      # CJK を含むアンカーが必ず不一致になり、実在するリンクまで解除してしまう。
      def test_should_keep_link_whose_fragment_is_percent_encoded
        write_file('31-lint.html', <<~HTML)
          <html><body><p><a id="gls-src-31-lint-css組版-1" class="glossary-link" href="_glossarypage.html#gls-css組版"><sup>†</sup></a></p></body></html>
        HTML
        glossary_path = write_file('_glossarypage.html', <<~HTML)
          <section class="glossarypage">
          <dl class="glossary-list">
          <dt id="gls-css組版" class="glossary-term">CSS組版</dt>
          <dd class="glossary-definition"><p class="glossary-backlinks"><a href="31-lint.html#gls-src-31-lint-css%E7%B5%84%E7%89%88-1" class="glossary-backlink"></a></p></dd>
          </dl>
          </section>
        HTML

        Builder.post_process_index_glossary_for_epub!(html_files)
        result = File.read(glossary_path, encoding: 'utf-8')

        assert_includes result, 'gls-src-31-lint-css%E7%B5%84%E7%89%88-1',
                        'エンコードされたフラグメントも実在 id と照合され、リンクは残る'
      end

      # 見出しの中身は合成画像へ置き換わるが、索引・用語集のアンカーは空 span として残す。
      # 索引はこの id を行き先にしているので、要素ごと消すと行き先の無いリンクになり
      # RSC-012 になる。主要参照は「章題にしか無い語はその章題を指すほかない」の分岐で
      # 章題・章リードへ着地しやすく、実測では 89 件中 27 件がここで消えていた。
      def test_should_keep_index_anchors_when_heading_becomes_an_image
        doc = PostProcessCommands::HtmlParser.parse_html_document(<<~HTML)
          <html><body>
          <h1 id="build" data-chapter-title="ビルド"><dfn id="idx-amazon-3" class="index-term">Amazon</dfn> のビルド</h1>
          <div class="chapter-lead"><p><span id="idx-kindle-7" class="index-term">Kindle</span> 用<a id="fnref9" href="#fn9">9</a></p></div>
          </body></html>
        HTML
        h1 = doc.css('h1').first
        lead = doc.css('.chapter-lead').first

        Builder.apply_image_heading!(h1, 'images/headings/x.svg', %w[第14章 ビルド], doc, also_from: lead)

        assert_equal 1, h1.css('img').size, '見出しの中身は合成画像 1 枚になる'
        assert_equal '第14章 ビルド', h1.css('img').first['alt'], '見出しテキストは alt へ格納される'
        assert_equal %w[idx-amazon-3 idx-kindle-7], h1.css('span.vs-epub-anchor').map { it['id'] },
                     '見出しと章リードの索引アンカーが空 span として残る'
        assert_empty h1.css('#fnref9'),
                     '索引・用語集以外の id は復活させない（別フェーズが意図して外した id と競合するため）'
      end

      private

      def write_file(name, content)
        path = File.join(@dir, name)
        File.write(path, content, encoding: 'utf-8')
        path
      end

      # @dir 直下の全 HTML を書籍構成順（番号昇順 → 索引・用語集）で返す
      def html_files
        Dir.glob(File.join(@dir, '*.html')).sort
      end
    end
  end
end
