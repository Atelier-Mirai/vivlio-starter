# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/unified_page_builder'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class UnifiedPageBuilderTest < Minitest::Test
        # 出力先はワークスペースの html/（P4 §3.4-1）
        INDEX_OUTPUT_FILE    = UnifiedPageBuilder::INDEX_OUTPUT_FILE
        GLOSSARY_OUTPUT_FILE = UnifiedPageBuilder::GLOSSARY_OUTPUT_FILE

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('unified_page_builder_test')
          Dir.chdir(@temp_dir)
          @builder = UnifiedPageBuilder.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # === 索引ページ ===

        def test_build_index_returns_nil_when_no_cache
          result = @builder.build_index!

          assert_nil result
        end

        def test_build_index_creates_html
          create_index_cache({ 'CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }] })

          result = @builder.build_index!

          assert_equal INDEX_OUTPUT_FILE, result
          assert File.exist?(INDEX_OUTPUT_FILE)
        end

        def test_build_index_generates_valid_structure
          create_index_cache({ 'CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }] })

          @builder.build_index!

          html = File.read(INDEX_OUTPUT_FILE)
          assert_includes html, '<!DOCTYPE html>'
          assert_includes html, '<title>索引</title>'
          assert_includes html, 'class="index-page"'
          assert_includes html, 'CSS'
        end

        # 索引・用語集は FrontmatterGenerator を通らないので、`<html lang>` を自前で組む。
        # ここが `ja` のベタ書きだと、英語の本でも索引だけ日本語と申告される
        # （読み上げ・ハイフネーションが誤る）。判型・テーマ色と同じ取り残しだった。
        def test_generated_pages_declare_the_configured_language
          create_index_cache({ 'CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }] })

          Common.stub(:book_language, 'en-US') do
            @builder.build_index!
          end

          assert_includes File.read(INDEX_OUTPUT_FILE), '<html lang="en-US">'
        end

        def test_build_index_groups_by_kana_row
          create_index_cache(
            {
              'あいう' => [{ 'yomi' => 'あいう', 'link' => '01.html#1' }],
              'かきく' => [{ 'yomi' => 'かきく', 'link' => '01.html#2' }]
            }
          )

          @builder.build_index!

          html = File.read(INDEX_OUTPUT_FILE)
          assert_includes html, 'data-initial="あ"'
          assert_includes html, 'data-initial="か"'
        end

        # 英字の読みは大文字・小文字を区別せずに並べる。文字コード順だと「KPF」が「Kindle」より先に来た（改善案 #99）
        def test_build_index_sorts_latin_readings_ignoring_case
          create_index_cache(
            %w[KPF Kobo Kindle\ Previewer Kindle KDP].to_h { [it, [{ 'yomi' => it, 'link' => "01.html##{it}" }]] }
          )

          @builder.build_index!

          html = File.read(INDEX_OUTPUT_FILE)
          order = %w[KDP Kindle Kindle\ Previewer Kobo KPF].map { html.index(">#{it}<") }
          assert(order.all?, "語が見つからない: #{order.inspect}")
          assert_equal order.sort, order
        end

        def test_build_index_returns_nil_when_empty
          create_index_cache({})

          result = @builder.build_index!

          assert_nil result
        end

        def test_build_index_removes_stale_file
          FileUtils.mkdir_p(File.dirname(INDEX_OUTPUT_FILE))
          File.write(INDEX_OUTPUT_FILE, '<html>stale</html>')
          create_index_cache({})

          @builder.build_index!

          refute File.exist?(INDEX_OUTPUT_FILE)
        end

        # === 主要参照（index-main-reference-spec.md R5・R6） ===

        # 索引の役割は所在の網羅ではなく説明の在り処への案内。
        # 「腰を据えて説明している箇所」を先頭に立てて太字にする。
        #
        # 既定では、出現ごとに別の節で、その節が語を見出しに掲げている（副次参照の候補になる）。
        # 節の選び方を確かめるテストだけが section・headed・h2 を指定する
        def occurrence(chapter, main: false, headed: true, section: nil, h2: nil)
          @section_seq = @section_seq.to_i + 1
          { 'yomi' => 'ようごしゅう', 'link' => "#{chapter}.html#idx-#{chapter}", 'is_main' => main,
            'section' => section || @section_seq, 'headed' => headed, 'h2' => h2 }.compact
        end

        # limit は副次参照の上限（0 で無制限）。book.yml では変えられないので、ビルダーの引数で当てる
        def index_links(occurrences, config: {}, limit: UnifiedPageBuilder::MAX_SUB_REFERENCES)
          create_index_cache({ '用語集' => occurrences })
          builder = UnifiedPageBuilder.new(index_config: config, sub_reference_limit: limit)
          builder.build_index!
          [File.read(INDEX_OUTPUT_FILE).scan(/<a href="([^"]+)"(?: class="([^"]+)")?>/), builder]
        end

        # **並べ替えは dedup より前でなければならない。** BacklinkDeduplicator は
        # 同一ページを指すリンクの DOM 上で最初の 1 本を残すため、順序が逆だと
        # 主要参照のほうが消える。
        def test_main_reference_comes_first_and_is_marked
          links, = index_links([occurrence('12-quickstart'), occurrence('33-index', main: true),
                                occurrence('41-book-yml')])

          assert_equal '33-index.html#idx-33-index', links.first[0], '主要参照が先頭'
          assert_equal 'main-ref', links.first[1]
          assert_nil links[1][1], '副次参照にはクラスを付けない'
        end

        def test_occurrence_order_is_preserved_among_sub_references
          links, = index_links([occurrence('12-quickstart'), occurrence('33-index', main: true),
                                occurrence('41-book-yml')])

          assert_equal %w[33-index 12-quickstart 41-book-yml],
                       links.map { it[0][/\A[^.]+/] }
        end

        def test_main_only_drops_sub_references
          links, = index_links([occurrence('12-quickstart'), occurrence('33-index', main: true)],
                               config: { reference_style: 'main_only' })

          assert_equal 1, links.size
          assert_equal '33-index.html#idx-33-index', links.first[0]
        end

        # 主要参照が無い語を間引くと、代わりの案内が無いまま索引から実質消える
        def test_terms_without_a_main_reference_are_never_thinned
          links, = index_links([occurrence('12-quickstart'), occurrence('33-index')],
                               config: { reference_style: 'main_only' })

          assert_equal 2, links.size
        end

        def test_max_sub_references_caps_the_tail
          occurrences = [occurrence('33-index', main: true)] +
                        (10..14).map { occurrence("#{it}-chapter") }
          links, = index_links(occurrences, limit: 2)

          assert_equal 3, links.size, '主要参照 1 + 副次参照 2'
          assert_equal '33-index.html#idx-33-index', links.first[0]
        end

        # 上限は出現回数で数えるので、先頭から機械的に切ると 1 つの章に集中した語が
        # 他の章を丸ごと押し出す（実測: CMYK が 43 章で 12 回出た途端、44 章の 1 件が
        # 索引から消えた）。章ごとに 1 件ずつ拾ってから枠を埋める
        def test_thinning_keeps_at_least_one_reference_per_chapter
          occurrences = [occurrence('43-cover', main: true)] +
                        Array.new(5) { occurrence('43-cover') } +
                        [occurrence('44-build')]
          links, = index_links(occurrences, limit: 2)

          chapters = links.map { it[0][/\A[^.]+/] }
          assert_equal 3, chapters.size, '主要参照 1 + 副次参照 2'
          assert_includes chapters, '44-build', '出現の少ない章を丸ごと落とさない'
        end

        # 章が上限より多いときは、拾える章から順に 1 件ずつ
        def test_thinning_prefers_breadth_when_chapters_outnumber_the_limit
          occurrences = [occurrence('10-a', main: true)] +
                        %w[20-b 20-b 30-c 40-d].map { occurrence(it) }
          links, = index_links(occurrences, limit: 2)

          chapters = links.map { it[0][/\A[^.]+/] }
          assert_equal %w[10-a 20-b 30-c], chapters, '同じ章の 2 件目より別の章を優先する'
        end

        # 上限は設定にしない（廃止キー）。古い book.yml に残っていても読まず、8 件で絞る
        def test_book_yml_max_sub_references_is_ignored
          occurrences = [occurrence('33-index', main: true)] +
                        (10..21).map { occurrence("#{it}-chapter") } # 12 章 → 上限 8 に絞られる
          links, = index_links(occurrences, config: { max_sub_references: 0 })

          assert_equal 1 + UnifiedPageBuilder::MAX_SUB_REFERENCES, links.size, '主要参照 1 + 副次参照 8'
        end

        # `all` は主要参照の扱いを丸ごと切る逃げ道。Phase 2 以前と同じ索引になる
        def test_all_disables_the_feature_entirely
          links, = index_links([occurrence('12-quickstart'), occurrence('33-index', main: true)],
                               config: { reference_style: 'all' })

          assert_equal '12-quickstart.html#idx-12-quickstart', links.first[0], '並べ替えない'
          assert_equal 2, links.size
          assert(links.none? { it[1] == 'main-ref' }, '太字にもしない')
        end

        # === 主要参照が別の巻にある語（index-other-volume-main-spec.md） ===

        def guided_index(occurrences, config: {}, guides: { '用語集' => '上巻 第7章' },
                         limit: UnifiedPageBuilder::MAX_SUB_REFERENCES)
          create_index_cache({ '用語集' => occurrences })
          builder = UnifiedPageBuilder.new(index_config: config, other_volume_guides: guides, sub_reference_limit: limit)
          builder.build_index!
          [File.read(INDEX_OUTPUT_FILE)[%r{<dd>.*?</dd>}m], builder]
        end

        # 組む巻に主要参照が無くても、別の巻の章を案内して副次参照を絞る（R1・R2）
        def test_other_volume_guide_leads_and_thins_sub_references
          dd, builder = guided_index((21..25).map { occurrence("#{it}-chapter") }, limit: 2)

          assert_match %r{</a><span class="index-other-volume"><strong>上巻 第7章</strong></span></dd>\z}, dd,
                       'ページ番号の後ろに太字で置く（先頭だと後ろの番号が別の巻のページに読める）'
          assert_equal 2, dd.scan('<a ').size
          assert_equal ['用語集'], builder.reference_limitation.terms, '絞ったことを知らせる'
        end

        # 組む巻に主要参照があれば、そちらが案内になる
        def test_other_volume_guide_is_omitted_when_main_is_local
          dd, = guided_index([occurrence('21-a', main: true), occurrence('22-b')])

          refute_includes dd, 'index-other-volume'
          assert_includes dd, 'main-ref'
        end

        def test_other_volume_guide_alone_with_main_only
          dd, = guided_index([occurrence('21-a'), occurrence('22-b')], config: { reference_style: 'main_only' })

          assert_equal '<dd><span class="index-other-volume"><strong>上巻 第7章</strong></span></dd>', dd
        end

        # `all` は逃げ道。案内も間引きもしない
        def test_other_volume_guide_is_off_with_all
          dd, = guided_index((21..25).map { occurrence("#{it}-chapter") },
                             config: { reference_style: 'all' }, limit: 2)

          refute_includes dd, 'index-other-volume'
          assert_equal 5, dd.scan('<a ').size
        end

        # 索引が短くなった理由が設定にあると分からないと「索引語が消えた」と読まれる
        def test_thinning_is_reported_not_silent
          occurrences = [occurrence('33-index', main: true)] +
                        (10..14).map { occurrence("#{it}-chapter") }
          _, builder = index_links(occurrences, limit: 2)

          limitation = builder.reference_limitation

          assert_predicate limitation, :any?
          assert_equal ['用語集'], limitation.terms
          assert_equal 2, limitation.limit
        end

        def test_nothing_reported_when_nothing_was_thinned
          _, builder = index_links([occurrence('33-index', main: true), occurrence('12-quickstart')])

          refute_predicate builder.reference_limitation, :any?
        end

        # 解釈できない値で組版を止めない。既定へ落として、直し方を添えて知らせる
        def test_unknown_reference_style_falls_back_with_a_warning
          out, err = capture_io do
            links, = index_links([occurrence('12-quickstart'), occurrence('33-index', main: true)],
                                 config: { reference_style: 'bogus' })

            assert_equal '33-index.html#idx-33-index', links.first[0]
          end

          assert_match(/reference_style/, out + err)
          assert_match(/main_and_sub/, out + err, '指定できる値を示す')
        end

        # === 副次参照の選び方（index-sub-reference-selection-spec.md） ===

        def linked_chapters(links) = links.map { it[0][/\A[^.]+/] }

        # 名前が出ているだけの所は、索引を引く手間に見合わない（R1）
        def test_sub_references_outside_headed_sections_are_dropped
          links, builder = index_links([occurrence('03-a', main: true), occurrence('07-b', headed: false),
                                        occurrence('08-c')])

          assert_equal %w[03-a 08-c], linked_chapters(links)
          assert_equal ['用語集'], builder.reference_limitation.terms, '絞ったことを知らせる'
        end

        # 同じ節の 2 回目以降は同じ所を指すだけ。主要参照の節は主要参照が入り口を受け持つ（R2）
        def test_only_the_first_occurrence_of_each_section_is_kept
          links, = index_links([occurrence('03-a', main: true, section: 5), occurrence('03-a', section: 5),
                                occurrence('07-b', section: 9), occurrence('07-b', section: 9),
                                occurrence('07-b', section: 20)])

          assert_equal %w[03-a 07-b 07-b], linked_chapters(links)
        end

        # 見出しに語を掲げた節が並ぶ章ごとに、別の節として数える
        def sections_in(chapters, main: '07-main')
          [occurrence(main, main: true)] + chapters.map { occurrence(it) }
        end

        # ふつうの言葉は作例の見出しにも出る。多すぎる語だけ主要参照の章へ絞る（R3）
        def test_terms_over_the_threshold_keep_only_main_chapter_sections
          subs = %w[07-main 07-main] + (10..20).map { "#{it}-other" } # 13 節
          links, builder = index_links(sections_in(subs), limit: 0)

          assert_equal %w[07-main 07-main 07-main], linked_chapters(links), '主要参照 1 + 主要参照の章の節 2'
          assert_equal ['用語集'], builder.reference_limitation.main_chapter_only
        end

        def test_terms_at_the_threshold_are_not_narrowed
          subs = %w[07-main] + (10..20).map { "#{it}-other" } # 12 節
          links, builder = index_links(sections_in(subs), limit: 0)

          assert_equal 13, links.size
          assert_empty builder.reference_limitation.main_chapter_only
        end

        # 「## 課題33　素数」の下の「### 解説」「### 勘所」は同じまとまりの続き。## ごとに 1 件にする（R2 改訂）
        def test_sections_under_an_h2_naming_the_term_count_as_one
          links, = index_links([occurrence('03-a', main: true),
                                occurrence('07-b', section: 4, h2: 4), occurrence('07-b', section: 6, h2: 4),
                                occurrence('07-b', section: 9, h2: 4), occurrence('07-b', section: 20)])

          assert_equal %w[03-a 07-b 07-b], linked_chapters(links), '## の 1 件と、別の ## の下の ### の 1 件'
        end

        # 主要参照のある ## の中は、主要参照が入り口を受け持つ
        def test_sections_in_the_main_references_h2_are_dropped
          links, = index_links([occurrence('03-a', main: true, section: 5, h2: 5),
                                occurrence('03-a', section: 8, h2: 5), occurrence('09-c')])

          assert_equal %w[03-a 09-c], linked_chapters(links)
        end

        # 多すぎるかは ## でまとめる前の ### ごとに数える。まとめた後で数えると、ふつうの言葉が
        # 境目を下回って作例の見出しが戻る。絞っても、## の見出しに語を掲げた節は章の外でも残す（R3 改訂）
        def test_narrowing_counts_sections_before_collapsing_and_keeps_h2_sections
          h2_sections = [3, 5, 7].map { occurrence('10-topic', section: it, h2: 3) } # 1 つの ## に 3 節
          plain = (11..20).map { occurrence("#{it}-other") } # ### だけ 10 節 → 計 13 節
          links, builder = index_links([occurrence('07-main', main: true)] + h2_sections + plain,
                                       limit: 0)

          assert_equal %w[07-main 10-topic], linked_chapters(links), '主要参照 1 + 章の外の ## の 1 件'
          assert_equal ['用語集'], builder.reference_limitation.main_chapter_only
        end

        # 省いた ### が無ければ、絞ったとは知らせない
        def test_narrowing_that_drops_nothing_is_not_reported
          subs = (10..22).map { occurrence("#{it}-topic", section: 2, h2: 2) } # 章の外の ## が 13
          links, builder = index_links([occurrence('07-main', main: true)] + subs, limit: 0)

          assert_equal 14, links.size
          assert_empty builder.reference_limitation.main_chapter_only
        end

        # 上限と公平さは、節を選んだ後に当てる（R5）
        def test_the_cap_applies_after_selecting_sections
          subs = %w[07-main] + (10..14).map { "#{it}-other" }
          occurrences = sections_in(subs) + [occurrence('15-x', headed: false)]
          links, = index_links(occurrences, limit: 3)

          assert_equal 4, links.size, '主要参照 1 + 副次参照 3'
          refute_includes linked_chapters(links), '15-x'
        end

        # 「まずここ」を示せないまま出現を削ると、語が索引から消える
        def test_terms_without_a_main_reference_keep_every_occurrence
          links, = index_links([occurrence('03-a', headed: false), occurrence('03-a', headed: false, section: 1),
                                occurrence('04-b', section: 1)])

          assert_equal 3, links.size
        end

        # 主要参照が別の巻にある語は、この巻に主要参照の章が無いので、案内だけになる
        def test_other_volume_terms_over_the_threshold_keep_only_the_guide
          dd, builder = guided_index((10..22).map { occurrence("#{it}-other") }, limit: 0)

          assert_equal '<dd><span class="index-other-volume"><strong>上巻 第7章</strong></span></dd>', dd
          assert_equal ['用語集'], builder.reference_limitation.main_chapter_only
        end

        # === 用語集ページ ===

        def test_build_glossary_returns_nil_when_no_terms
          result = @builder.build_glossary!([])

          assert_nil result
        end

        def test_build_glossary_creates_html
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'スタイルシート言語', 'flags' => 'g' }]

          result = @builder.build_glossary!(terms)

          assert_equal GLOSSARY_OUTPUT_FILE, result
          assert File.exist?(GLOSSARY_OUTPUT_FILE)
        end

        def test_build_glossary_includes_definition
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'スタイルシート言語', 'flags' => 'g' }]

          @builder.build_glossary!(terms)

          html = File.read(GLOSSARY_OUTPUT_FILE)
          assert_includes html, 'スタイルシート言語'
          assert_includes html, 'CSS'
        end

        # R2: バックリンクは中間 YAML（_index_matches.yml）の glossary_backlinks から描画する
        def test_build_glossary_includes_backlinks_from_matches_file
          create_index_cache(
            {},
            backlinks: { 'CSS' => [{ 'chapter' => '01-intro', 'occurrence' => 1,
                                     'anchor_id' => 'gls-src-01-intro-css-1' }] }
          )
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'テスト', 'flags' => 'g' }]

          @builder.build_glossary!(terms)

          html = File.read(GLOSSARY_OUTPUT_FILE)
          assert_includes html, 'gls-src-01-intro-css-1'
          assert_includes html, 'glossary-backlink'
        end

        # 幽霊リンク回帰（R2）: 辞書に前回ビルドの backlink_sources が残置していても読まない。
        # 今回のスキャン結果（中間 YAML）に無い語はバックリンクなしで掲載される
        def test_build_glossary_ignores_stale_backlink_sources_in_dictionary
          create_index_cache({}, backlinks: {})
          terms = [{
            'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'テスト', 'flags' => 'g',
            'backlink_sources' => [
              { 'chapter' => '61-developer', 'occurrence' => 1, 'anchor_id' => 'gls-src-61-developer-css-1' }
            ]
          }]

          @builder.build_glossary!(terms)

          html = File.read(GLOSSARY_OUTPUT_FILE)
          refute_includes html, 'gls-src-61-developer-css-1', '存在しない章への幽霊バックリンクを印字しない'
          refute_includes html, 'glossary-backlink'
          assert_includes html, 'CSS', '掲載自体は維持される'
        end

        def test_build_glossary_removes_stale_file
          FileUtils.mkdir_p(File.dirname(GLOSSARY_OUTPUT_FILE))
          File.write(GLOSSARY_OUTPUT_FILE, '<html>stale</html>')

          @builder.build_glossary!([])

          refute File.exist?(GLOSSARY_OUTPUT_FILE)
        end

        def test_build_glossary_groups_by_initial
          terms = [
            { 'term' => 'あいう', 'yomi' => 'あいう', 'definition' => 'テスト1', 'flags' => 'g' },
            { 'term' => 'かきく', 'yomi' => 'かきく', 'definition' => 'テスト2', 'flags' => 'g' }
          ]

          @builder.build_glossary!(terms)

          html = File.read(GLOSSARY_OUTPUT_FILE)
          assert_includes html, 'glossary-group-header'
        end

        def test_build_glossary_with_custom_title
          builder = UnifiedPageBuilder.new(glossary_config: { title: 'カスタム用語集' })
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'テスト', 'flags' => 'g' }]

          builder.build_glossary!(terms)

          html = File.read(GLOSSARY_OUTPUT_FILE)
          assert_includes html, 'カスタム用語集'
        end

        # === 用語集のページ番号を索引にそろえる（index-sub-reference-selection-spec.md R8） ===

        def glossary_backlinks_html(occurrences, flags: 'ig', config: {}, guides: {})
          create_index_cache(
            { '用語集' => occurrences },
            backlinks: { '用語集' => [{ 'chapter' => '01-intro', 'occurrence' => 1,
                                        'anchor_id' => 'gls-src-01-intro-用語集-1' }] }
          )
          builder = UnifiedPageBuilder.new(index_config: config, other_volume_guides: guides)
          builder.build_index!
          builder.build_glossary!([{ 'term' => '用語集', 'yomi' => 'ようごしゅう', 'definition' => '説明', 'flags' => flags }])
          [File.read(GLOSSARY_OUTPUT_FILE)[%r{<p class="glossary-backlinks">.*?</p>}m], builder]
        end

        def test_glossary_lists_the_same_references_as_the_index
          html, builder = glossary_backlinks_html([occurrence('12-a'), occurrence('33-index', main: true),
                                                   occurrence('41-b', headed: false)])

          assert_equal [['33-index.html#idx-33-index', 'glossary-backlink main-ref'],
                        ['12-a.html#idx-12-a', 'glossary-backlink']],
                       html.scan(/<a href="([^"]+)" class="([^"]+)">/), '主要参照が先頭で太字・選んだ副次参照が続く'
          assert_equal ['用語集'], builder.reference_limitation.terms, '用語集で選び直しても二重に数えない'
        end

        # 区切りの「, 」は CSS の ::before が付ける。リンクの間に空白があると「935 , 843」になる。
        # 索引の参照を並べる語も、章ごとの初出を並べる語も同じ
        def test_glossary_backlinks_have_no_space_between_links
          index_html, = glossary_backlinks_html([occurrence('12-a'), occurrence('33-index', main: true)])
          chapter_html, = glossary_backlinks_html([occurrence('33-index', main: true)], flags: 'g')

          [index_html, chapter_html].each { refute_match(%r{</a>\s+<a}, it) }
          assert_match(%r{</a><a}, index_html, 'リンクが 2 本並ぶ形で確かめる')
        end

        def test_glossary_only_terms_keep_the_chapter_first_occurrences
          html, = glossary_backlinks_html([occurrence('33-index', main: true)], flags: 'g')

          assert_includes html, 'gls-src-01-intro-用語集-1'
          refute_includes html, 'idx-'
        end

        def test_glossary_with_all_keeps_the_chapter_first_occurrences
          html, = glossary_backlinks_html([occurrence('33-index', main: true)], config: { reference_style: 'all' })

          assert_includes html, 'gls-src-01-intro-用語集-1'
        end

        def test_glossary_terms_without_a_main_reference_keep_the_chapter_first_occurrences
          html, = glossary_backlinks_html([occurrence('12-a'), occurrence('41-b')])

          assert_includes html, 'gls-src-01-intro-用語集-1'
        end

        def test_glossary_with_main_only_lists_only_the_main_reference
          html, = glossary_backlinks_html([occurrence('12-a'), occurrence('33-index', main: true)],
                                          config: { reference_style: 'main_only' })

          assert_equal ['33-index.html#idx-33-index'], html.scan(/href="([^"]+)"/).flatten
        end

        # 別の巻の案内は、索引と同じく末尾に「,」で区切って太字で置く
        def test_glossary_appends_the_other_volume_guide
          html, = glossary_backlinks_html([occurrence('21-a')], guides: { '用語集' => '上巻 第7章' })

          assert_match %r{<a href="21-a\.html#idx-21-a" class="glossary-backlink"></a>, <span class="index-other-volume"><strong>上巻 第7章</strong></span></p>\z},
                       html
        end

        # === 統合テスト ===

        def test_both_pages_can_be_built_sequentially
          create_index_cache(
            { 'CSS' => [{ 'yomi' => 'CSS', 'link' => '01.html#1' }] },
            backlinks: { 'CSS' => [{ 'chapter' => '01', 'occurrence' => 1, 'anchor_id' => 'gls-src-01-css-1' }] }
          )
          terms = [{ 'term' => 'CSS', 'yomi' => 'CSS', 'definition' => 'スタイルシート', 'flags' => 'ig' }]

          @builder.build_index!
          @builder.build_glossary!(terms)

          assert File.exist?(INDEX_OUTPUT_FILE)
          assert File.exist?(GLOSSARY_OUTPUT_FILE)

          glossary_html = File.read(GLOSSARY_OUTPUT_FILE)
          assert_includes glossary_html, 'gls-src-01-css-1'
        end

        private

        def create_index_cache(terms_hash, backlinks: {})
          data = {
            'generated_at' => Time.now.iso8601,
            'total_matches' => terms_hash.values.sum { it.size },
            'terms' => terms_hash,
            'glossary_backlinks' => backlinks
          }
          FileUtils.mkdir_p(File.dirname(Common::INDEX_MATCHES_FILE))
          File.write(Common::INDEX_MATCHES_FILE, data.to_yaml)
        end
      end
    end
  end
end
