# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'

module VivlioStarter
  module CLI
    # vs doctor は Node.js が「在る」だけでなく、Vivliostyle CLI の要求する版かを見る
    # （改善案.md #52）。古い Node は ✅ のまま vivliostyle が動かないため。
    class DoctorNodeVersionTest < Minitest::Test
      VIVLIOSTYLE_PACKAGE = File.expand_path('../../../node_modules/@vivliostyle/cli/package.json', __dir__)

      # 下限は Vivliostyle CLI の engines.node と一致していること。
      # Vivliostyle を上げて要求が変わったら、ここで気づいて NODE_MIN_VERSION を追随させる。
      def test_min_version_should_match_vivliostyle_engines
        skip 'node_modules に @vivliostyle/cli がありません（npm install 前）' unless File.exist?(VIVLIOSTYLE_PACKAGE)

        engines = JSON.parse(File.read(VIVLIOSTYLE_PACKAGE)).dig('engines', 'node')

        assert_equal ">=#{DoctorCommands::NODE_MIN_VERSION}", engines
      end

      def test_should_judge_versions_below_the_minimum_as_too_old
        assert DoctorCommands.node_too_old?(Gem::Version.new('20.19.0'))
        assert DoctorCommands.node_too_old?(Gem::Version.new('22.11.0'))
        refute DoctorCommands.node_too_old?(Gem::Version.new('22.12.0'))
        refute DoctorCommands.node_too_old?(Gem::Version.new('26.9.0'))
      end

      # 版が分からない（node が無い・出力を読めない）ときは言い立てない
      def test_should_not_judge_an_unknown_version_as_too_old
        refute DoctorCommands.node_too_old?(nil)
      end

      # 案内には、そのまま打てる更新コマンドと、Homebrew 以外で入れた人への道筋を添える
      def test_should_tell_how_to_update_in_the_warning
        warned = nil
        Common.stub :log_warn, ->(msg, detail: nil) { warned = [msg, detail] } do
          DoctorCommands.report_node_outdated(Gem::Version.new('20.19.0'))
        end

        assert_includes warned[0], '20.19.0'
        assert_includes warned[0], DoctorCommands::NODE_MIN_VERSION
        assert_includes warned[1], 'brew upgrade node'
        assert_includes warned[1], 'nvm'
      end
    end
  end
end
