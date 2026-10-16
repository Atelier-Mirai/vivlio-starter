# frozen_string_literal: true

# ================================================================
# Test: contract/snippet_cheatsheet_consistency_test.rb
# ================================================================
# 記法の見本帳と記法早見表の整合テスト（SC）— 改善案 #112
#
# 付録「記法早見表」（contents/90-notation-cheatsheet.md）は、やりたいことから記法を引く一覧。
# 見本帳（templates/markdown_snippet.md）は、その各行をコピーしてそのまま使える実例で持つ。
# 記法を足すたびに両方を直すことになるので、早見表に載った記法が見本帳にあるかを確かめる。
#
# 検証内容:
#   SC-01: 早見表に出るクラス名（`.tip` など）が、見本帳にもある
#   SC-02: 早見表に出る @ 記法（`@vspace` など）が、見本帳にもある
#   SC-03: 早見表に出る属性（`width=` など）が、見本帳にもある
#   SC-04: クラスでも @ 記法でもない記法（タスクリスト・math のフェンスなど）が、両方にある
# ================================================================

require 'test_helper'

module VivlioStarter
  module CLI
    class SnippetCheatsheetConsistencyTest < Minitest::Test
      REPO_ROOT = File.expand_path('../../..', __dir__)
      CHEATSHEET_PATH = File.join(REPO_ROOT, 'contents', '90-notation-cheatsheet.md')
      SNIPPET_PATH = File.join(REPO_ROOT, 'templates', 'markdown_snippet.md')

      # 早見表で例として出すだけで、記法ではないクラス名
      NOT_NOTATION_CLASSES = %w[myclass].freeze

      # クラスでも @ 記法でもないので、字面で照合する記法。早見表と見本帳とで字面が違うもの
      # （早見表は言語名だけ、見本帳はフェンスごと）は [早見表, 見本帳] の組で書く
      LITERAL_NOTATIONS = [
        '- [ ]',                      # タスクリスト
        ['`math`', '```math'],        # 数式だと明示する
        ['`mermaid`', '```mermaid'],  # 図
        ['`include:', '```include:'], # 外部ファイルの取り込み
        '^[',                         # インライン脚注
        '〘',                         # キー
        '<kbd>',                      # キー（タグ）
        '[!]',                        # コメント行の強調
        '#L5',                        # 行番号を途中から
        '▶',                          # 青コメ
        '❶',                          # 赤コメ
        '``√'                         # 数式をコードのまま見せる
      ].freeze

      def setup
        skip '原稿か見本帳が見つかりません（リポジトリ実体でのみ実行）' unless [CHEATSHEET_PATH, SNIPPET_PATH].all? { File.exist?(it) }
      end

      # SC-01
      def test_should_show_every_cheatsheet_class_in_snippet
        missing = cheatsheet_classes.reject { snippet.match?(/\.#{Regexp.escape(it)}(?![\w-])/) }

        assert_empty missing, message_for('クラス', missing.map { ".#{it}" })
      end

      # SC-02
      def test_should_show_every_cheatsheet_directive_in_snippet
        missing = cheatsheet_directives.reject do |name|
          # `@ch-` はスラッグを続ける前置きなので、後ろに語が続いてよい
          snippet.match?(name.end_with?('-') ? "@#{name}" : /@#{Regexp.escape(name)}(?![\w-])/)
        end

        assert_empty missing, message_for('@ で始まる記法', missing.map { "@#{it}" })
      end

      # SC-03
      def test_should_show_every_cheatsheet_attribute_in_snippet
        missing = cheatsheet_attributes.reject { snippet.include?("#{it}=") }

        assert_empty missing, message_for('属性', missing.map { "#{it}=" })
      end

      # SC-04: 早見表から消えたものは、ここからも外す（照合の対象が古くならないよう、両方にあることを見る）
      def test_should_show_literal_notations_in_both
        absent = LITERAL_NOTATIONS.reject do |notation|
          in_cheatsheet, in_snippet = Array(notation).then { it.size == 1 ? it * 2 : it }
          cheatsheet.include?(in_cheatsheet) && snippet.include?(in_snippet)
        end

        assert_empty absent, <<~MSG
          早見表と見本帳の両方に無い記法があります: #{absent.map { Array(it).last }.join(' ')}
          見本帳へ例を足すか、早見表から外したならこのテストの LITERAL_NOTATIONS からも外してください。
        MSG
      end

      # 抽出が空になったら、早見表の書き方が変わって照合が働いていない
      def test_should_extract_notations_from_cheatsheet
        assert_operator cheatsheet_classes.size, :>=, 30
        assert_includes cheatsheet_directives, 'vspace'
        assert_includes cheatsheet_attributes, 'width'
      end

      private

      def cheatsheet = @cheatsheet ||= File.read(CHEATSHEET_PATH, encoding: 'utf-8')
      def snippet = @snippet ||= File.read(SNIPPET_PATH, encoding: 'utf-8')

      # 表のセルのコード（`…`）だけを見る。``$a^2$`` のようにバッククォートを重ねたものも
      # 1 つのコードとして読む（1 つずつ数えると、後ろのコードの区切りがずれる）
      def code_spans = cheatsheet.scan(/(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)/).map(&:last)

      # `:::{.tip}`・`{.aki}`・`.align-center` の形のクラス名。`custom.css`・`画像.png` の
      # 拡張子は、前に語の文字（和字を含む）があるので拾わない
      def cheatsheet_classes
        code_spans.flat_map { it.scan(%r{(?<![\p{Word}/])\.([a-z][a-z0-9-]*[a-z0-9])}).flatten }
                  .uniq - NOT_NOTATION_CLASSES
      end

      # `@vspace:1.5lh`・`@pageref:ラベル`・`@title` の @ に続く名前。`@ラベル` は和字なので拾わない。
      # `@ch-スラッグ` は `ch-` までを名前とする
      def cheatsheet_directives
        code_spans.flat_map { it.scan(/@([a-z][a-z-]*[a-z]-?)/).flatten }.uniq
      end

      # `{width=50% align=center}` の属性名
      def cheatsheet_attributes
        code_spans.flat_map { it.scan(/\{[^}]*\}/) }.flat_map { it.scan(/([a-z][a-z-]*)=/).flatten }.uniq
      end

      def message_for(kind, missing)
        <<~MSG
          記法早見表にある#{kind}が、見本帳（templates/markdown_snippet.md）にありません: #{missing.join(' ')}
          見本帳へ、コピーしてそのまま使える例を足してください。
        MSG
      end
    end
  end
end
