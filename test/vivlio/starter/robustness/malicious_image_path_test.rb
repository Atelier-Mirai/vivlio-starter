# frozen_string_literal: true

# ================================================================
# robustness: 画像パスにディレクトリトラバーサルや HTML 特殊文字
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 2-3-4 (L116): 画像パスに `../../etc/passwd`
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 期待される挙動（仕様書本文）:
#   ✅ Markdown としては単に画像が無い扱い。
#   **rsvg/imagemagick 等が何を読むか**を実測し、サンドボックスが必要か判断
#
# 本テストで検証する範囲:
#   1. `fix_image_paths` はトラバーサル入力で例外を投げず、プレースホルダーに置換する
#   2. プロジェクト外ファイル（例: /etc/hosts）が images/ 外に存在しても、
#      ImagePathNormalizer はこれを「画像あり」扱いしない（= trueと誤判定しない）
#   3. 生成される data: URI に危険文字（`<`, `"`, HTMLインジェクション）が含まれない
#   4. パスにヌルバイト・改行・シェルメタ文字があっても例外を投げず placeholder に倒れる
#
# 本テストの範囲外（別タスク）:
#   - rsvg / imagemagick 等の外部レンダラにおけるパス解決は、ビルドパイプライン全体の
#     E2E で検証すべきであり、本ユニットテストのスコープ外とする。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/pre_process/image_path_normalizer'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        class MaliciousImagePathTest < Minitest::Test
          # ----------------------------------------------------------------
          # 1. トラバーサル入力で例外を投げず、placeholder に倒れる
          # ----------------------------------------------------------------
          def test_path_traversal_is_replaced_with_placeholder_without_raising
            within_project do
              content  = "# heading\n\n![secrets](../../etc/passwd)\n"
              filename = '05-security.md'

              result = nil
              captured = capture_stdout do
                result = ImagePathNormalizer.fix_image_paths(content, filename)
              end

              # placeholder (data: URI) に置換されていること
              assert_match %r{!\[secrets\]\(data:image/svg\+xml[^)]+\)}, result,
                           'トラバーサル入力はプレースホルダー data: URI に置換されるべき'

              # 原文のパスは Markdown 記法として残っていない
              refute_includes result, '(../../etc/passwd)',
                              '原文のトラバーサルパスが記法として残ってはいけない'

              # 「見つかりません」の警告が出ていること
              assert(captured.any? { it.include?('見つかりません') },
                     '見つからない画像として警告が出るべき')
            end
          end

          # ----------------------------------------------------------------
          # 2. プロジェクト外ファイルは「画像あり」と誤判定されない
          # ----------------------------------------------------------------
          # `image_exists_for?` は `File.expand_path(..., IMAGES_DIR)` で解決するため、
          # `../` を多数含むパスは images/ の外に出るが、対応拡張子（.webp/.png/.jpg/.jpeg）でない
          # 実ファイルを指していれば false を返す。`/etc/hosts` は拡張子が無いため対応拡張子なし
          # → 絶対に false になるべき。
          def test_image_exists_for_rejects_out_of_tree_paths_without_valid_extension
            within_project do
              # images/<chapter>/../../../../etc/hosts 相当のパス
              # 実マシン上に /etc/hosts は存在するが、拡張子が対応外なので false
              normalized = 'images/05-security/../../../../etc/hosts'
              refute ImagePathNormalizer.image_exists_for?(normalized),
                     'プロジェクト外の拡張子なしファイルを "画像あり" と判定してはならない'
            end
          end

          # ----------------------------------------------------------------
          # 3. placeholder SVG に危険文字がエスケープ済みで埋め込まれる
          # ----------------------------------------------------------------
          # sanitize_placeholder_text は CGI.escapeHTML を通すため、
          # `<script>` 等は `&lt;script&gt;` に変換される。
          # さらに最終 data URI は CGI.escape で URL エンコードされ、
          # 生の `<` や `"` は残らない。
          def test_placeholder_escapes_html_special_characters_in_filename
            sanitized = ImagePathNormalizer.sanitize_placeholder_text('<script>alert(1)</script>')
            refute_includes sanitized, '<script>', '生の <script> タグが残ってはいけない'
            refute_includes sanitized, '</script>', '生の閉じタグが残ってはいけない'
            assert_includes sanitized, '&lt;', '< は HTML エンティティに変換されるべき'
          end

          def test_placeholder_data_uri_does_not_contain_raw_injection_payload
            # 生成される placeholder の最終 data URI を検査
            data_uri = ImagePathNormalizer.placeholder_image_path('<script>alert(1)</script>.webp')
            assert data_uri.start_with?('data:image/svg+xml;charset=utf-8,'),
                   'data URI 形式で返るべき'
            # URL エンコード済みのため、生の < や " は含まれない
            refute_includes data_uri, '<', '生の < が URI に含まれてはいけない'
            refute_includes data_uri, '"', '生の " が URI に含まれてはいけない'
            refute_includes data_uri, 'alert(1)', '生の JS ペイロードが含まれてはいけない'
          end

          # ----------------------------------------------------------------
          # 4. ヌルバイト・改行・シェルメタ文字で落ちない
          # ----------------------------------------------------------------
          def test_bizarre_paths_do_not_raise
            bizarre_paths = [
              'foo\x00bar.png',               # ヌルバイト風リテラル
              'foo;rm -rf /.png',             # シェル区切り（Markdown に直書き）
              '$(whoami).png',                # コマンド置換風
              '`date`.png',                   # バッククォート
              'foo\nbar.png'                  # リテラル改行
            ]

            within_project do
              bizarre_paths.each do |path|
                content = "![x](#{path})\n"
                result = nil
                capture_stdout do
                  result = ImagePathNormalizer.fix_image_paths(content, '05-security.md')
                end
                assert_match %r{!\[x\]\(data:image/svg\+xml[^)]+\)}, result,
                             "異常パス #{path.inspect} は placeholder に倒れるべき"
              end
            end
          end

          private

          # images/ ディレクトリが存在する作業ディレクトリで yield
          def within_project
            Dir.mktmpdir('vs-robustness-malicious-image-') do |root|
              FileUtils.mkdir_p(File.join(root, 'images'))
              Dir.chdir(root) { yield }
            end
          end

          def capture_stdout
            original = $stdout
            captured = StringIO.new
            $stdout = captured
            yield
            captured.string.lines.map(&:chomp)
          ensure
            $stdout = original
          end
        end
      end
    end
  end
end
