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
        def occurrence(chapter, main: false)
          { 'yomi' => 'ようごしゅう', 'link' => "#{chapter}.html#idx-#{chapter}", 'is_main' => main }
        end

        def index_links(occurrences, config: {})
          create_index_cache({ '用語集' => occurrences })
          builder = UnifiedPageBuilder.new(index_config: config)
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
          links, = index_links(occurrences, config: { max_sub_references: 2 })

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
          links, = index_links(occurrences, config: { max_sub_references: 2 })

          chapters = links.map { it[0][/\A[^.]+/] }
          assert_equal 3, chapters.size, '主要参照 1 + 副次参照 2'
          assert_includes chapters, '44-build', '出現の少ない章を丸ごと落とさない'
        end

        # 章が上限より多いときは、拾える章から順に 1 件ずつ
        def test_thinning_prefers_breadth_when_chapters_outnumber_the_limit
          occurrences = [occurrence('10-a', main: true)] +
                        %w[20-b 20-b 30-c 40-d].map { occurrence(it) }
          links, = index_links(occurrences, config: { max_sub_references: 2 })

          chapters = links.map { it[0][/\A[^.]+/] }
          assert_equal %w[10-a 20-b 30-c], chapters, '同じ章の 2 件目より別の章を優先する'
        end

        def test_zero_means_unlimited
          occurrences = [occurrence('33-index', main: true)] +
                        (10..14).map { occurrence("#{it}-chapter") }
          links, = index_links(occurrences, config: { max_sub_references: 0 })

          assert_equal 6, links.size
        end

        # `all` は主要参照の扱いを丸ごと切る逃げ道。Phase 2 以前と同じ索引になる
        def test_all_disables_the_feature_entirely
          links, = index_links([occurrence('12-quickstart'), occurrence('33-index', main: true)],
                               config: { reference_style: 'all' })

          assert_equal '12-quickstart.html#idx-12-quickstart', links.first[0], '並べ替えない'
          assert_equal 2, links.size
          assert(links.none? { it[1] == 'main-ref' }, '太字にもしない')
        end

        # 索引が短くなった理由が設定にあると分からないと「索引語が消えた」と読まれる
        def test_thinning_is_reported_not_silent
          occurrences = [occurrence('33-index', main: true)] +
                        (10..14).map { occurrence("#{it}-chapter") }
          _, builder = index_links(occurrences, config: { max_sub_references: 2 })

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
