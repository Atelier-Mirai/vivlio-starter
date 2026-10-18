# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/cli/build/kindle_previewer_notice_test.rb
#
# Kindle を選んだ本で Kindle Previewer が無いときだけ、vs build・vs preflight の終わりに
# vs doctor --fix で入れられることを 💡 で知らせる（改善案.md #87）。
# =============================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build/kindle_previewer_notice'

module VivlioStarter
  module CLI
    module Build
      class KindlePreviewerNoticeTest < Minitest::Test
        def test_should_point_to_doctor_fix_when_kindle_is_chosen_but_missing
          lines = notice(kindle: true, available: false)

          assert lines.first.start_with?('💡'), '原稿の誤りではないので 💡'
          assert_includes lines.join("\n"), 'vs doctor --fix'
        end

        def test_should_say_nothing_when_kindle_previewer_is_installed
          assert_empty notice(kindle: true, available: true)
        end

        def test_should_say_nothing_when_kindle_is_not_chosen
          assert_empty notice(kindle: false, available: false)
        end

        private

        def notice(kindle:, available:)
          targets = Targets.new(pdf: true, print_pdf: false, epub: false, kindle:)
          lines = []
          Common.with_emit_sink(lines) { KindlePreviewerNotice.report(targets:, available: -> { available }) }
          lines
        end
      end
    end
  end
end
