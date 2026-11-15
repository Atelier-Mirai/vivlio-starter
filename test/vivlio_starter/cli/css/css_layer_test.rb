# frozen_string_literal: true

# ================================================================
# Test: css/css_layer_test.rb
# ================================================================
# テスト対象:
#   同梱の CSS（stylesheets/ と themes/）が、層で優先を決める設計の決まりを守っていること
#   （css-layer-restructure-spec.md §2.4・§4.3）。
#
# 検証方法:
#   ファイルを読み、コメントを外した宣言の中に `!important` が無いことを見る。
#   層の中の !important は層の順を逆にする（前の層が後の層に勝つ）ので、vs とテーマの CSS では
#   使わない。著者の custom.css は層の外にあり、今と同じに働くので対象にしない（§7.1）。
#   EPUB・Kindle の束を平らにして、層を外すと勝ち負けが変わる組（Css::InversionCheck の静的な
#   判定）が許可の表の外に無いことを見る。これは早めの警報で、保証は組み上がった HTML での
#   要素ごとの判定が行う（ビルドの --log=debug。v2-flat-cascade-consultation.md §5.4）。
#   book-settings*.css は本の設定から生成されるので含めない。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'nokogiri'
require 'vivlio_starter/cli/css/bundle'

module VivlioStarter
  module CLI
    module Css
      class CssLayerTest < Minitest::Test
        ROOT = File.expand_path('../../../..', __dir__)
        AUTHOR_FILES = %w[stylesheets/custom.css].freeze

        # 層を外すと勝ち負けが変わるが、直さない組（css-layer-restructure-spec.md §4.3 の許可の表）。
        # upper は層ありで勝つ規則の選択子、lower は平らな CSS で勝つ規則の選択子に当てる。
        ALLOWED_INVERSIONS = [
          { upper: /\A\.glossary-link sup\z/, lower: /code\[class\*="language-"\] \*\z/,
            reason: '用語集の印はコードの中に付かない（索引語の走査がコードを外す・IndexMatchScanner）' },
          { upper: /\Abody\z/, lower: /code\[class\*="language-"\] \*\z/,
            reason: 'body はコードの中の要素にならない（対象の判定が祖先を見ないための挙がり）' },
          { upper: /\A\.text-(?:left|right) p\z/, lower: /\Abody:not\(\.appendix\) p:has\(/,
            reason: '表の題の段落を .text-* で囲む形。EPUB では 1.x と同じく中央になる。KFX は :has() の規則を捨てる' },
          # 以下は S3-2 で出力先の規則を target 層へ移して挙がるようになった組。平らな CSS での並びと
          # 詳細度は移す前と同じなので、EPUB と Kindle の結果は移す前と変わらない
          { upper: /\Abody(?:\.vs-header-simple)?\.vs-kindle h[12]\z/, lower: /code\[class\*="language-"\] \*\z/,
            reason: '見出しはコードの中の要素にならない' },
          { upper: /\Abody\.vs-kindle h1\z/, lower: /\A\.(?:output|text-table-body|table-text-body) > :last-child\z/,
            reason: '前書きの h1 は題で、囲みや並べ方の中に置かない（targets/kindle-preface.css）' },
          { upper: /\Abody\.vs-kindle \.(?:img-text\d?|text\d?-img|sideimage(?:-left|-right)?) > figure\z/,
            lower: /\A\.pictures > figure:not\(/,
            reason: '写真の列（.pictures）と横並べ（.img-text・.sideimage など）は同じ箱に付けない' },
          { upper: /\Abody\.vs-(?:epub|kindle) \.side-by-side > \*\z/, lower: /\Abody\.vs-header-image \.section-topic h2\z/,
            reason: '節の見出しは .section-topic の中にあり、.side-by-side の子にならない' },
          { upper: /\Abody\.vs-(?:epub|kindle) \.side-by-side > \*\z/, lower: /p:has\(> strong:only-child\):has\(\+ table\)\z/,
            reason: '表の題の段落を .side-by-side に直に置く形。EPUB では移す前と同じく :has() の規則が勝つ。' \
                    'KFX は :has() の規則を捨てる' }
        ].freeze

        def test_should_not_use_important_in_bundled_stylesheets
          files = bundled_css_files
          refute_empty files, 'stylesheets/ の CSS が見つからない'

          offenders = files.flat_map do |path|
            important_lines(File.read(path, encoding: 'utf-8')).map { "#{relative(path)}:#{it}" }
          end
          assert_empty offenders, "層の中では !important を使わない（css-layer-restructure-spec.md §2.4）:\n" \
                                  "#{offenders.join("\n")}"
        end

        # 出力先の規則（body.vs-epub・body.vs-kindle）は stylesheets/targets/ にだけ置く。PDF は target 層を
        # 読まないので、出力先の規則が PDF の束に入らない（css-layer-restructure-spec.md §5・§8 の S3-2 (a)）
        def test_should_keep_target_rules_in_targets
          offenders = bundled_css_files.reject { relative(it).start_with?('stylesheets/targets/') }.flat_map do |path|
            selectors(Crass.parse(File.read(path, encoding: 'utf-8')))
              .grep(/vs-(?:epub|kindle)/).map { "#{relative(path)}: #{it}" }
          end

          assert_empty offenders, "出力先の規則は stylesheets/targets/ に置く:\n#{offenders.join("\n")}"
        end

        # 検査が空振りしないこと（コメントの中は数えず、宣言の中は数える）
        def test_should_find_important_only_outside_comments
          css = <<~CSS
            /* 以前は !important で打ち消していた */
            .a { color: red; }
            .b {
              display: none ! important;
            }
          CSS

          assert_equal [4], important_lines(css)
        end

        # 平らな CSS（EPUB・Kindle）で、層ありと勝ち負けが変わる組が、許可の表の外に無いこと
        def test_should_keep_cascade_when_layers_are_removed
          unexpected = []
          Dir.mktmpdir('vs-css-inversion') do |tmp|
            Dir.chdir(ROOT) do
              %i[epub kindle].product(EntryWriter::IMPORTS.keys).each do |target, kind|
                pieces = Bundle.flat_pieces(kind, target:, dest: File.join(tmp, 'styles', "#{kind}.css"),
                                                  package_root: tmp, embed_fonts: false)
                bundled = pieces.reject do
                  it.source.end_with?(EntryWriter::BOOK_SETTINGS, EntryWriter::BOOK_SETTINGS_KINDLE, 'custom.css')
                end
                InversionCheck.pairs(bundled).each do |pair|
                  next if allowed?(pair)

                  unexpected << "#{kind}（#{target}）: #{InversionCheck.describe(pair)}"
                end
              end
            end
          end

          assert_empty unexpected.uniq, "層を外すと勝ち負けが変わる組（直し方は css-layer-restructure-spec.md §4.3）:\n" \
                                        "#{unexpected.uniq.join("\n")}"
        end

        # 検査が空振りしないこと（下の層の詳細度の高い規則が、上の層の規則と同じ要素を取り合う）
        def test_should_report_inversion_between_layers
          css = <<~CSS
            @layer parts, utilities;
            @layer parts { .box p { text-align: center; } .box p.note { color: red; } }
            @layer utilities { p { text-align: right; } .note { color: blue; } .other { color: green; } }
          CSS

          pieces = Flattener.pieces(File.join(ROOT, 'entry.css'), rebase: ->(path) { path }, css:)
          pairs = InversionCheck.pairs(pieces).map { [it.upper.selector, it.lower.selector] }

          assert_includes pairs, ['p', '.box p'], 'クラスを持たない同じ要素名の組'
          assert_includes pairs, ['.note', '.box p.note'], '同じクラスを含む組'
          refute_includes pairs, ['.other', '.box p.note'], 'クラスの違う組は挙げない'
        end

        # 要素ごとの判定（v2-flat-cascade-consultation.md §5.4）: 組み上がった HTML の要素で、
        # 層ありで勝つ宣言と平らな CSS で勝つ宣言を比べる。どちらの形でも勝つ第三の宣言があれば
        # 挙げない（部扉の break-before と同じ形。同 §5.2）。違う媒体の宣言どうしは取り合わない
        def test_should_compare_winners_per_element
          css = <<~CSS
            @layer parts, pages, settings;
            @layer parts { .box p { text-align: center; } @media screen { .box p { color: red; } } }
            @layer pages { .part-title { break-before: recto; } }
            @layer settings {
              p { text-align: right; }
              @media print { p { color: blue; } }
              body, .part-title { break-before: page; }
            }
          CSS
          html = '<html><body class="part-title"><div class="box"><p>本文</p></div></body></html>'

          pieces = Flattener.pieces(File.join(ROOT, 'entry.css'), rebase: ->(path) { path }, css:)
          pairs, unreadable = InversionCheck.inversions(pieces, [Nokogiri::HTML5(html)])
          found = pairs.map { [it.longhand, it.upper.selector, it.lower.selector] }

          assert_equal [['text-align', 'p', '.box p']], found
          refute(InversionCheck.pairs(pieces, wide: true).none? { it.lower.selector == '.part-title' },
                 '組で比べると部扉の組が挙がる（要素ごとに比べると挙がらない）')
          assert_empty unreadable
        end

        private

        def allowed?(pair)
          ALLOWED_INVERSIONS.any? { pair.upper.selector.match?(it[:upper]) && pair.lower.selector.match?(it[:lower]) }
        end


        def bundled_css_files
          Dir.glob(File.join(ROOT, '{stylesheets,themes}', '**', '*.css'))
             .reject { AUTHOR_FILES.include?(relative(it)) }
             .sort
        end

        # !important を含む行の番号（1 始まり）。コメントは同じ行数の空白に置き換えて外す
        def important_lines(css)
          stripped = css.gsub(%r{/\*.*?\*/}m) { it.gsub(/[^\n]/, ' ') }
          stripped.each_line.with_index(1).filter_map { |line, number| number if line.match?(/!\s*important/i) }
        end

        def relative(path) = path.delete_prefix("#{ROOT}/")

        # 規則の選択子の列（@media・@supports の中も見る）
        def selectors(nodes)
          nodes.flat_map do |node|
            case node
            in { node: :style_rule, selector: { value: } } then [value.gsub(/\s+/, ' ').strip]
            in { node: :at_rule, block: Array => block } then selectors(Crass::Parser.parse_rules(block))
            else []
            end
          end
        end
      end
    end
  end
end
