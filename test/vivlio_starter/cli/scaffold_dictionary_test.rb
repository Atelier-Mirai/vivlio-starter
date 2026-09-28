# frozen_string_literal: true

require 'test_helper'
require_relative '../../../lib/vivlio_starter/cli/upgrade'

module VivlioStarter
  module CLI
    # vs new の雛形は、索引辞書を空の初期形で配る（改善案.md #51）。
    #
    # ルートの辞書はこのマニュアルの語で、そのまま配ると、著者が原稿を入れ替えたあとも
    # 辞書だけが残る。空にするのは scripts/copy_to_scaffold.rb で、中身は vs upgrade /
    # vs import が辞書を足すときの初期形（UpgradeCommands::EMPTY_DICTIONARY_TEMPLATES）を
    # 写している。写しがずれたり、同期を忘れたりしたらここで気づく。
    class ScaffoldDictionaryTest < Minitest::Test
      SCAFFOLD_CONFIG = File.expand_path('../../../lib/project_scaffold/config', __dir__)

      def test_should_ship_empty_index_dictionaries_in_scaffold
        %w[index_glossary_terms.yml index_glossary_rejected.yml].each do |basename|
          shipped  = File.read(File.join(SCAFFOLD_CONFIG, basename), encoding: 'utf-8')
          template = UpgradeCommands::EMPTY_DICTIONARY_TEMPLATES.fetch(File.join('config', basename))

          assert_equal template, shipped, "雛形の #{basename} が空の初期形になっていない（copy_to_scaffold.rb を実行したか）"
        end
      end
    end
  end
end
