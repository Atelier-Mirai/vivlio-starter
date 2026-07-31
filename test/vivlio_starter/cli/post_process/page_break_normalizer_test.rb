# frozen_string_literal: true

# ================================================================
# Test: page_break_normalizer_test.rb
# ================================================================
# 検証内容（page-break-control-spec.md §2.1 / §3-1）:
#   - 改ページマーカーの直後が h2 なら二重改ページを解消する
#     （VFM の section.level2 ／ image スタイルの article.section-topic の両構造で）
#   - h2 以外（p / h3 / figure）が続く正当な改ページは触らない
#   - `--- ---` の連打（意図的な空白ページ）は h2 直前の 1 個だけを正規化する
#   - :recto / :verso はマーカーを残し h2 側を無効化する（recto 指定が勝つ）
#   - page.section_pagebreak: false では一切正規化しない
#     （ただし image スタイルは章扉保護で章の最初の節だけ改ページが残るため、そこは正規化する）
# ================================================================

require_relative '../../../test_helper'
require 'tempfile'
require 'vivlio_starter/cli/loader'

class PageBreakNormalizerTest < Minitest::Test
  PBN = VivlioStarter::CLI::PostProcessCommands::PageBreakNormalizer

  # HTML を一時ファイルへ書いて正規化し、[結果 HTML, 件数] を返す。
  #
  # 節の改ページ設定は明示的に与える。プロジェクト自身の book.yml を読ませると、
  # 著者が page.section_pagebreak を false にした瞬間にテストが落ちる
  # （正規化は h2 が改ページする前提でのみ働くため）。
  # body クラスは CSS が実際に見る印（vs-header-image / vs-header-simple）。
  # section_pagebreak: false のとき対象範囲がこれで変わる（breaking_h2_scope）。
  def normalize(body, section_pagebreak: true, body_class: nil)
    body_tag = body_class ? %(<body class="#{body_class}">) : '<body>'
    PBN.stub(:section_pagebreak_enabled?, section_pagebreak) do
      Tempfile.create(['vs_pbn_', '.html']) do |f|
        f.write("<html>#{body_tag}\n#{body}\n</body></html>")
        f.flush
        count = PBN.normalize!(f.path)
        return [File.read(f.path, encoding: 'utf-8'), count]
      end
    end
  end

  # VFM の素の構造: hr は前セクション末尾・h2 は次セクション先頭に離れて置かれる
  def sectioned(marker)
    <<~HTML
      <section class="level2">
        <p>前節の本文。</p>
        #{marker}
      </section>
      <section class="level2">
        <h2>次の節</h2>
        <p>本文。</p>
      </section>
    HTML
  end

  # image スタイル: SectionWrapper が h2 を article.section-topic で包む
  def article_wrapped(marker)
    <<~HTML
      <section class="level2">
        <p>前節の本文。</p>
        #{marker}
      </section>
      <section class="level2">
        <article class="section-topic">
          <h2>次の節</h2>
        </article>
        <p>本文。</p>
      </section>
    HTML
  end

  def test_should_remove_hr_pagebreak_before_h2_across_sections
    out, count = normalize(sectioned('<hr class="pagebreak">'))

    assert_equal 1, count
    refute_includes out, 'class="pagebreak"'
    assert_includes out, '<h2>次の節</h2>'
  end

  def test_should_remove_hr_pagebreak_before_article_wrapped_h2
    out, count = normalize(article_wrapped('<hr class="pagebreak">'))

    assert_equal 1, count
    refute_includes out, 'class="pagebreak"'
  end

  def test_should_remove_vs_break_page_before_h2
    out, count = normalize(sectioned('<div class="vs-break-page"></div>'))

    assert_equal 1, count
    refute_includes out, 'vs-break-page'
  end

  # :recto はマーカーを残し、h2 側の改ページだけを無効化する（合流クラス付与）
  def test_should_merge_recto_marker_into_following_h2
    out, count = normalize(sectioned('<div class="vs-break-recto"></div>'))

    assert_equal 1, count
    assert_includes out, 'vs-break-recto'
    assert_match(/<h2 class="vs-break-merged">/, out)
  end

  def test_should_merge_verso_marker_into_following_h2
    out, = normalize(sectioned('<div class="vs-break-verso"></div>'))

    assert_includes out, 'vs-break-verso'
    assert_match(/<h2 class="vs-break-merged">/, out)
  end

  # --- 正規化しないケース ---

  def test_should_keep_pagebreak_before_paragraph
    out, count = normalize(<<~HTML)
      <section class="level2">
        <p>前の本文。</p>
        <hr class="pagebreak">
        <p>次の本文。</p>
      </section>
    HTML

    assert_equal 0, count
    assert_includes out, 'class="pagebreak"'
  end

  def test_should_keep_pagebreak_before_h3
    out, count = normalize(<<~HTML)
      <section class="level2">
        <hr class="pagebreak">
        <h3>小見出し</h3>
      </section>
    HTML

    assert_equal 0, count
    assert_includes out, 'class="pagebreak"'
  end

  def test_should_keep_pagebreak_before_figure
    out, count = normalize(<<~HTML)
      <section class="level2">
        <hr class="pagebreak">
        <figure><img src="a.png" alt=""></figure>
      </section>
    HTML

    assert_equal 0, count
    assert_includes out, 'class="pagebreak"'
  end

  # 意図的な空白ページ（--- 連打）は保存する: h2 直前の 1 個だけが消える
  def test_should_normalize_only_the_marker_adjacent_to_h2
    out, count = normalize(<<~HTML)
      <section class="level2">
        <hr class="pagebreak" id="first">
        <hr class="pagebreak" id="second">
      </section>
      <section class="level2">
        <h2>節</h2>
      </section>
    HTML

    assert_equal 1, count
    assert_includes out, 'id="first"'
    refute_includes out, 'id="second"'
  end

  # page.section_pagebreak: false では h2 が改ページしない＝冗長性が無いので何もしない
  def test_should_do_nothing_when_section_pagebreak_disabled
    out, count = normalize(sectioned('<hr class="pagebreak">'), section_pagebreak: false)

    assert_equal 0, count
    assert_includes out, 'class="pagebreak"'
  end

  # --- section_pagebreak: false ＋ image スタイル（章扉保護）---
  # 節の改ページを止めても、image スタイルの章の最初の節だけは改ページが残る
  # （章扉は全面の扉絵で成立するページなので独立させる）。そこだけは冗長性が生じる。

  # 章（section.level1）配下に h1 と節を並べた image スタイルの構造。
  def chaptered(first_marker:, second_marker:)
    <<~HTML
      <section class="level1">
        <h1>章題</h1>
        #{first_marker}
        <section class="level2">
          <article class="section-topic"><h2>最初の節</h2></article>
          <p>本文。</p>
          #{second_marker}
        </section>
        <section class="level2">
          <article class="section-topic"><h2>次の節</h2></article>
          <p>本文。</p>
        </section>
      </section>
    HTML
  end

  def test_should_normalize_only_the_first_section_marker_when_disabled_in_image_style
    body = chaptered(first_marker: '<hr class="pagebreak" id="before-first">',
                     second_marker: '<hr class="pagebreak" id="before-second">')
    out, count = normalize(body, section_pagebreak: false, body_class: 'chapter vs-header-image')

    assert_equal 1, count
    # 章扉保護で改ページする最初の節 → マーカーは冗長なので落とす
    refute_includes out, 'id="before-first"'
    # 2 つ目以降の節は改ページしない → 著者が書いた改ページとして残す
    assert_includes out, 'id="before-second"'
  end

  # simple スタイルはどの h2 も改ページしないので、章の最初の節でも触らない
  def test_should_keep_all_markers_when_disabled_in_simple_style
    body = chaptered(first_marker: '<hr class="pagebreak" id="before-first">', second_marker: '')
    out, count = normalize(body, section_pagebreak: false, body_class: 'chapter vs-header-simple')

    assert_equal 0, count
    assert_includes out, 'id="before-first"'
  end
end
