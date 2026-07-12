# frozen_string_literal: true

require_relative '../../test_helper'
require 'vivlio_starter/cli/pre_process/data_render'

# ================================================================
# DataRender テスト
# ================================================================
# QueryStream 記法の全ステージ（源泉・抽出・ソート・件数・スタイル）を
# 書籍・都道府県・気象・元素の4データ種別で網羅的にテストする。
#
# テスト構成:
#   1. Singularize       - 単数形/複数形の自動解決
#   2. QueryStreamParser - 記法のパース
#   3. TemplateCompiler  - テンプレートの変数展開
#   4. DataRender        - 統合テスト（パイプライン全体）
# ================================================================

module VivlioStarter
  module CLI
    module PreProcessCommands
      # テスト用のフィクスチャディレクトリパスを返す
      FIXTURE_BASE = File.expand_path('fixtures/data_render', __dir__)
      FIXTURE_DATA_DIR = File.join(FIXTURE_BASE, 'data')
      FIXTURE_TEMPLATES_DIR = File.join(FIXTURE_BASE, 'templates')

      # ================================================================
      # 1. Singularize テスト
      # ================================================================
      class SingularizeTest < Minitest::Test
        # 通常の複数形（末尾 s）を単数形に変換できる
        def test_should_singularize_regular_plurals
          assert_equal 'book',           QueryStream::Singularize.call('books')
          assert_equal 'element',        QueryStream::Singularize.call('elements')
          assert_equal 'weather_report', QueryStream::Singularize.call('weather_reports')
          assert_equal 'prefecture',     QueryStream::Singularize.call('prefectures')
        end

        # -ies で終わる複数形を -y に変換できる
        def test_should_singularize_ies_to_y
          assert_equal 'category', QueryStream::Singularize.call('categories')
          assert_equal 'entry',    QueryStream::Singularize.call('entries')
        end

        # -ches/-shes/-ses/-xes/-zes で終わる複数形を変換できる
        def test_should_singularize_es_variants
          assert_equal 'branch', QueryStream::Singularize.call('branches')
          assert_equal 'brush',  QueryStream::Singularize.call('brushes')
          assert_equal 'box',    QueryStream::Singularize.call('boxes')
        end

        # -ves で終わる複数形を -f に変換できる
        def test_should_singularize_ves_to_f
          assert_equal 'shelf', QueryStream::Singularize.call('shelves')
        end

        # 不変の語はそのまま返す
        def test_should_keep_invariant_words
          assert_equal 'data',  QueryStream::Singularize.call('data')
          assert_equal 'sheep', QueryStream::Singularize.call('sheep')
        end
      end

      # ================================================================
      # 2. QueryStreamParser テスト
      # ================================================================
      class QueryStreamParserTest < Minitest::Test
        Parser = QueryStream::QueryStreamParser

        # 源泉のみの最小記法をパースできる
        def test_should_parse_source_only
          result = Parser.parse('= books')
          assert_equal 'books', result[:source]
          assert_empty result[:filters]
          assert_nil result[:sort]
          assert_nil result[:limit]
          assert_nil result[:style]
        end

        # スタイル指定をパースできる
        def test_should_parse_style
          result = Parser.parse('= books | :full')
          assert_equal 'books', result[:source]
          assert_equal 'full',  result[:style]
        end

        # 件数指定をパースできる
        def test_should_parse_limit
          result = Parser.parse('= books | 5')
          assert_equal 5, result[:limit]
        end

        # ソート指定（降順）をパースできる
        def test_should_parse_sort_desc
          result = Parser.parse('= books | -title')
          assert_equal({ field: :title, direction: :desc }, result[:sort])
        end

        # ソート指定（昇順）をパースできる
        def test_should_parse_sort_asc
          result = Parser.parse('= books | +title')
          assert_equal({ field: :title, direction: :asc }, result[:sort])
        end

        # 等値フィルタをパースできる
        def test_should_parse_eq_filter
          result = Parser.parse('= books | tags=ruby')
          assert_equal 1, result[:filters].size
          filter = result[:filters].first
          assert_equal :tags, filter[:field]
          assert_equal :eq,   filter[:op]
          assert_equal ['ruby'], filter[:value]
        end

        # カンマ区切りOR条件をパースできる
        def test_should_parse_or_filter_with_comma
          result = Parser.parse('= books | tags=ruby, javascript')
          filter = result[:filters].first
          assert_equal ['ruby', 'javascript'], filter[:value]
        end

        # AND 条件をパースできる
        def test_should_parse_and_filter
          result = Parser.parse('= books | tags=ruby && tags=beginner')
          assert_equal 2, result[:filters].size
          assert_equal :tags, result[:filters][0][:field]
          assert_equal :tags, result[:filters][1][:field]
        end

        # AND の別記法（and）をパースできる
        def test_should_parse_and_with_word
          result = Parser.parse('= weather_reports | location=東京 AND condition=晴')
          assert_equal 2, result[:filters].size
        end

        # 比較演算子（>=）をパースできる
        def test_should_parse_gte_operator
          result = Parser.parse('= weather_reports | temp_min_c>=20')
          filter = result[:filters].first
          assert_equal :temp_min_c, filter[:field]
          assert_equal :gte,        filter[:op]
          assert_equal 20,          filter[:value]
        end

        # 比較演算子（<=）をパースできる
        def test_should_parse_lte_operator
          result = Parser.parse('= prefectures | population<=5000000')
          filter = result[:filters].first
          assert_equal :lte, filter[:op]
        end

        # 比較演算子（>）をパースできる
        def test_should_parse_gt_operator
          result = Parser.parse('= elements | atomic_number>5')
          filter = result[:filters].first
          assert_equal :gt, filter[:op]
          assert_equal 5,   filter[:value]
        end

        # 比較演算子（<）をパースできる
        def test_should_parse_lt_operator
          result = Parser.parse('= elements | atomic_number<5')
          filter = result[:filters].first
          assert_equal :lt, filter[:op]
        end

        # 不等値演算子（!=）をパースできる
        def test_should_parse_neq_operator
          result = Parser.parse('= elements | category!=nonmetal')
          filter = result[:filters].first
          assert_equal :neq, filter[:op]
        end

        # 包括的範囲指定（..）をパースできる
        def test_should_parse_inclusive_range
          result = Parser.parse('= elements | atomic_number=1..6')
          filter = result[:filters].first
          assert_equal :range, filter[:op]
          assert_equal 1..6,   filter[:value]
        end

        # 排他的範囲指定（...）をパースできる
        def test_should_parse_exclusive_range
          result = Parser.parse('= elements | atomic_number=1...6')
          filter = result[:filters].first
          assert_equal :range, filter[:op]
          assert_equal 1...6,  filter[:value]
        end

        # 下限のみの範囲指定（20..）をパースできる
        def test_should_parse_open_ended_range
          result = Parser.parse('= weather_reports | temp_min_c=20..')
          filter = result[:filters].first
          assert_equal :gte, filter[:op]
          assert_equal 20,   filter[:value]
        end

        # 上限のみの範囲指定（..25）をパースできる
        def test_should_parse_open_start_range
          result = Parser.parse('= weather_reports | temp_min_c=..25')
          filter = result[:filters].first
          assert_equal :lte, filter[:op]
          assert_equal 25,   filter[:value]
        end

        # 上限のみの排他的範囲（...25 → 25未満）をパースできる
        def test_should_parse_open_start_exclusive_range
          result = Parser.parse('= weather_reports | temp_min_c=...25')
          filter = result[:filters].first
          assert_equal :lt, filter[:op]
          assert_equal 25,  filter[:value]
        end

        # 主キー検索をパースできる
        def test_should_parse_primary_key_lookup
          result = Parser.parse('= book | 楽しいRuby')
          assert result[:single_lookup]
          assert_equal 1, result[:filters].size
          assert_equal :_primary_key, result[:filters].first[:field]
        end

        # 全ステージの組み合わせをパースできる
        def test_should_parse_full_pipeline
          result = Parser.parse('= books | tags=ruby | -title | 5 | :full')
          assert_equal 'books', result[:source]
          assert_equal 1,       result[:filters].size
          assert_equal :desc,   result[:sort][:direction]
          assert_equal :title,  result[:sort][:field]
          assert_equal 5,       result[:limit]
          assert_equal 'full',  result[:style]
        end

        # パイプ省略時の自動判別が正しく動作する
        def test_should_auto_classify_tokens_with_omitted_pipes
          result = Parser.parse('= books | tags=ruby | :full')
          assert_equal 'full', result[:style]
          assert_equal 1, result[:filters].size
          assert_nil result[:sort]
          assert_nil result[:limit]
        end

        # 複雑な条件式をパースできる
        def test_should_parse_complex_expression
          result = Parser.parse('= weather_reports | condition=晴, 曇 and temp_min_c>=20 | -date | 5 | :full')
          assert_equal 'weather_reports', result[:source]
          assert_equal 2, result[:filters].size
          assert_equal :eq,  result[:filters][0][:op]
          assert_equal :gte, result[:filters][1][:op]
          assert_equal 'full', result[:style]
          assert_equal 5, result[:limit]
        end

        # AND 連結時に2件目以降のフィールド省略を許容する
        def test_should_allow_fieldless_and_clause
          result = Parser.parse('= books | tags = ruby && beginner')
          assert_equal 1, result[:filters].size
          filter = result[:filters].first
          assert_equal :eq, filter[:op]
          assert_equal [:ruby, :beginner].map(&:to_s), filter[:value]
        end
      end

      # ================================================================
      # 3. TemplateCompiler テスト
      # ================================================================
      class TemplateCompilerTest < Minitest::Test
        Compiler = QueryStream::TemplateCompiler

        # 単一レコードの変数展開が正しく動作する
        def test_should_expand_single_record
          template = "### = title\n**著者**: = author\n"
          records = [{ title: '楽しいRuby', author: '高橋征義' }]

          result = Compiler.render(template, records)
          assert_includes result, '### 楽しいRuby'
          assert_includes result, '**著者**: 高橋征義'
        end

        # 複数レコードの反復展開が正しく動作する
        def test_should_expand_multiple_records
          template = "### = title\n= desc\n"
          records = [
            { title: '楽しいRuby', desc: 'Rubyを楽しく学べる入門書。' },
            { title: 'はじめてのC', desc: 'C言語の定番入門書。' }
          ]

          result = Compiler.render(template, records)
          assert_includes result, '### 楽しいRuby'
          assert_includes result, '### はじめてのC'
          assert_includes result, 'Rubyを楽しく学べる入門書。'
          assert_includes result, 'C言語の定番入門書。'
        end

        # nil フィールドの行がスキップされる
        def test_should_skip_line_when_value_is_nil
          template = "### = title\n![](cover){width=40%}\n"
          records = [{ title: 'はじめてのC', cover: nil }]

          result = Compiler.render(template, records)
          assert_includes result, '### はじめてのC'
          refute_includes result, '![](cover)'
          refute_includes result, '![]()'
        end

        # 空文字フィールドの行がスキップされる
        def test_should_skip_line_when_value_is_empty
          template = "### = title\n= desc\n"
          records = [{ title: 'テスト', desc: '' }]

          result = Compiler.render(template, records)
          assert_includes result, '### テスト'
          refute_includes result, 'desc'
        end

        # 画像記法の変数展開が正しく動作する
        def test_should_expand_image_variable
          template = "![](cover){width=40%}\n"
          records = [{ cover: 'ruby-enjoyer.webp' }]

          result = Compiler.render(template, records)
          assert_includes result, '![](ruby-enjoyer.webp){width=40%}'
        end

        # 画像記法のリテラル（拡張子あり）はそのまま出力される
        def test_should_keep_literal_image_path
          template = "![](Einstein.png){width=40%}\n"
          records = [{ title: 'テスト' }]

          result = Compiler.render(template, records)
          assert_includes result, '![](Einstein.png){width=40%}'
        end

        # 画像記法の明示的変数展開（= cover）も動作する
        def test_should_expand_explicit_image_variable
          template = "![](= cover){width=40%}\n"
          records = [{ cover: 'ruby-enjoyer.webp' }]

          result = Compiler.render(template, records)
          assert_includes result, '![](ruby-enjoyer.webp){width=40%}'
        end

        # テーブル記法のヘッダー行が一度だけ出力される
        def test_should_output_table_header_once
          template = "| タイトル | 説明 | 著者 |\n|---|---|---|\n| = title | = desc | = author |\n"
          records = [
            { title: '楽しいRuby', desc: '入門書', author: '高橋' },
            { title: 'はじめてのC', desc: '定番', author: '柴田' }
          ]

          result = Compiler.render(template, records)

          # ヘッダー行は1回だけ
          assert_equal 1, result.scan('| タイトル |').size
          assert_equal 1, result.scan('|---|---|---|').size

          # データ行は2件
          assert_includes result, '| 楽しいRuby | 入門書 | 高橋 |'
          assert_includes result, '| はじめてのC | 定番 | 柴田 |'
        end

        # 存在しないキーがテンプレートにある場合エラーになる
        def test_should_raise_error_for_unknown_key
          template = "### = unknown_field\n"
          records = [{ title: 'テスト' }]

          assert_raises(QueryStream::UnknownKeyError) do
            Compiler.render(template, records)
          end
        end

        # レコードが空の場合は空文字列を返す
        def test_should_return_empty_for_no_records
          template = "### = title\n"
          result = Compiler.render(template, [])
          assert_equal '', result
        end
      end

      # ================================================================
      # 4. DataRender 統合テスト
      # ================================================================
      class DataRenderIntegrationTest < Minitest::Test
        # ----------------------------------------------------------------
        # 書籍データ
        # ----------------------------------------------------------------

        # 全件展開が正しく動作する
        def test_should_expand_all_books
          content = "# 参考書籍\n\n= books\n\n次の章へ\n"
          result = render(content)

          assert_includes result, '### 楽しいRuby'
          assert_includes result, '### はじめてのC'
          assert_includes result, '### JavaScript入門'
          assert_includes result, '### Rubyレシピブック'
          assert_includes result, '次の章へ'
        end

        # タグでの絞り込みが正しく動作する
        def test_should_filter_books_by_tag
          content = "= books | tags=ruby\n"
          result = render(content)

          assert_includes result, '楽しいRuby'
          assert_includes result, 'JavaScript入門'   # tags: "ruby, javascript"
          assert_includes result, 'Rubyレシピブック'
          refute_includes result, 'はじめてのC'
        end

        # AND 条件の絞り込みが正しく動作する
        def test_should_filter_books_with_and_condition
          content = "= books | tags=ruby && tags=beginner\n"
          result = render(content)

          assert_includes result, '楽しいRuby'
          refute_includes result, 'Rubyレシピブック'  # advanced
        end

        # OR 条件の絞り込みが正しく動作する
        def test_should_filter_books_with_or_values
          content = "= books | tags=c, javascript\n"
          result = render(content)

          assert_includes result, 'はじめてのC'
          assert_includes result, 'JavaScript入門'
          refute_includes result, 'Rubyレシピブック'
        end

        # 主キー検索（title）で一件取得できる
        def test_should_lookup_book_by_title
          content = "= book | 楽しいRuby\n"
          result = render(content)

          assert_includes result, '楽しいRuby'
          refute_includes result, 'はじめてのC'
        end

        # スタイル指定が正しく動作する
        def test_should_use_full_style_template
          content = "= books | tags=ruby && tags=beginner | :full\n"
          result = render(content)

          assert_includes result, '## 楽しいRuby'     # fullスタイルは ## を使用
          assert_includes result, '**タグ**:'          # fullスタイルにはタグがある
        end

        # テーブルスタイルが正しく動作する
        def test_should_render_table_style
          content = "= books | tags=ruby && tags=beginner | :table\n"
          result = render(content)

          assert_includes result, '| タイトル |'
          assert_includes result, '| 楽しいRuby |'
        end

        # nil cover の行がスキップされる
        def test_should_skip_nil_cover_line
          content = "= book | はじめてのC\n"
          result = render(content)

          assert_includes result, 'はじめてのC'
          refute_includes result, '![]()'
          refute_match(/!\[\]\([^)]*\)\{width/, result)
        end

        # ソートが正しく動作する
        def test_should_sort_books_by_title_desc
          content = "= books | -title\n"
          result = render(content)

          titles = result.scan(/### (.+)/).flatten
          assert_equal titles, titles.sort.reverse
        end

        # 件数制限が正しく動作する
        def test_should_limit_results
          content = "= books | 2\n"
          result = render(content)

          titles = result.scan(/### (.+)/).flatten
          assert_equal 2, titles.size
        end

        # ----------------------------------------------------------------
        # 都道府県データ
        # ----------------------------------------------------------------

        # 全件展開ができる
        def test_should_expand_all_prefectures
          content = "= prefectures\n"
          result = render(content)

          assert_includes result, '北海道'
          assert_includes result, '東京都'
          assert_includes result, '大阪府'
        end

        # 地方での絞り込みが動作する
        def test_should_filter_prefectures_by_region
          content = "= prefectures | region=関東\n"
          result = render(content)

          assert_includes result, '東京都'
          assert_includes result, '神奈川県'
          refute_includes result, '北海道'
          refute_includes result, '大阪府'
        end

        # 複数地方のOR絞り込みが動作する
        def test_should_filter_prefectures_by_multiple_regions
          content = "= prefectures | region=関東, 関西\n"
          result = render(content)

          assert_includes result, '東京都'
          assert_includes result, '神奈川県'
          assert_includes result, '大阪府'
          refute_includes result, '北海道'
        end

        # code による主キー検索ができる
        def test_should_lookup_prefecture_by_code
          content = "= prefecture | 13\n"
          result = render(content)

          assert_includes result, '東京都'
          refute_includes result, '大阪府'
        end

        # name による主キー検索ができる
        def test_should_lookup_prefecture_by_name
          content = "= prefecture | 東京都\n"
          result = render(content)

          assert_includes result, '東京都'
          assert_includes result, '新宿区'
        end

        # 人口での比較フィルタが動作する
        def test_should_filter_prefectures_by_population_gte
          content = "= prefectures | population>=9000000\n"
          result = render(content)

          assert_includes result, '東京都'
          assert_includes result, '神奈川県'
          refute_includes result, '北海道'
        end

        # ----------------------------------------------------------------
        # 気象データ
        # ----------------------------------------------------------------

        # 地点＋天候の複合AND条件が動作する
        def test_should_filter_weather_by_location_and_condition
          content = "= weather_reports | location=東京 AND condition=晴\n"
          result = render(content)

          assert_includes result, '2024-01-01'
          assert_includes result, '2024-07-20'
          refute_includes result, '2024-06-15'   # 雨
        end

        # 気温の範囲指定が動作する
        def test_should_filter_weather_by_temp_range
          content = "= weather_reports | temp_min_c=20..27\n"
          result = render(content)

          assert_includes result, '2024-07-20'   # 26.3
          assert_includes result, '2024-07-21'   # 25.0
          refute_includes result, '2024-01-01'   # 1.5
        end

        # 排他的範囲指定が動作する
        def test_should_filter_weather_by_exclusive_range
          content = "= weather_reports | temp_min_c=25...27\n"
          result = render(content)

          assert_includes result, '2024-07-20'   # 26.3
          assert_includes result, '2024-07-21'   # 25.0
          refute_includes result, '2024-08-10'   # 27.8（27未満なので含まない）
        end

        # 日付降順ソート＋件数制限が動作する
        def test_should_sort_weather_by_date_desc_with_limit
          content = "= weather_reports | -date | 3\n"
          result = render(content)

          # 最新3件のみ
          assert_includes result, '2024-08-10'
          assert_includes result, '2024-07-21'
          assert_includes result, '2024-07-20'
          refute_includes result, '2024-01-01'
        end

        # OR天候 + 気温条件の複合クエリが動作する
        def test_should_handle_complex_weather_query
          content = "= weather_reports | condition=晴, 曇 and temp_min_c>=20 | -date | 5\n"
          result = render(content)

          # 晴または曇で最低気温20度以上
          assert_includes result, '2024-08-10'   # 晴, 27.8
          assert_includes result, '2024-07-21'   # 曇, 25.0
          assert_includes result, '2024-07-20'   # 晴, 26.3
          refute_includes result, '2024-01-01'   # 晴だが気温1.5
          refute_includes result, '2024-06-15'   # 雨
        end

        # ----------------------------------------------------------------
        # 元素データ
        # ----------------------------------------------------------------

        # カテゴリ+状態のANDフィルタが動作する
        def test_should_filter_elements_by_category_and_phase
          content = "= elements | category=nonmetal AND phase_at_stp=gas\n"
          result = render(content)

          assert_includes result, '水素'
          assert_includes result, '窒素'
          assert_includes result, '酸素'
          refute_includes result, '炭素'    # solid
          refute_includes result, 'ヘリウム' # noble_gas
        end

        # 原子番号の範囲フィルタが動作する
        def test_should_filter_elements_by_atomic_number_range
          content = "= elements | atomic_number=1..3\n"
          result = render(content)

          assert_includes result, '水素'
          assert_includes result, 'ヘリウム'
          assert_includes result, 'リチウム'
          refute_includes result, '炭素'
        end

        # name による主キー検索ができる
        def test_should_lookup_element_by_name
          content = "= element | 水素\n"
          result = render(content)

          assert_includes result, '水素'
          assert_includes result, 'H'
          refute_includes result, 'ヘリウム'
        end

        # fullスタイルで元素を表示できる
        def test_should_render_element_with_full_style
          content = "= element | 水素 | :full\n"
          result = render(content)

          assert_includes result, '## 水素'      # fullスタイルは ## を使用
          assert_includes result, '**カテゴリ**:' # fullスタイルにはカテゴリがある
        end

        # 不等値フィルタが動作する
        def test_should_filter_elements_with_neq
          content = "= elements | category!=nonmetal\n"
          result = render(content)

          assert_includes result, 'ヘリウム'   # noble_gas
          assert_includes result, 'リチウム'   # alkali_metal
          refute_includes result, '水素'       # nonmetal
        end

        # ----------------------------------------------------------------
        # コードブロック内のQueryStreamはスキップされる
        # ----------------------------------------------------------------
        def test_should_not_expand_inside_code_block
          content = "```\n= books\n```\n"
          result = render(content)

          assert_equal content, result
        end

        # ----------------------------------------------------------------
        # エラーハンドリング
        # ----------------------------------------------------------------

        # 存在しないデータファイルは元の行を残して処理を継続する
        def test_should_keep_line_and_continue_for_missing_data_file
          content = "前の行\n= nonexistent\n後の行\n"
          result = render(content)

          assert_includes result, '前の行'
          assert_includes result, '= nonexistent'  # 元の行が残る
          assert_includes result, '後の行'
        end

        # 存在しないテンプレートは元の行を残して処理を継続する
        def test_should_keep_line_and_continue_for_missing_template
          content = "前の行\n= books | :nonexistent_style\n後の行\n"
          result = render(content)

          assert_includes result, '前の行'
          assert_includes result, '= books | :nonexistent_style'  # 元の行が残る
          assert_includes result, '後の行'
        end

        # 複数のQueryStream記法があるとき、1つが失敗しても残りは展開される
        def test_should_continue_expanding_after_error
          content = <<~MD
            = books | tags=ruby && tags=beginner
            = books | :shart
            = books | tags=c
          MD
          result = render(content)

          assert_includes result, '楽しいRuby'          # 1行目は展開される
          assert_includes result, '= books | :shart'   # 2行目は元の行が残る
          assert_includes result, 'はじめてのC'          # 3行目は展開される
        end

        # 一件検索で0件の場合は空文字列になる
        def test_should_return_empty_for_zero_results_single_lookup
          content = "= book | 存在しない本\n"
          result = render(content)

          # QueryStream 行は空に置換されるが、前後のコンテンツは保持
          refute_includes result, '存在しない本'
        end

        # ----------------------------------------------------------------
        # パイプライン統合
        # ----------------------------------------------------------------

        # 通常のMarkdownテキストとQueryStreamが共存できる
        def test_should_preserve_surrounding_content
          content = <<~MD
            # 参考書籍

            この章では参考書籍を紹介します。

            = books | tags=ruby && tags=beginner

            次の章では都道府県データを扱います。
          MD

          result = render(content)

          assert_includes result, '# 参考書籍'
          assert_includes result, 'この章では参考書籍を紹介します。'
          assert_includes result, '楽しいRuby'
          assert_includes result, '次の章では都道府県データを扱います。'
        end

        # 複数のQueryStreamが同一ファイル内で展開できる
        def test_should_expand_multiple_query_streams
          content = <<~MD
            = books | tags=ruby && tags=beginner

            ---

            = prefectures | region=関東
          MD

          result = render(content)

          assert_includes result, '楽しいRuby'
          assert_includes result, '東京都'
          assert_includes result, '---'
        end

        # ----------------------------------------------------------------
        # VFM フェンス記法統合テスト
        # ----------------------------------------------------------------

        # :card スタイルでフェンス付きテンプレートが正しく展開される
        def test_should_expand_books_with_card_style
          content = "## Books\n\n= books | tags=ruby && tags=beginner | :card\n\n次へ\n"
          result = render(content)

          # タグ絞り込みで1件のみ → フェンスも1回
          assert_equal 1, result.scan(':::{.book-card}').size
          assert_includes result, '**楽しいRuby**'
          assert_includes result, '## Books'
          assert_includes result, '次へ'
        end

        # :card スタイルで全件展開した場合、各レコードが個別フェンスを持つ
        def test_should_expand_all_books_with_card_style
          content = "= books | :card\n"
          result = render(content)

          # 4件の書籍データがあり、各自フェンスを持つ
          fence_count = result.scan(':::{.book-card}').size
          assert_operator fence_count, :>, 1, '複数レコードが個別フェンスを持つべき'
        end

        # フェンス付きテンプレートで nil cover の行がスキップされる
        def test_should_skip_nil_cover_inside_fence
          content = "= book | はじめてのC | :card\n"
          result = render(content)

          assert_includes result, ':::{.book-card}'
          assert_includes result, '**はじめてのC**'
          refute_includes result, '![]()'
        end

        private

        # テスト用のrender ヘルパー
        def render(content)
          DataRender.process(
            content,
            source_filename: 'test.md',
            data_dir: FIXTURE_DATA_DIR,
            templates_dir: FIXTURE_TEMPLATES_DIR
          )
        end
      end

      # ================================================================
      # 5. データ画像解決の配線（post_render 注入）統合テスト
      # ================================================================
      # chapter_slug を渡すと DataImageResolver が post_render として働き、
      # data/ 配下のデータ画像が images/data/… へ書き換わることを end-to-end で検証する
      # （querystream-data-images-spec.md §3.3・§4-1）。
      class DataRenderDataImageWiringTest < Minitest::Test
        require 'tmpdir'
        require 'fileutils'

        # cwd 相対の data/ ・templates/ を組み立てて DataRender.process を通す
        def in_project
          Dir.mktmpdir('vs-data-image-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('data/books')
              File.write('data/books.yml', <<~YAML)
                - title: 楽しいRuby
                  cover: ruby.webp
              YAML
              FileUtils.mkdir_p('templates')
              File.write('templates/_book.md', "### = title\n![](cover)\n")
              yield
            end
          end
        end

        # chapter_slug 指定時、data/books/ の画像が images/data/books/… へ書き換わる
        def test_should_rewrite_data_image_when_chapter_slug_given
          in_project do
            File.write('data/books/ruby.webp', 'WEBP')

            result = DataRender.process(
              "= books\n",
              source_filename: '10-intro.md',
              chapter_slug: '10-intro',
              data_dir: 'data',
              templates_dir: 'templates'
            )

            assert_includes result, '![](images/data/books/ruby.webp)'
            assert File.exist?(
              File.join(Common::BUILD_HTML_DIR, 'images', 'data', 'books', 'ruby.webp')
            ), 'ワークスペースへ実体がコピーされるべき'
          end
        end

        # chapter_slug 未指定（既定 nil）なら解決せず素のファイル名のまま
        def test_should_not_rewrite_without_chapter_slug
          in_project do
            File.write('data/books/ruby.webp', 'WEBP')

            result = DataRender.process(
              "= books\n",
              source_filename: '10-intro.md',
              data_dir: 'data',
              templates_dir: 'templates'
            )

            assert_includes result, '![](ruby.webp)'
            refute_includes result, 'images/data/'
          end
        end
      end
    end
  end
end
