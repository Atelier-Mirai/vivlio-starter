# frozen_string_literal: true

# ================================================================
# Test: lint/rulesets_test.rb
# ================================================================
# テスト対象:
#   Lint::Rulesets（lib/vivlio_starter/cli/lint/rulesets.rb。v2-architecture-spec.md §6）
#   - technical は小説の規則のほかは何も切らない（今の一組。本書の vs lint の指摘が変わらない）
#   - minimal は文体の規則と小説の規則を切り、誤字・表記の揺れ・記法の取り違えの規則は残す
#   - novel は minimal に小説の規則（novel-vertical-spec.md §6.2）を足したもの
#   - 組に書いた名前が、実在の規則かプリセットの名前である（綴りの誤りは何も切らないので）
#   - BookProfile の種類の既定値が指す組がある
# ================================================================

require 'test_helper'
require 'yaml'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/lint'

module VivlioStarter
  module CLI
    class LintRulesetsTest < Minitest::Test
      TEXTLINTRC = File.expand_path('../../../../config/.textlintrc.yml', __dir__)

      def test_technical_should_disable_only_the_novel_rules
        assert_equal Lint::NovelChecker::RULES, Lint::Rulesets.disabled_by('technical')
        assert_equal Lint::NovelChecker::RULES, Lint::Rulesets.disabled_by(nil), '書かなければ technical'
        assert_equal Lint::NovelChecker::RULES, Lint::Rulesets.disabled_by('  ')
      end

      def test_minimal_should_keep_typo_spelling_and_notation_rules
        disabled = Lint::Rulesets.disabled_by('minimal')
        prose = Lint::ProseChecker

        [prose::MAZEGAKI_RULE, prose::KANJI_LOOKALIKE_RULE, prose::KANSUJI_COUNTER_RULE,
         prose::INDENTED_CODE_RULE, prose::SETEXT_RULE, prose::UNCLOSED_SUPPRESSION_RULE,
         'prh', 'spellcheck-tech-word'].each { refute_includes disabled, it }
        [prose::SENTENCE_LENGTH_RULE, prose::WEAK_PHRASE_RULE, 'preset-ja-technical-writing'].each do
          assert_includes disabled, it
        end
      end

      def test_novel_should_be_minimal_plus_the_novel_rules
        minimal = Lint::Rulesets.disabled_by('minimal')

        assert_equal minimal - Lint::NovelChecker::RULES, Lint::Rulesets.disabled_by('novel')
        assert_empty Lint::NovelChecker::RULES - minimal, 'minimal は小説の規則を切る'
      end

      def test_should_raise_for_an_unknown_ruleset
        error = assert_raises(KeyError) { Lint::Rulesets.disabled_by('novle') }
        assert_includes error.message, 'novle'
      end

      def test_every_disabled_name_should_be_a_real_rule_or_preset
        prose_rules = Lint::ProseChecker.constants.filter_map do |name|
          name.end_with?('_RULE') ? Lint::ProseChecker.const_get(name) : nil
        end
        presets = YAML.safe_load_file(TEXTLINTRC).fetch('rules').keys.grep(/\Apreset-/)
        unknown = Lint::Rulesets::TABLE.values.flatten.uniq - prose_rules - Lint::NovelChecker::RULES - presets

        assert_empty unknown, '綴りを誤った名前は何も切らない'
      end

      def test_should_cover_the_rulesets_named_by_book_profiles
        named = BookProfile::PROFILES.values.filter_map { it[%i[lint ruleset]] }

        assert_empty named.map(&:to_sym) - Lint::Rulesets.names
      end
    end
  end
end
