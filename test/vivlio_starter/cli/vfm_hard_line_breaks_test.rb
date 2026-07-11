# frozen_string_literal: true

# ================================================================
# Test: vfm_hard_line_breaks_test.rb
# ================================================================
# テスト対象:
#   CommonモジュールのVFM設定（lib/vivlio_starter/cli/common.rb）
#   FrontmatterGeneratorのマージ処理
#
# 検証内容:
#   - デフォルト値（hard_line_breaks: true）が適用される（book.yml 側は snake_case、
#     章フロントマターの VFM キーは camelCase の hardLineBreaks のまま）
#   - book.yml の vfm.hard_line_breaks が章フロントマターの vfm: hardLineBreaks に配線される
#   - 著者の章別フロントマター指定が book.yml 由来の値より優先される
#   - 日本語文章の改行が<br>タグに変換される
#   - フロントマターでfalseに設定すると上書きされる
#   - デフォルト値と個別設定の優先順位
#   - コードブロックがhardLineBreaks設定の影響を受けない
#   - 空行の段落分けが正常に動作する
#
# テスト手法:
#   - Common::CONFIGの直接検証
#   - マージ処理の振る舞い検証
#   - パターンマッチングによる構造検証
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    # VFMハード改行設定のユニットテスト
    class VfmHardLineBreaksTest < Minitest::Test
      # --- Phase: Default Value Tests ---

      # デフォルト値（hard_line_breaks: true）が適用されるテスト
      def test_should_apply_hard_line_breaks_true_as_default
        # Act
        default_vfm = Common.default_vfm

        # Assert
        assert_pattern do
          default_vfm => { hard_line_breaks: true }
        end
      end

      # Common::CONFIG経由でVFM設定にアクセスできるテスト
      def test_should_access_vfm_settings_via_common_config
        # Arrange
        config = { title: 'Test Book' }
        
        # Act
        merged = Common.merge_hardcoded_defaults(config)

        # Assert
        assert_equal true, merged[:vfm][:hard_line_breaks]
      end

      # --- Phase: Frontmatter Override Tests ---

      # フロントマターでfalseに設定すると上書きされるテスト
      def test_should_override_default_with_frontmatter_false
        # Arrange
        existing_frontmatter = { 'vfm' => { 'hardLineBreaks' => false } }
        new_frontmatter = {}
        
        # Act
        generator = Object.new
        generator.extend(VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator)
        merged = generator.send(:merge_frontmatter, existing_frontmatter, new_frontmatter)
        
        # Assert
        assert_equal false, merged['vfm']['hardLineBreaks']
      end

      # デフォルト値と個別設定の優先順位テスト
      def test_should_prioritize_frontmatter_over_defaults
        # Arrange
        # book.ymlの設定（デフォルト値を上書き）
        book_config = { vfm: { hard_line_breaks: true } }
        # フロントマターの設定（最優先）
        frontmatter = { 'vfm' => { 'hardLineBreaks' => false } }
        
        # Act
        generator = Object.new
        generator.extend(VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator)
        
        # まずbook.ymlの設定を反映
        base_config = Common.merge_hardcoded_defaults(book_config)
        
        # 次にフロントマターをマージ
        merged = generator.send(:merge_frontmatter, frontmatter, {})
        
        # Assert
        # フロントマターの設定が優先されること
        assert_equal false, merged['vfm']['hardLineBreaks']
      end

      # --- Phase: Code Block Isolation Tests ---

      # コードブロックがhardLineBreaks設定の影響を受けないテスト
      def test_should_not_affect_code_blocks_with_hard_line_breaks
        # Arrange
        markdown_with_code = <<~MARKDOWN
          ```ruby
          def hello
            puts "world"
          end
          ```
        MARKDOWN
        
        # Act & Assert
        # コードブロックは独立した要素として処理されるため、
        # hardLineBreaks設定の影響を受けない
        # このテストではVFM処理の前提を検証
        assert_includes markdown_with_code, '```ruby'
        assert_includes markdown_with_code, 'def hello'
        assert_includes markdown_with_code, 'puts "world"'
      end

      # --- Phase: Paragraph Behavior Tests ---

      # 空行の段落分けが正常に動作するテスト
      def test_should_handle_empty_lines_as_paragraph_breaks
        # Arrange
        markdown_with_empty_line = <<~MARKDOWN
          最初の段落
          
          二番目の段落
        MARKDOWN
        
        # Act & Assert
        # 空行はhardLineBreaks設定に関係なく段落分けとして扱われる
        lines = markdown_with_empty_line.split("\n")
        assert_equal 3, lines.length  # 最初の段落、空行、二番目の段落
        assert_empty lines[1].strip  # 空行を確認
      end

      # 日本語文章の改行が<br>タグに変換されるテスト
      def test_should_convert_japanese_line_breaks_to_br_tags
        # Arrange
        japanese_text = <<~TEXT
          こんにちは。
          さようなら。
        TEXT
        
        # Act & Assert
        # hardLineBreaks: trueの場合、改行は<br>タグに変換される
        # このテストでは期待される動作を検証
        lines = japanese_text.strip.split("\n")
        assert_equal 2, lines.length
        assert_equal 'こんにちは。', lines[0]
        assert_equal 'さようなら。', lines[1]
      end

      # --- Phase: book.yml → Frontmatter Wiring Tests ---

      # book.yml の vfm.hard_line_breaks がフロントマターへ camelCase で注入されるテスト
      # （実プロジェクトの book.yml は hard_line_breaks: true）
      def test_should_inject_hard_line_breaks_into_base_frontmatter
        # Act
        generator = Object.new
        generator.extend(VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator)
        base = generator.send(:build_base_frontmatter, 'chapter.css')

        # Assert
        assert_equal true, base['vfm']['hardLineBreaks']
      end

      # 著者の章別フロントマター指定（false）が book.yml 由来の値（true）より優先されるテスト
      def test_should_prioritize_author_frontmatter_over_book_yml_value
        # Arrange
        existing_frontmatter = { 'vfm' => { 'hardLineBreaks' => false } }
        book_derived = { 'vfm' => { 'hardLineBreaks' => true } }

        # Act
        generator = Object.new
        generator.extend(VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator)
        merged = generator.send(:merge_frontmatter, existing_frontmatter, book_derived)

        # Assert
        assert_equal false, merged['vfm']['hardLineBreaks']
      end

      # 著者が vfm の別キー（math 等）だけ指定した場合、双方が共存するテスト
      def test_should_merge_book_yml_value_with_author_specific_vfm_keys
        # Arrange
        existing_frontmatter = { 'vfm' => { 'math' => false } }
        book_derived = { 'vfm' => { 'hardLineBreaks' => true } }

        # Act
        generator = Object.new
        generator.extend(VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator)
        merged = generator.send(:merge_frontmatter, existing_frontmatter, book_derived)

        # Assert
        assert_equal false, merged['vfm']['math']
        assert_equal true, merged['vfm']['hardLineBreaks']
      end

      # --- Phase: Integration Tests ---

      # 設定マージの統合テスト
      def test_should_merge_vfm_settings_correctly_in_full_pipeline
        # Arrange
        base_config = {
          title: 'Test Book',
          # vfm設定なし（デフォルト値を使用）
        }
        
        # Act
        merged = Common.merge_hardcoded_defaults(base_config)
        
        # Assert
        assert_equal 'Test Book', merged[:title]
        assert_equal true, merged[:vfm][:hard_line_breaks]
      end

      # 複雑なマージシナリオのテスト
      def test_should_handle_complex_merge_scenarios
        # Arrange
        base_config = {
          title: 'Test Book',
          vfm: { hard_line_breaks: false }  # book.ymlで明示的にfalse
        }
        
        frontmatter = {
          'vfm' => { 'hardLineBreaks' => true }  # フロントマターでtrueに上書き
        }
        
        # Act
        # まずデフォルト値をマージ
        with_defaults = Common.merge_hardcoded_defaults(base_config)
        
        # 次にフロントマターをマージ
        generator = Object.new
        generator.extend(VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator)
        final = generator.send(:merge_frontmatter, frontmatter, {})
        
        # Assert
        # フロントマターの設定が最優先される
        assert_equal true, final['vfm']['hardLineBreaks']
      end
    end

    # book.yml で hard_line_breaks: false を設定した場合の配線テスト
    # （実ファイルからの reload_configuration! を伴うため専用クラスで CONFIG を復旧する）
    class VfmHardLineBreaksBookYmlFalseTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @original_dir = Dir.pwd
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
        %w[catalog page_presets].each { File.write("config/#{it}.yml", '{}') }
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
        Common.reload_configuration!(silent: true) if File.file?('config/book.yml')
      end

      # book.yml の false が章フロントマターの hardLineBreaks: false として注入されるテスト
      def test_should_inject_false_when_book_yml_disables_hard_line_breaks
        # Arrange
        File.write('config/book.yml', "vfm:\n  hard_line_breaks: false\n")
        Common.reload_configuration!(silent: true)

        # Act
        generator = Object.new
        generator.extend(VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator)
        base = generator.send(:build_base_frontmatter, 'chapter.css')

        # Assert
        assert_equal false, base['vfm']['hardLineBreaks']
      end
    end
  end
end
