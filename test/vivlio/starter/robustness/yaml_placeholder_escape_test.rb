# frozen_string_literal: true

# ================================================================
# robustness: YAML プレースホルダエスケープ
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 3-2-1 (L155): 著者名に `'`（シングルクォート）を含めても book.yml が壊れない
#   - 3-2-2 (L156): 著者名に改行（ペースト事故）を含めても book.yml が壊れない
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 目的:
#   `vs new` のプレースホルダ置換が「想定外の入力」を受け取っても book.yml を
#   有効な YAML として保つことを回帰的に検証する。
#   プロダクション実装（`lib/vivlio/starter/cli/new.rb` の yaml_escape_double_quoted）
#   は第一段階で導入済み。本テストは robustness 観点で追加の攻撃的入力を検証する。
#
# 検証方針:
#   1. `yaml_escape_double_quoted` を単体で呼び出し、出力が YAML double-quoted
#      リテラルとしてパース可能であることを確認（ユニットレイヤー）。
#   2. 実際の `rewrite_book_yml` パスを通し、最終 book.yml が `YAML.safe_load`
#      に成功し、値が元の文字列として復元できることを確認（統合レイヤー）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio/starter/cli/new'

module Vivlio
  module Starter
    module CLI
      class YamlPlaceholderEscapeTest < Minitest::Test
        # scaffold book.yml 冒頭と同じ double-quoted プレースホルダ形式を最小構成で再現。
        # 実際の scaffold を使うとファイルサイズと依存関係が大きくなるため、
        # 挙動検証に必要最小限の 5 プレースホルダだけを持つ YAML を用意する。
        MINIMAL_TEMPLATE = <<~YAML
          book:
            main_title: "{{MAIN_TITLE}}"
            subtitle: "{{SUBTITLE}}"
            author: "{{AUTHOR}}"
            publisher: "{{PUBLISHER}}"
          project:
            name: "{{PROJECT_NAME}}"
        YAML

        # ----------------------------------------------------------------
        # ユニットレイヤー: yaml_escape_double_quoted 単体
        # ----------------------------------------------------------------

        # 3-2-1: シングルクォート `'` は scaffold が double-quoted を採用しているため
        # そのまま通過してよい（エスケープ不要）。後段の YAML パーサで再現できること。
        def test_escape_single_quote_passes_through_in_double_quoted_context
          escaped = NewCommands.send(:yaml_escape_double_quoted, "O'Reilly")
          yaml = %(name: "#{escaped}")
          parsed = YAML.safe_load(yaml)

          assert_equal 'O\'Reilly',   escaped, 'シングルクォートはそのまま通過すべき'
          assert_equal "O'Reilly",    parsed['name'], 'YAML 復元値は元文字列と一致すべき'
        end

        # 3-2-2: 改行は \n / \r に変換され、YAML パーサで元の改行として復元される
        def test_escape_embedded_newline_survives_yaml_round_trip
          adversarial = "山田 太郎\n偽著者名"
          escaped = NewCommands.send(:yaml_escape_double_quoted, adversarial)
          yaml = %(author: "#{escaped}")
          parsed = YAML.safe_load(yaml)

          assert_includes escaped, '\\n', 'LF は \\n に変換されるべき'
          refute_includes escaped, "\n",  'エスケープ後文字列に生 LF が残ってはならない'
          assert_equal adversarial, parsed['author'], '復元された author は元の改行入り文字列と一致すべき'
        end

        # CRLF ペースト事故（Windows 由来のクリップボード）
        def test_escape_crlf_paste_accident
          adversarial = "姓\r\n名"
          escaped = NewCommands.send(:yaml_escape_double_quoted, adversarial)
          yaml = %(author: "#{escaped}")
          parsed = YAML.safe_load(yaml)

          assert_includes escaped, '\\r', 'CR は \\r に変換されるべき'
          assert_includes escaped, '\\n', 'LF は \\n に変換されるべき'
          assert_equal adversarial, parsed['author']
        end

        # ダブルクォート自身が YAML リテラルを破壊しないこと
        def test_escape_double_quote_does_not_break_literal
          adversarial = %(Say "Hello")
          escaped = NewCommands.send(:yaml_escape_double_quoted, adversarial)
          yaml = %(title: "#{escaped}")
          parsed = YAML.safe_load(yaml)

          assert_equal adversarial, parsed['title']
        end

        # バックスラッシュの多重エスケープ: `C:\\path\\to` のような Windows パスが壊れないこと
        def test_escape_backslash_is_doubled
          adversarial = 'C:\\path\\to\\book'
          escaped = NewCommands.send(:yaml_escape_double_quoted, adversarial)
          yaml = %(path: "#{escaped}")
          parsed = YAML.safe_load(yaml)

          assert_equal adversarial, parsed['path'], 'Windows パスは元のまま復元されるべき'
        end

        # YAML インジェクション試行: `" injected_key: malicious #` を埋め込んでも
        # 値が 1 つの文字列として保持され、新規キーが生えないこと
        def test_escape_prevents_yaml_key_injection
          adversarial = %(innocent" injected_key: "pwned)
          escaped = NewCommands.send(:yaml_escape_double_quoted, adversarial)
          yaml = %(author: "#{escaped}")
          parsed = YAML.safe_load(yaml)

          assert_equal adversarial, parsed['author']
          refute parsed.key?('injected_key'), 'YAML インジェクションで新キーが生えてはならない'
        end

        # nil / 空文字 / 空白のみ入力でも例外にならず空文字列相当にエスケープされる
        def test_escape_handles_nil_and_blank
          assert_equal '', NewCommands.send(:yaml_escape_double_quoted, nil),     'nil は空文字列に変換されるべき'
          assert_equal '', NewCommands.send(:yaml_escape_double_quoted, ''),      '空文字列は空文字列のまま'
          assert_equal '   ', NewCommands.send(:yaml_escape_double_quoted, '   '), '空白は保持される'
        end

        # マルチバイト文字（日本語・絵文字）は変換されず通過すること
        def test_escape_preserves_multibyte_characters
          adversarial = '山田🎌太郎'
          escaped = NewCommands.send(:yaml_escape_double_quoted, adversarial)

          assert_equal adversarial, escaped, '日本語・絵文字はそのまま通過すべき'
        end

        # ----------------------------------------------------------------
        # 統合レイヤー: rewrite_book_yml 実パスを通した end-to-end 検証
        # ----------------------------------------------------------------

        # 複数の危険文字を同時入力しても、最終 book.yml が有効な YAML で
        # あり、全 5 プレースホルダが正しい値に復元されること
        def test_rewrite_book_yml_with_adversarial_inputs_produces_valid_yaml
          answers = {
            main_title: %(my"book'with"quotes),
            subtitle:   "multi\nline\nsubtitle",
            author:     "C:\\Users\\山田\t太郎",
            publisher:  "quote'mark and \"double\""
          }
          project_name = 'testbook'

          run_rewrite(answers, project_name) do |dest_path|
            # (1) book.yml が有効な YAML としてパースできる
            parsed = nil
            begin
              parsed = YAML.safe_load_file(dest_path)
            rescue Psych::SyntaxError => e
              flunk "book.yml が YAML としてパースできない: #{e.message}\n" \
                    "---generated book.yml---\n#{File.read(dest_path)}"
            end

            # (2) 全プレースホルダが元の入力に復元される
            assert_equal answers[:main_title], parsed.dig('book', 'main_title')
            assert_equal answers[:subtitle],   parsed.dig('book', 'subtitle')
            assert_equal answers[:author],     parsed.dig('book', 'author')
            assert_equal answers[:publisher],  parsed.dig('book', 'publisher')
            assert_equal project_name,         parsed.dig('project', 'name')
          end
        end

        # 3-2-1 specific: 著者名に単一引用符
        def test_rewrite_book_yml_with_single_quote_in_author
          answers = { main_title: 'Book', subtitle: '', author: "O'Reilly 出版", publisher: '' }

          run_rewrite(answers, 'quotebook') do |dest_path|
            parsed = YAML.safe_load_file(dest_path)
            assert_equal "O'Reilly 出版", parsed.dig('book', 'author'),
                         'シングルクォートを含む著者名が復元できるべき'
          end
        end

        # 3-2-2 specific: 著者名の末尾に改行（ペースト時の誤変換）
        def test_rewrite_book_yml_with_trailing_newline_in_author
          answers = { main_title: 'Book', subtitle: '', author: "山田 太郎\n", publisher: '' }

          run_rewrite(answers, 'newlinebook') do |dest_path|
            parsed = YAML.safe_load_file(dest_path)
            assert_equal "山田 太郎\n", parsed.dig('book', 'author'),
                         '末尾改行を含む著者名が復元できるべき'
          end
        end

        # メタ記法攻撃: 著者名に `{{PROJECT_NAME}}` を埋め込んでも二重展開されないこと
        def test_rewrite_book_yml_does_not_expand_nested_placeholder
          answers = { main_title: '{{AUTHOR}}', subtitle: '', author: '{{PROJECT_NAME}}', publisher: '' }

          run_rewrite(answers, 'metabook') do |dest_path|
            parsed = YAML.safe_load_file(dest_path)
            assert_equal '{{AUTHOR}}',       parsed.dig('book', 'main_title'),
                         'main_title 内のメタ記法は再展開されてはならない'
            assert_equal '{{PROJECT_NAME}}', parsed.dig('book', 'author'),
                         'author 内のメタ記法は再展開されてはならない'
            assert_equal 'metabook',         parsed.dig('project', 'name')
          end
        end

        private

        # 最小 YAML テンプレートに対して rewrite_book_yml を実行し、
        # 生成された book.yml のパスをブロックに渡す。一時ディレクトリは自動削除。
        def run_rewrite(answers, project_name)
          Dir.mktmpdir('vs-robustness-yaml-') do |tmp|
            src_path  = File.join(tmp, 'book.yml.src')
            dest_path = File.join(tmp, 'book.yml')
            File.write(src_path, MINIMAL_TEMPLATE, encoding: 'utf-8')

            NewCommands.send(:rewrite_book_yml, nil, src_path, dest_path, answers, project_name)

            yield dest_path
          end
        end
      end
    end
  end
end
