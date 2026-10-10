# frozen_string_literal: true

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # タグの無い PDF の紙面から構造を推定する規則（pdf-read-structure-spec.md の経路 B）を、
    # 座標とフォントを持つ文字を組み立てて確かめる
    class LayoutStructureTest < Minitest::Test
      Glyph = MarkedContentReceiver::Glyph
      FontInfo = MarkedContentReceiver::FontInfo
      ImageBox = MarkedContentReceiver::ImageBox
      # 受け手（MarkedContentReceiver）のうち、経路 B が読むところだけを持つ
      Page = Data.define(:page_glyphs, :page_images, :page_dots, :page_size, :page_rules)

      BODY = FontInfo.new(name: 'Mincho-Regular', bold: false, mono: false)
      GOTHIC = FontInfo.new(name: 'Gothic-Bold', bold: true, mono: false)
      MONO = FontInfo.new(name: 'HackGen-Regular', bold: false, mono: true)
      MATH = FontInfo.new(name: 'CMMI10', bold: false, mono: false)

      # 本文と違う書体で大きい短い行は見出し。大きさの順に段階を振る。本文と同じ書体で少し大きいだけの
      # 行（本のカードの書名）と、4 行以上続く大きな字（章のリード）は段落にする
      def test_should_find_headings_by_size_and_typeface
        lines = [
          text('章の題', y: 780, size: 24, font: GOTHIC),
          text('大きな字のリードです', y: 740, size: 12), text('二行目のリードです', y: 720, size: 12),
          text('三行目のリードです', y: 700, size: 12), text('四行目で終わります。', y: 680, size: 12),
          text('節の題', y: 640, size: 14, font: GOTHIC),
          text('本の書名', y: 610, size: 13),
          *body_paragraph(y: 580), *body_paragraph(y: 540), *body_paragraph(y: 500)
        ]

        markdown = render([lines])

        assert_equal(<<~MARKDOWN, markdown)
          # 章の題

          大きな字のリードです二行目のリードです三行目のリードです四行目で終わります。

          ## 節の題

          本の書名

          本文の一行目は版面の右端まで届きます続きの行で終わります。

          本文の一行目は版面の右端まで届きます続きの行で終わります。

          本文の一行目は版面の右端まで届きます続きの行で終わります。
        MARKDOWN
      end

      # 柱とノンブルは、ページの上下の端で本文から離れ、同じ高さに何ページも出る行として落とす
      def test_should_drop_running_heads_and_page_numbers
        pages = (1..3).map do |number|
          [text('本の題名', y: 810, size: 7), *body_paragraph(y: 700, page: number - 1), text(number.to_s, y: 30, size: 7)]
        end

        markdown = render(pages)

        refute_includes(markdown, '本の題名')
        refute_match(/^\d$/, markdown)
        assert_equal(3, markdown.scan('本文の一行目').size)
      end

      # 1 字下げた行と、版面の右端より手前で止まった行の後で段落を切る
      def test_should_split_paragraphs_by_indent_and_short_line
        lines = [*body_paragraph(y: 700), *body_paragraph(y: 660, first: '次の段落の一行目も右端まで届きます')]

        assert_equal(<<~MARKDOWN, render([lines]))
          本文の一行目は版面の右端まで届きます続きの行で終わります。

          次の段落の一行目も右端まで届きます続きの行で終わります。
        MARKDOWN
      end

      # 目次の項目は、リーダーが右端まで届いても 1 項目ずつ切る（TeX の目次が 2〜3 項目ずつつながっていた）
      def test_should_split_table_of_contents_entries
        lines = [['数の表現', '1', 700], ['ブール代数の基本公式', '20', 683], ['半導体', '24', 666]].map do |title, number, y|
          leader = (((60 + (title.size * 10) + 5) / 5.0).ceil * 5).step(440, 5).flat_map { text('.', x: it, y:) }
          [*text(title, y:), *leader, *text(number, x: 470 - (number.size * 5), y:)]
        end

        assert_equal(<<~MARKDOWN, render([lines]).gsub(/ *(?:\. *){3,}/, ' … '))
          数の表現 … 1

          ブール代数の基本公式 … 20

          半導体 … 24
        MARKDOWN
      end

      # リーダーは半角の中黒（･）の並びや、三点リーダー 1〜2 字（「大事なこと … 16」）のこともある
      def test_should_split_table_of_contents_entries_with_other_leaders
        lines = [['ココロの準備', '･' * 40, '16', 700], ['いちばん大事なこと', '…', '16', 683], ['楽しむために', '……', '19', 666]].map do |title, leader, number, y|
          [*text(title, y:), *text(leader, x: 70 + (title.size * 10), y:), *text(number, x: 470 - (number.size * 5), y:)]
        end

        assert_equal(<<~MARKDOWN, render([lines]).gsub(/ *(?:･ *){3,}| *[…]+ */, ' … '))
          ココロの準備 … 16

          いちばん大事なこと … 16

          楽しむために … 19
        MARKDOWN
      end

      # OCR の字（書体の情報が無い）は字の大きさの見積もりが行ごとに揺れるので、25% までの差では段落を
      # 切らない（「乗客／にとっては」が 7.8pt と 6.2pt に出て切れていた）。文字の層のある PDF の字は、
      # 0.5pt を超える差で切る
      def test_should_tolerate_size_jitter_only_for_ocr_lines
        lines = ->(font) { [text('本文の一行目は版面の右端まで届きます', y: 700, font:, last_x: 470), text('続きの行で終わります。', y: 683, size: 8.4, font:)] }

        assert_equal("本文の一行目は版面の右端まで届きます続きの行で終わります。\n", render([lines.(nil)]))
        assert_equal("本文の一行目は版面の右端まで届きます\n\n続きの行で終わります。\n", render([lines.(BODY)]))
      end

      # OCR の行が版面の右端まで届き、文末で終わらなければ、文の途中の折り返しとみなして、次の行の頭が
      # 下がって見えても段落を切らない（OCR の行頭の位置は揺れる）。文末で終わる行の後と、文字の層の
      # ある PDF の字では、これまでどおり切る
      def test_should_join_ocr_line_wrapped_mid_sentence
        lines = lambda do |font, first|
          [*body_paragraph(y: 740, first: '前の段落の一行目も版面の右端まで届きます'),
           text(first, y: 700, font:, last_x: 470), text('下がって見える続きの行で終わります。', x: 72, y: 683, font:)]
        end

        assert_includes(render([lines.(nil, '本文の一行目は版面の右端まで届いて折り返')]), '届いて折り返下がって見える')
        assert_includes(render([lines.(nil, '本文の一行目は版面の右端まで届きました。')]), "届きました。\n\n下がって見える")
        assert_includes(render([lines.(BODY, '本文の一行目は版面の右端まで届いて折り返')]), "届いて折り返\n\n下がって見える")
      end

      # OCR の表は、行ごとに字の大きさの見積もりが揺れても表に組む。表題の短い行は表に入れない。
      # OCR のページの右端は、長い行の右端がそろう所で決める（右端が揺れて決まらず、表題の行の右端を
      # 本文の右端と取り違えて、表題を「右端まで届いた文の途中の行」とみなし、表とつなげていた）
      def test_should_find_ocr_table_under_short_caption
        cells = [%w[金属 仕事関数 しきい周波数], %w[カリウム 2.2 5.32], %w[ナトリウム 2.3 5.56], %w[金 5.1 1.23]]
        sizes = [10.2, 8.3, 9.5, 9.0]
        rows = cells.each_with_index.map do |(metal, work, frequency), index|
          y = 700 - (index * 18)
          [*text(metal, x: 100, y:, size: sizes[index], font: nil), *text(work, x: 260, y:, size: sizes[index], font: nil),
           *text(frequency, x: 400 + (index * 0.7), y:, size: sizes[index], font: nil)]
        end

        markdown = render([[text('表 H-1: 光電効果のしきい周波数', x: 200, y: 722, font: nil), *rows]])

        assert_includes(markdown, "表 H-1: 光電効果のしきい周波数\n\n")
        assert_includes(markdown, "| 金属 | 仕事関数 | しきい周波数 |\n| --- | --- | --- |\n| カリウム | 2.2 | 5.32 |")
      end

      # OCR のコードは、行番号を読み違えても（字につながる・1 違いにならない）、番号の無い字下げの行や和文の
      # コメント、コードの中の空行をはさんでも、1 つの囲みにする。和文で始まる番号（「1827年」）は行番号ではない。
      # 番号は、欄の位置で外す。欄だけの崩れ（「まき」）は捨て、空行は行の間隔から補い直す
      def test_should_find_ocr_code_with_misread_line_numbers
        # 番号は欄の右端（97pt）にそろえ、コードは 100pt から書く。:glued は番号を字につなげて読んだ行、
        # :gutter は番号の欄を縦に読んだ崩れ
        code = [[:glued, '2#v0 = phi / h', 0], ['3', 'PLANCK = 6.626e-34', 0], ['1', 'EV = 1.602e-19', 0], ['6', 'def threshold(phi)', 1],
                [nil, '  phi * EV / PLANCK', 0], ['9', 'end', 0], [:gutter, 'まき', 0], ['11', '# 代表的な金属', 0],
                ['12', 'metals.each do |metal|', 0], [nil, '  puts metal', 0], ['16', 'end', 0]]
        y = 720.0
        lines = code.map do |number, source, blank|
          y -= 16 * (1 + blank)
          case number
          in :glued then text(source, x: 92, y:, font: nil)
          in :gutter then text(source, x: 88, y: y + 8, size: 5, font: nil)
          else [*(number && text(number, x: 97 - (number.size * 5), y:, font: nil)),
                *text(source.strip, x: 100 + (source[/\A */].size * 5), y:, font: nil)]
          end
        end

        markdown = render([[text('1827年、植物学者ロバート・ブラウンは、花粉から出た微粒子を観察しました。', y: 740, font: nil), *lines,
                            text('各金属のしきい周波数を比較すると次のようになります。', y: y - 30, font: nil)]])

        assert_equal(<<~MARKDOWN, markdown)
          1827年、植物学者ロバート・ブラウンは、花粉から出た微粒子を観察しました。

          ```
          #v0 = phi / h
          PLANCK = 6.626e-34
          EV = 1.602e-19

          def threshold(phi)
            phi * EV / PLANCK
          end

          # 代表的な金属
          metals.each do |metal|
            puts metal
          end
          ```

          各金属のしきい周波数を比較すると次のようになります。
        MARKDOWN
      end

      # ページの頭のファイル名だけの行は、コードの 1 行目が崩れて読めても、行番号を読めなくても、コードの
      # キャプションにする。前のページの末尾の段落にはつなげない。番号の欄を読めないコードでは、コードに
      # つなげて読んだ番号（「2#」）だけが左へ飛び出す。左端はほかの行でそろう位置にし、その番号は外す
      def test_should_attach_ocr_file_name_to_code_below
        code = ['Pb oe', '2# 高速で移動する物体', 'SPEED = 2.99e8', 'def lorentz(v)', '  1.0 / v', 'end']
        lines = code.each_with_index.map do |source, index|
          x = source.start_with?('2#') ? 95 : 100 + (source[/\A */].size * 5)
          text(source.strip, x:, y: 690 - (index * 14), font: nil)
        end
        ocr_paragraph = body_paragraph(y: 700).map { |line| line.map { it.with(font: nil) } }

        markdown = render([ocr_paragraph, [text('time_dilation.rb', x: 84, y: 712, font: nil), *lines]])

        assert_includes(markdown, "続きの行で終わります。\n\n```ruby:time_dilation.rb\nPb oe\n# 高速で移動する物体\n")
        assert_includes(markdown, "def lorentz(v)\n  1.0 / v\nend\n```\n")
      end

      # 番号の後が数と記号だけの行（九九の「3 = 27」）は、頭の数が 1 ずつ増えても行番号とみなさず、コードにしない
      def test_should_not_take_multiplication_table_for_ocr_code
        rows = (1..5).map { |n| [*text(n.to_s, x: 290, y: 600 - (n * 13), font: nil), *text("= #{n * 9}", x: 301, y: 600 - (n * 13), font: nil)] }

        markdown = render([rows])

        refute_includes(markdown, '```')
        assert_match(/\b3\b.*= 27/, markdown) # 表にも組まれうる。頭の数を消さない
      end

      # ページの最後の目次の項目に、次のページの頭の行をつなげない（柱の「CONTENTS」がつながっていた）
      def test_should_not_continue_table_of_contents_entry_on_next_page
        entry = [*text('まとめ', y: 100), *(80.step(440, 5).flat_map { text('.', x: it, y: 100) }), *text('161', x: 455, y: 100)]

        markdown = render([[*body_paragraph(y: 700), entry], [text('次のページの頭の行', y: 780), *body_paragraph(y: 700)]])

        assert_match(/^まとめ[ .]+161\n\n次のページの頭の行/, markdown)
      end

      # 番号の頭（1.）と、行の左に描かれた点（Chrome は • を図形で描く）でリストにする
      def test_should_find_numbered_and_dotted_lists
        lines = [text('1. 一つめ', y: 700), text('2. 二つめ', y: 683), text('点の項目', x: 70, y: 640)]
        dot = ImageBox.new(page: 0, left: 62, bottom: 642, right: 66, top: 646)

        assert_equal("1. 一つめ\n2. 二つめ\n- 点の項目\n", render([lines], dots: [[dot]]))
      end

      # 等幅の書体の行はコード。直前のファイル名だけの行はキャプションにし、字下げは x 座標から戻す
      def test_should_make_code_block_with_file_caption
        lines = [
          text('hello.rb', y: 720, font: GOTHIC),
          text('def hello', y: 705, size: 9, font: MONO),
          text('puts 1', x: 70, y: 692, size: 9, font: MONO),
          text('end', y: 679, size: 9, font: MONO)
        ]

        assert_equal("```ruby:hello.rb\ndef hello\n  puts 1\nend\n```\n", render([lines]))
      end

      # pLaTeX の本のコード。キャプションは「リスト 1.8:」の後のファイル名だけを残し、行番号は「1:」のコロンごと外す。
      # コードの中の和文は和文の書体で描かれるが、行頭の行番号が前後と続くので、その行もコードに含める
      def test_should_read_platex_listing_with_label_and_colon_line_numbers
        japanese_in_code = ->(string, **options) { text(string, font: MONO, **options).map { it.text.match?(StructureMarkdown::WIDE_CHAR) ? it.with(font: BODY) : it } }
        lines = [
          text('リスト 1.8: app/views/list.html.erb', y: 720, font: GOTHIC),
          text('1:', y: 705, size: 9, font: MONO), text('<table>', x: 78, y: 705, size: 9, font: MONO),
          text('2:', y: 692, size: 9, font: MONO), japanese_in_code.('<th>削除</th>', x: 87, y: 692, size: 9),
          text('3:', y: 679, size: 9, font: MONO), text('</table>', x: 78, y: 679, size: 9, font: MONO)
        ]

        assert_equal("```erb:app/views/list.html.erb\n<table>\n  <th>削除</th>\n</table>\n```\n", render([lines]))
      end

      # 等幅の「1」で始まる和文の行でも、前後の行に番号が無ければコードにしない（番号の無い行を 0 番と数えて、
      # 「0 と 1 で続く」と取り違えていた）
      def test_should_not_take_body_line_starting_with_mono_one_for_code
        lines = [
          text('全体は stmts です。その中の', y: 720),
          text('1', y: 705, font: MONO), text('つめの式は', x: 70, y: 705),
      text('var_assign', x: 122, y: 705, font: MONO), text('です。', x: 174, y: 705),
          text('代入を表しています。', y: 690)
        ]

        refute_includes(render([lines]), '```')
      end

      # 版面の外のつめに縦に組んだ章の印は、回して描いた字として 1 ページだけでも落とす（繰り返しを待たない）。
      # 本文の行頭に接していても、ふつうの字とは別のまとまりにする
      def test_should_drop_rotated_margin_label_on_single_page
        tab = text('Chapter', x: 30, y: 700, size: 6).map { it.with(rotated: true) }
        lines = [tab, *body_paragraph(y: 700), *body_paragraph(y: 660)]

        assert_equal(<<~MARKDOWN, render([lines]))
          本文の一行目は版面の右端まで届きます続きの行で終わります。

          本文の一行目は版面の右端まで届きます続きの行で終わります。
        MARKDOWN
      end

      # 2 段組みは、同じ高さの左右の行が 1 行につながり、段の間の隙間で表に組まれていた。段の境目（左の段の右端が
      # そろう隙間）で分け、左の段を読み終えてから右の段を読む。段は 19 字（190pt）で、間を 20pt あける
      def test_should_read_two_columns_left_then_right
        lines = [
          text('左の段の文章は段の右端までしっかりと届', y: 700), text('右の段は一字下げて始まり右端まで届い', x: 280, y: 700),
          text('いて次の行へと続いていく。段落はこの行', y: 685), text('て次の行へと同じように続いていきます。', x: 270, y: 685),
          text('の後もまだもう少しだけ長く続いていき、', y: 670), text('右の段の段落はこの行の後も続いていき、', x: 270, y: 670),
          text('ここで終わります。', y: 655), text('ここで終わります。', x: 270, y: 655)
        ]

        assert_equal(<<~MARKDOWN, render([lines]))
          左の段の文章は段の右端までしっかりと届いて次の行へと続いていく。段落はこの行の後もまだもう少しだけ長く続いていき、ここで終わります。

          右の段は一字下げて始まり右端まで届いて次の行へと同じように続いていきます。右の段の段落はこの行の後も続いていき、ここで終わります。
        MARKDOWN
      end

      # 左の段の下で終わらない段落は、右の段の頭へ字下げせずに続く
      def test_should_continue_paragraph_from_left_column_to_right_column
        lines = [
          text('左の段の文章は段の右端までしっかりと届', y: 700), text('て、ここで段落が終わります。', x: 270, y: 700),
          text('いて次の行へと続いていくが段落は終わら', y: 685), text('次の段落は一字下げて右の段で始まる。', x: 280, y: 685),
          text('ないまま右の段の頭へと字下げせずに移っ', y: 670), text('右端まで届いて続いていきます。', x: 270, y: 670)
        ]

        assert_equal(<<~MARKDOWN, render([lines]))
          左の段の文章は段の右端までしっかりと届いて次の行へと続いていくが段落は終わらないまま右の段の頭へと字下げせずに移って、ここで段落が終わります。

          次の段落は一字下げて右の段で始まる。右端まで届いて続いていきます。
        MARKDOWN
      end

      # 列のあいだの縦の隙間が 3 行以上そろえば表に仮組みし、確かめるよう促すコメントを添える
      def test_should_infer_table_from_aligned_gaps
        rows = [%w[金属 仕事関数], %w[カリウム 2.2], %w[金 5.1]].each_with_index.flat_map do |(left, right), index|
          [text(left, y: 700 - (index * 18)), text(right, x: 200, y: 700 - (index * 18))]
        end

        assert_equal(<<~MARKDOWN, render([rows]))
          <!-- pdf:read: 列を推定して組んだ表です。列の対応を確かめてください -->

          | 金属 | 仕事関数 |
          | --- | --- |
          | カリウム | 2.2 |
          | 金 | 5.1 |
        MARKDOWN
      end

      # 分子と分母が詰まって並ぶ数式は、隙間がそろっても表にしない
      def test_should_not_take_fraction_lines_for_table
        lines = [%w[1 1], %w[x y], %w[2 3]].each_with_index.flat_map do |(left, right), index|
          [text(left, y: 700 - (index * 8)), text(right, x: 200, y: 700 - (index * 8))]
        end

        refute_includes(render([lines]), '列を推定')
      end

      # 本文の行のすぐ上の小さな仮名の行はルビにする
      def test_should_attach_ruby_to_base_characters
        lines = [text('かんじ', x: 60, y: 711, size: 5), text('漢字を読む', y: 700)]

        assert_equal("{漢字|かんじ}を読む\n", render([lines]))
      end

      # 擬似太字（同じ字を少しずらして 2 度描く）は 1 字にし、版面の外のつめは落とす
      def test_should_drop_overprinted_glyphs_and_margin_labels
        bold = text('2-2-2 節', y: 700, size: 14, font: GOTHIC)
        shifted = bold.map { it.with(x: it.x + 0.3) }
        pages = (0..1).map do |page|
          [*body_paragraph(y: 600, page:), text('つめ', x: 520, y: 583, page:)]
        end
        pages[0] = [*bold, *shifted, *pages[0]]

        markdown = render(pages)

        assert_includes(markdown, "# 2-2-2 節\n")
        refute_includes(markdown, 'つめ')
      end

      # 画像は描かれた高さで読む順に差し込み、画像の上に描かれた文字（図の注釈）は本文から除く
      def test_should_place_images_and_drop_labels_on_them
        image = ImageBox.new(page: 0, left: 100, bottom: 500, right: 300, top: 650)
        lines = [*body_paragraph(y: 700), text('注釈', x: 150, y: 600), *body_paragraph(y: 450)]

        markdown = render([lines], images: [[image]])

        assert_equal(2, markdown.scan('本文の一行目').size)
        assert_match(/終わります。\n\n<!-- 画像 -->\n\n本文の一行目/, markdown)
        refute_includes(markdown, '注釈')
      end

      # 和文のフォント（MS 明朝など）は全角の字がそろう作りで等幅の印を持つが、コードの書体ではない。
      # 印だけを手がかりにするときは英数字の字に限って等幅とみなす
      def test_should_not_take_fixed_pitch_japanese_font_for_code
        mincho = FontInfo.new(name: 'MS-Mincho', bold: false, mono: true)
        lines = [text('本文の一行目は和文の等幅の書体で組まれています', y: 700, font: mincho),
                 text('二行目も同じ書体です。', y: 683, font: mincho)]

        assert_equal("本文の一行目は和文の等幅の書体で組まれています二行目も同じ書体です。\n", render([lines]))
      end

      # 本文の書体が太字の名前（論文の「FutoMinA101Pro-Bold」）でも、本文を強調や見出しにしない。本文の大きさは字の幅の
      # 合計で決める（英語の参考文献の小さな字は、字の数では和文の本文を上回る）
      def test_should_not_take_bold_named_body_font_for_emphasis
        body = FontInfo.new(name: 'FutoMinA101Pro-Bold', bold: true, mono: false)
        roman = FontInfo.new(name: 'CMR8', bold: false, mono: false)
        paragraphs = [700, 660, 620, 580].flat_map do |y|
          [text('本文の一行目は版面の右端まで届きます', x: 70, y:, size: 9.2, font: body, last_x: 470),
           text('続きの行で終わります。', y: y - 15, size: 9.2, font: body)]
        end
        references = [500, 490, 480].map do |y|
          text('Sugiyama, M. and Kawanabe, M. Machine Learning in Non-Stationary Environments.', y:, size: 8, font: roman)
        end

        markdown = render([paragraphs + references])

        assert_includes(markdown, "本文の一行目は版面の右端まで届きます続きの行で終わります。\n")
        refute_includes(markdown, '**')
        refute_match(/^#/, markdown)
      end

      # 本文の書体が等幅の印を持つ和文の書体（Word の論文の MS ゴシック）なら、本文の英数字を行内のコードにしない
      def test_should_not_take_latin_of_fixed_pitch_body_font_for_code
        gothic = FontInfo.new(name: 'MSGothic', bold: false, mono: true)
        lines = [text('AICは1973年に導入された統計モデルの評価の規準で', y: 700, font: gothic),
                 text('ある。', y: 683, font: gothic)]

        assert_equal("AICは1973年に導入された統計モデルの評価の規準である。\n", render([lines]))
      end

      # 和文は両端をそろえて組むので、全角の文末で右端より 1 字を超えて手前に止まった行の後で段落を切る。
      # 次の段落の 1 行目は同じだけ字下げしているので、字下げの比べ方では切れない
      def test_should_break_paragraph_after_japanese_sentence_end_short_of_right_edge
        lines = [text('クッキーの有効期限は二十年後に設定されます。', x: 70, y: 700, last_x: 455),
                 text('テストを実行してすべてのエグザンプルが成功するこ', x: 70, y: 683, last_x: 470),
                 text('とを確かめてください。', y: 666)]

        assert_equal("クッキーの有効期限は二十年後に設定されます。\n\nテストを実行してすべてのエグザンプルが成功することを確かめてください。\n",
                     render([lines]))
      end

      # 本文より大きな字の行（「■コラム: …」の題）は、頭の「■」を箇条書きの点とみなさない
      def test_should_not_take_large_line_with_square_for_list_item
        lines = [text('■コラム: テストを書くのが難しいケース', y: 760, size: 12), *body_paragraph(y: 730), *body_paragraph(y: 690)]

        assert_match(/\A■コラム: テストを書くのが難しいケース\n\n本文/, render([lines]))
      end

      # TeX の脚注は、本文より小さい字の行が持ち上げた番号で始まる（「¹注の文」）。同じページの脚注は
      # 番号ごとに分ける
      def test_should_read_footnotes_with_raised_numbers
        body = text('本文です', y: 700)
        reference = Glyph.new(text: '1', x: body.last.right, y: 704, width: 4, size: 6, page: 0, font: BODY)
        notes = [1, 2].flat_map do |number|
          y = 80 - ((number - 1) * 12)
          [Glyph.new(text: number.to_s, x: 60, y: y + 3.5, width: 3, size: 6, page: 0, font: BODY),
           *text("注#{number}の文。", x: 64, y:, size: 8)]
        end
        second = Glyph.new(text: '2', x: 200, y: 704, width: 4, size: 6, page: 0, font: BODY)

        markdown = render([[*body, reference, *text('続く', x: 104, y: 700), second, *body_paragraph(y: 650), *notes]])

        assert_includes(markdown, "本文です[^1]続く[^2]\n")
        assert_includes(markdown, "[^1]: 注1の文。\n\n[^2]: 注2の文。\n")
      end

      # OCR の柱は、高さが数 pt 揺れ、字を読み違えても（「贈り物」を「り物」）、字の 6 割以上が共通すれば落とす
      def test_should_drop_ocr_running_heads_that_drift_and_misread
        heads = [[810, '付録A挑戦することの贈り物'], [811.6, '付録A挑戦することのり物'], [808.7, '付録 A 挑戦することの贈り物']]
        pages = heads.each_with_index.map do |(y, head), page|
          [text(head, x: 420, y:, size: 5, font: nil), *body_paragraph(y: 700, page:).map { |line| line.map { it.with(font: nil) } }]
        end

        markdown = render(pages)

        refute_includes(markdown, '挑戦すること')
        assert_equal(3, markdown.scan('本文の一行目').size)
      end

      # OCR が箇条書きの点を英字や記号と読んだ行（「e 1879年」「© 1895年」）も、点と続く字の位置がそろって
      # 3 行以上並べば箇条書きにする。項目の続きの行は、字の大きさの見積もりが揺れてもつなぐ
      def test_should_read_ocr_bullets_misread_as_letters
        lines = [text('e 1879年:ドイツに誕生', y: 700, font: nil), text('© 1895年:入学試験に不', y: 684, font: nil),
                 text('合格', x: 67.8, y: 668, size: 14, font: nil), text('es 1896年:入学', y: 652, font: nil)]

        assert_equal("- 1879年:ドイツに誕生\n- 1895年:入学試験に不合格\n- 1896年:入学\n", render([lines]))
        assert_includes(render([lines.first(2)]), 'e 1879年')
      end

      # OCR の脚注の参照は持ち上がりで見分けられないので、和文の直後で句読点の前の 1 桁の数字を候補にし、
      # 同じページに同じ番号の脚注の本文があるときだけ参照にする
      def test_should_link_ocr_footnote_digit_on_same_page
        note = [text('本文の一行目は版面の右端まで届きます', x: 70, y: 700, last_x: 470, font: nil),
                text('と記しています1。', y: 683, font: nil), text('1. 自伝ノートより。', y: 80, size: 8, font: nil)]
        plain = [text('本文の一行目は版面の右端まで届きます', x: 70, y: 700, last_x: 470, font: nil), text('その1、2日後です。', y: 683, font: nil)]

        markdown = render([note, plain])

        assert_includes(markdown, "記しています[^1]。\n")
        assert(markdown.end_with?("[^1]: 自伝ノートより。\n"))
        assert_includes(markdown, 'その1、2日後です。')
      end

      # TeX は論理式の否定（Ā）の上の線を字ではなく細い横線で描く。数式の書体の字の真上の線を $\overline{…}$ に
      # 戻し、重なった線（二重否定）は入れ子にする。本文の書体の字の上の罫線と、すぐ上に分子のある分数の線は
      # 否定の線ではない
      def test_should_restore_overline_of_negation_as_tex
        rule = ->(left, right, y) { ImageBox.new(page: 0, left:, bottom: y, right:, top: y + 0.4) }
        formula = [text('A+B', x: 100, y: 700, font: MATH), text('C', x: 130, y: 700, font: MATH)]
        others = [text('Name', x: 100, y: 650), text('1', x: 202.5, y: 609, font: MATH), text('n', x: 202.5, y: 590, font: MATH)]
        rules = [rule.(100, 115, 708), rule.(130, 135, 708), rule.(130, 135, 710), rule.(100, 120, 658), rule.(200, 210, 600)]

        markdown = render([formula + others], rules: [rules])

        assert_includes(markdown, '$\overline{A+B}$')
        assert_includes(markdown, '$\overline{\overline{C}}$')
        assert_equal(3, markdown.scan('\overline{').size)
        assert_includes(markdown, 'Name')
        refute_includes(markdown, '\overline{n}')
      end

      # 左端に根号の字（TeX の CMSY の「p」。横棒の高さから垂れ下がる字）が接する横線は、平方根の横棒。
      # 下の字の並び（数字だけでもよい）を $\sqrt{…}$ にし、入れ子にする。根号の字は本文から除く
      def test_should_restore_square_root_from_radical_and_bar
        root = FontInfo.new(name: 'CMSY10', bold: false, mono: false)
        roman = FontInfo.new(name: 'CMR12', bold: false, mono: false)
        bar = ->(left, right, y) { ImageBox.new(page: 0, left:, bottom: y, right:, top: y) }
        radical = ->(right, y) { Glyph.new(text: 'p', x: right - 10, y:, width: 10, size: 12, page: 0, font: root) }
        # a = 2√3、b = √(2+√2)
        glyphs = [text('a = 2', x: 60, y: 700, font: roman), radical.(102, 710.5), text('3', x: 102, y: 700, font: roman),
                  text('b =', x: 60, y: 650, font: roman), radical.(92, 662), text('2+', x: 92, y: 650, font: roman),
                  radical.(112, 660.5), text('2', x: 112, y: 650, font: roman)]
        rules = [bar.(102, 108, 710.5), bar.(92, 118, 662), bar.(112, 118, 660.5)]

        markdown = render([glyphs], rules: [rules])

        assert_includes(markdown, 'a = 2 $\sqrt{3}$')
        assert_includes(markdown, 'b = $\sqrt{2+\sqrt{2}}$')
        refute_match(/\bp\b/, markdown)
      end

      # 数を右そろえで縦に並べ、横線を引いた筆算は、別行立ての数式（array と \hline）にする。数は原本と同じ
      # 等幅（\mathtt）で書き、行の右端の差を \phantom{0} で埋めて桁をそろえる。升目ごとに字のまとまりが
      # 幾つもある数の表の罫線は筆算ではない
      def test_should_turn_written_addition_into_array
        tt = FontInfo.new(name: 'Cmtt10', bold: false, mono: true)
        rule = ->(left, right, y) { ImageBox.new(page: 0, left:, bottom: y, right:, top: y + 0.4) }
        addition = [text('1110.011', x: 70, y: 700, font: tt), text('+', x: 58, y: 685, font: tt), text('101.11', x: 75, y: 685, font: tt),
                    text('10100.001', x: 65, y: 670, font: tt)]
        table = [text('1', x: 60, y: 600), text('2', x: 100, y: 600), text('3', x: 140, y: 600), text('4', x: 60, y: 585), text('5', x: 100, y: 585), text('6', x: 140, y: 585)]

        markdown = render([addition + table], rules: [[rule.(55, 112, 681), rule.(55, 150, 596)]])

        assert_includes(markdown, "$$\n\\begin{array}{r} \\mathtt{1110.011}\\mathtt{} \\\\ +\\ \\mathtt{101.11}\\mathtt{\\phantom{0}} " \
                                  "\\\\ \\hline \\mathtt{10100.001}\\mathtt{} \\end{array}\n$$")
        assert_equal(1, markdown.scan('begin{array}').size)
        refute_includes(markdown, '1110.011 ')
      end

      # 割り算の筆算は、一番上の横線のすぐ下の行が「除数)被除数」になる。「除数\enclose{longdiv}{被除数}」とし、
      # 引く数の行（すぐ下に横線のある行）に下線を引く
      def test_should_turn_written_division_into_longdiv
        tt = FontInfo.new(name: 'Cmtt10', bold: false, mono: true)
        rule = ->(left, right, y) { ImageBox.new(page: 0, left:, bottom: y, right:, top: y + 0.4) }
        division = [text('10.1', x: 90, y: 720, font: tt), text('101)', x: 60, y: 705, font: tt), text('1110.1', x: 80, y: 705, font: tt),
                    text('1010', x: 85, y: 690, font: tt), text('100.1', x: 85, y: 675, font: tt)]

        markdown = render([division], rules: [[rule.(78, 112, 716), rule.(78, 112, 686)]])

        assert_includes(markdown, '\mathtt{101}\enclose{longdiv}{\mathtt{1110.1}}')
        assert_includes(markdown, '\underline{\mathtt{1010}}')
        assert_includes(markdown, '\mathtt{10.1}')
      end

      private

      def render(pages, images: [], dots: [], rules: [])
        scans = pages.each_with_index.map do |glyphs, index|
          Page.new(page_glyphs: glyphs.flatten.map { it.with(page: index) }, page_images: Array(images[index]),
                   page_dots: Array(dots[index]), page_size: [595.0, 842.0], page_rules: Array(rules[index]))
        end
        StructureMarkdown.new(LayoutStructure.new(scans).root).render
      end

      # 1 字下げた 1 行目が右端（約 470pt）まで届き、2 行目が手前で止まる段落
      def body_paragraph(y:, page: 0, first: '本文の一行目は版面の右端まで届きます')
        [text(first, x: 70, y:, page:, last_x: 470), text('続きの行で終わります。', y: y - 17, page:)]
      end

      # 文字を左から並べる。和文は 1 字、欧文は半字の幅、空白は 0.28 字ぶん進める。last_x を渡すと
      # 最後の字がそこで終わるよう字間を広げる（両端揃え）
      def text(string, y:, x: 60.0, size: 10.0, font: BODY, page: 0, last_x: nil)
        widths = string.each_char.map { it == ' ' ? size * 0.28 : (it.match?(StructureMarkdown::WIDE_CHAR) ? size : size * 0.5) }
        spacing = last_x ? (last_x - x - widths.sum) / [string.size - 1, 1].max : 0.0
        cursor = x
        string.each_char.zip(widths).filter_map do |char, width|
          glyph = Glyph.new(text: char, x: cursor, y:, width:, size:, page:, font:) unless char == ' '
          cursor += width + spacing
          glyph
        end
      end
    end
  end
end
