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
#   Kindle の束で落ちる宣言（Css::LiteralResolver）が、紙の寸法と許可の表のものだけであることを見る
#   （§4.5）。こちらは、本書の book.yml から作った book-settings.css を入れた束で数える。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'nokogiri'
require 'fileutils'
require 'vivlio_starter/cli/css/bundle'
require 'vivlio_starter/cli/pre_process/book_settings_css'

module VivlioStarter
  module CLI
    module Css
      class CssLayerTest < Minitest::Test
        ROOT = File.expand_path('../../../..', __dir__)
        AUTHOR_FILES = %w[stylesheets/custom.css].freeze

        # 層の中でも使ってよい !important（ファイルと、その行に当てる正規表現と理由）。
        # target 層は PDF の束に入らず平らな CSS でだけ読まれるので、層の順の逆転は起きない
        ALLOWED_IMPORTANT = [
          { file: 'stylesheets/targets/kindle.css', line: /content: var\(--book-marker-h4/,
            reason: 'Kindle の h4 の印。Techbook が HTML の <style> で content を "" !important にしているのに勝つ' }
        ].freeze

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
                    'KFX は :has() の規則を捨てる' },
          # 改善案 #135（1.0.1）の、囲みに .align-* を重ねたときに段落を囲みの組み方へ戻す規則
          { upper: /\A\.text-(?:left|right|center) p\z/,
            lower: /\A\.(?:column|memo|tip|note|notice)\.align-(?:center|right) > p\z/,
            reason: '.align-* を重ねた囲みの段落が .text-* の中にもある形（囲みに .align-* と .text-* を両方付けるか、' \
                    '.text-* の囲いの中に置く）。PDF は .text-* が勝ち、EPUB と Kindle は 1.0.1 と同じく囲みの組み方になる' },
          # 以下は S6-4 で見出しの 2 枚を parts 層から theme 層へ移して挙がるようになった組
          # （theme-contract-spec.md §9 の S6 の決め 1）
          { upper: /\Abody\.vs-header-(?:simple|image) h[12]\z/,
            lower: /\A\.(?:output|text-table-body|table-text-body) > :(?:first|last)-child\z/,
            reason: '章題と節見出しは本文の最上位に書き、囲みや並べ方の中に置かない' },
          { upper: /\Abody\.vs-header-(?:simple|image)(?: \.section-topic)? h[12]\z/, lower: /code\[class\*="language-"\] \*\z/,
            reason: '見出しはコードの中の要素にならない' },
          { upper: /\Abody\.vs-header-image \.section-topic h2 > \*\z/,
            lower: /(?:code\[class\*="language-"\]|p:has\(> strong:only-child\):has\(\+ table\))\z/,
            reason: '節見出しの子は番号と題の span で、コードの図（figure > pre > code）や段落にならない' },
          { upper: /\Abody\.vs-header-(?:simple|image) /, lower: /\A#toc(?:-title::before| li\.)/,
            reason: '目次のページの body には vs-header-* が付かない（BodyClassInjector は章と付録にだけ付ける）' }
        ].freeze

        # Kindle 用の CSS で落ちる宣言のうち、直さないもの（css-layer-restructure-spec.md §4.5 の許可の表）。
        # 紙の寸法（:paper_dimension）は意図した書き方なので載せない。表に無い宣言が落ちたら失敗し、
        # 表の行がどの宣言にも当たらなくなっても失敗する（名前を変えて変数が解けなくなったことを見つけ、
        # 表を古びさせないため）。reason は LiteralResolver::Dropped#reason（配列ならどれか）、file は
        # 宣言のあるファイル、rule は「選択子 { 宣言 }」（:has() で選択子ごと落としたものは選択子だけ）に当てる。
        # KFX は var()・calc()・color-mix()・linear-gradient()・:has() を解さないので（kindle-css-compatibility-notes.md §2）、
        # どの行も、リテラル化を入れる前から Kindle には届いていない
        ALLOWED_KINDLE_DROPS = [
          { reason: :variable, file: 'stylesheets/parts/talk.css', rule: /var\(--book-talk-(?:accent|bg|icon-size|speaker-size)\b/,
            why: '会話の変数は .talk と話者の .talk-c-<key> の上で定義する（要素ごとに値が違う）。Kindle は会話を ' \
                 'inline の形に組み替え、話者の色は book-settings.css が :root の変数で名前・区切り・強調に当てる' },
          { reason: :variable, file: %r{\Astylesheets/pages/(?:colophon|titlepage)\.css\z},
            rule: /\A\.subtitle::(?:before|after) \{ content: var\(--subtitle-(?:prefix|suffix)\) \}\z/,
            why: '副題の飾りは .subtitle と .subtitle--wave などの上で定義する（要素ごとに値が違う）。既定は飾りなし' },
          { reason: :variable, file: 'stylesheets/pages/chapter.css',
            rule: /\A@page \{ background-image: var\(--book-frontispiece-image\) \}\z/,
            why: '扉絵。Kindle には WebP を運ばないので、定義を TargetFilter が落とす。Kindle の章扉は合成した画像になる' },
          { reason: :variable, file: 'themes/standard/image-header.css', rule: /\{ background-image: var\(--book-ornament-image\) \}\z/,
            why: '節絵。扉絵と同じく WebP の定義が落ちる。Kindle の節の見出しは合成した画像になる' },
          { reason: :calc, file: 'stylesheets/pages/chapter.css',
            rule: /\A@page \{ background-size: var\(--book-frontispiece-background-size\) \}\z/,
            why: '扉絵の大きさ（100% から縁の余白を引く。単位が混ざる）。Kindle の章扉は合成した画像になる' },
          { reason: :calc, file: '.cache/vs/book-settings.css', rule: /\A@page \{ background-position: calc\(50% \+ [\d.]+mm\) center \}\z/,
            why: '扉絵を綴じの側へ寄せる量（単位が混ざる）。Kindle の章扉は合成した画像になる' },
          { reason: :calc, file: 'stylesheets/pages/colophon.css', rule: /: calc\((?:50% - 50vw|70vh - 24pt)\) \}\z/,
            why: '奥付の紙面の全幅と、ページの高さに対する位置（単位が混ざる）。Kindle の奥付は targets/kindle-colophon.css が決める' },
          { reason: %i[calc variable], file: 'stylesheets/parts/layout.css', rule: /\A\.pictures > figure \{ flex: /,
            why: '写真の列の幅を画像の数で割る（数は後処理が style 属性に書くので要素ごとに違い、単位も混ざる）。' \
                 'KFX は flex も解さない' },
          { reason: :color_mix, file: 'stylesheets/parts/preface.css',
            rule: /\Ah[23] \{ (?:background: linear-gradient|border-block-end: 1px solid color-mix\(in oklab)/,
            why: '前書きの見出しの地のぼかしと下線（oklab の混色は解かない）。Kindle の前書きの見出しの線は ' \
                 'targets/kindle-preface.css が決める' },
          { reason: :has, file: 'stylesheets/parts/code.css', rule: /\Ah6:has\(\+ pre\)\z/,
            why: 'コードの題（h6）の幅をコードに合わせる。Kindle では題が全幅になる' },
          { reason: :has, file: 'stylesheets/parts/heading.css', rule: /\Asection:has\(hr:last-child\) \+ section > h3:first-child\z/,
            why: '区切り線で改ページした直後の h3 の上の余白を消す（margin-break）。同じ規則のほかの選択子は残る' },
          { reason: :has, file: 'stylesheets/parts/table.css', rule: /\A(?:body:not\(\.appendix\) )?p:has\(> strong:only-child\):has\(\+ table\)/,
            why: '表の直前の太字だけの段落を表の題として組む。Kindle では太字の段落のまま' },
          { reason: :has, file: 'stylesheets/parts/table.css', rule: /\Athead:(?:has|not\(:has)\(/,
            why: '短い表の見出しの行で改ページを避ける・空の見出しの行を隠す' }
        ].freeze

        # Kindle 用 EPUB の body のクラス（本書の B1。書いていない種類は種類の名前だけ）。
        # 変数の表を作る範囲（LiteralResolver.scope_for）を、実際の本と同じにする
        KINDLE_BODY_CLASSES = { 'chapter' => 'chapter vs-header-image', 'appendix' => 'appendix vs-header-simple',
                                'index' => 'index-page', 'glossary' => 'glossary-page' }.freeze

        def test_should_not_use_important_in_bundled_stylesheets
          files = bundled_css_files
          refute_empty files, 'stylesheets/ の CSS が見つからない'

          offenders = files.flat_map do |path|
            lines = File.readlines(path, encoding: 'utf-8')
            important_lines(lines.join).reject { |number| allowed_important?(relative(path), lines[number - 1]) }
                                       .map { "#{relative(path)}:#{it}" }
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
                  it.source.end_with?(EntryWriter::BOOK_SETTINGS, 'custom.css')
                end
                # Kindle が読むのはリテラル化した CSS（:has() の規則は落ちている）
                if target == :kindle
                  bundled = LiteralResolver.resolve(bundled.reject(&:nested), scope: Bundle.kindle_scope([])).pieces
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

        # Kindle 用の CSS で落ちる宣言が、紙の寸法と許可の表のものだけであること。本の設定から作る
        # book-settings.css を入れた束で数える。入れないと、本の設定が定義する変数（扉絵の画像・会話の
        # 話者の色など）を読む宣言まで「解けない」に数え、実際のビルドには無い落ち方が表に載る
        def test_should_drop_only_allowed_declarations_for_kindle
          drops = kindle_drops.reject { |(reason, *), _| reason == :paper_dimension }
          unexpected = drops.reject { |drop, _| ALLOWED_KINDLE_DROPS.any? { allowed_drop?(it, drop) } }
                            .map { |(reason, file, rule), kinds| "#{file}（#{reason}・#{kinds.join('・')}）: #{rule}" }
          unused = ALLOWED_KINDLE_DROPS.reject { |entry| drops.each_key.any? { allowed_drop?(entry, it) } }

          assert_empty unexpected, "Kindle 用の CSS で、許可の表に無い宣言が落ちた（css-layer-restructure-spec.md §4.5）:\n" \
                                   "#{unexpected.join("\n")}"
          assert_empty unused.map { "#{it[:file]}: #{it[:rule].inspect}" },
                       '許可の表に、どの宣言にも当たらない行がある（直ったなら表から消す）'
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

        def allowed_important?(file, line)
          ALLOWED_IMPORTANT.any? { it[:file] == file && line.match?(it[:line]) }
        end

        def allowed?(pair)
          ALLOWED_INVERSIONS.any? { pair.upper.selector.match?(it[:upper]) && pair.lower.selector.match?(it[:lower]) }
        end
        def allowed_drop?(entry, drop)
          reason, file, rule = drop
          Array(entry[:reason]).include?(reason) && (entry[:file] === file) && rule.match?(entry[:rule]) # rubocop:disable Style/CaseEquality
        end

        # 本の写し（stylesheets/ は custom.css を空にして、ほかはリポジトリへの symlink）に、本書の
        # book.yml から作った book-settings.css を置き、ページの種類ごとに Kindle の束を解いて落ちた宣言を集める
        # @return [Hash{Array(Symbol, String, String) => Array<String>}] [理由, ファイル, 規則] → ページの種類
        def kindle_drops
          drops = Hash.new { |hash, key| hash[key] = [] }
          Dir.mktmpdir('vs-kindle-drops') do |tmp|
            dir = File.realpath(tmp)
            stylesheets = File.join(dir, 'stylesheets')
            FileUtils.mkdir_p([stylesheets, File.join(dir, '.cache', 'vs')])
            Dir.children(File.join(ROOT, 'stylesheets')).each do
              File.symlink(File.join(ROOT, 'stylesheets', it), File.join(stylesheets, it)) unless AUTHOR_FILES.include?("stylesheets/#{it}")
            end
            File.write(File.join(stylesheets, 'custom.css'), '')
            # テーマ（standard の見出しの 2 枚）も束に入る
            File.symlink(File.join(ROOT, Theme::DIR), File.join(dir, Theme::DIR))
            File.write(File.join(dir, '.cache', 'vs', EntryWriter::BOOK_SETTINGS), PreProcessCommands::BookSettingsCss.render)
            File.write(File.join(dir, '.cache', 'vs', EntryWriter::BOOK_FONTS), '')
            Dir.chdir(dir) do
              EntryWriter::IMPORTS.each_key do |kind|
                html = File.join(dir, "#{kind}.html")
                File.write(html, %(<html><body class="#{KINDLE_BODY_CLASSES.fetch(kind, kind)}"></body></html>))
                pieces = Bundle.flat_pieces(kind, target: :kindle, dest: File.join(dir, 'styles', "#{kind}.css"),
                                                  package_root: dir, embed_fonts: false)
                LiteralResolver.resolve(pieces.reject(&:nested), scope: Bundle.kindle_scope([html])).dropped.each do |dropped|
                  rule = dropped.declaration ? "#{dropped.selector} { #{dropped.declaration} }" : dropped.selector
                  drops[[dropped.reason, dropped.source.delete_prefix("#{dir}/"), rule]] << kind
                end
              end
            end
          end
          drops
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
