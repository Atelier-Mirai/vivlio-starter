# frozen_string_literal: true

require 'tmpdir'

require_relative '../../../test_helper'
require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/techbook/processor'

module VivlioStarter
  module CLI
    module Techbook
      class ProcessorTest < Minitest::Test
        FIXTURES_DIR = File.expand_path('fixtures/twemoji', __dir__)

        def test_should_enable_when_techbook_true
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)

          assert processor.enabled?
        end

        def test_should_disable_when_techbook_false
          config = Common.wrap_config({ output: { pdf: { techbook: false } } })
          processor = Processor.new(config)

          refute processor.enabled?
        end

        def test_should_disable_when_techbook_omitted
          config = Common.wrap_config({})
          processor = Processor.new(config)

          refute processor.enabled?
        end

        def test_should_return_html_unchanged_when_disabled
          config = Common.wrap_config({ output: { pdf: { techbook: false } } })
          processor = Processor.new(config)
          html = "<p>Hello World ✅</p>"

          result = processor.process(html)

          assert_equal html, result
        end

        def test_should_inject_emoji_css_when_enabled
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)

          css = processor.inject_css

          assert_includes css, "img.vs-emoji"
          assert_includes css, "display: inline"
          assert_includes css, "width: 1em"
          assert_includes css, "height: 1em"
          assert_includes css, "vertical-align: -0.15em"
          assert_includes css, "border: none !important"
        end

        def test_should_inject_css_marker_images_when_enabled
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)

          css = processor.inject_css

          assert_includes css, '--h3-marker: url("stylesheets/twemoji/vs-techbook/marker-h3.webp") !important;'
          assert_includes css, '--h4-marker: url("stylesheets/twemoji/vs-techbook/marker-h4.webp") !important;'
          assert_includes css, 'background-image: var(--h3-marker) !important;'
          assert_includes css, 'background-image: var(--h4-marker) !important;'
          assert_includes css, '--subtitle-wave-image: url("stylesheets/twemoji/vs-techbook/wave.webp") !important;'
          assert_includes css, '--code-font: var(--font-code);'
          refute_includes css, '-webkit-text-stroke: 0 !important;'
          refute_includes css, 'mask-image'
        end

        def test_should_return_empty_css_when_disabled
          config = Common.wrap_config({ output: { pdf: { techbook: false } } })
          processor = Processor.new(config)

          css = processor.inject_css

          assert_equal "", css
        end

        def test_should_inject_both_emoji_and_font_css
          config = Common.wrap_config({
            output: {
              pdf: {
                techbook: true,
                variable_fonts: [
                  {
                    family: "Noto Sans JP",
                    src: "fonts/NotoSansJP-VF.woff2",
                    instances: [
                      { weight: 400, settings: '"wght" 400' },
                      { weight: 700, settings: '"wght" 700' }
                    ]
                  }
                ]
              }
            }
          })
          processor = Processor.new(config)

          css = processor.inject_css

          assert_includes css, "img.vs-emoji"
          assert_includes css, "@font-face"
          assert_includes css, "Noto Sans JP-400"
          assert_includes css, "Noto Sans JP-700"
        end

        def test_should_process_html_with_mixed_emoji_and_text
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)

          # Use EmojiReplacer with fixtures dir directly to verify the full pipeline
          replacer = EmojiReplacer.new(FIXTURES_DIR)
          html = "<p>Check ✅ and text</p>"

          # Verify Processor is enabled and would delegate to EmojiReplacer
          assert processor.enabled?

          # Verify EmojiReplacer (which Processor delegates to) produces img tags
          result = replacer.process(html)
          assert_includes result, '<img src='
          assert_includes result, 'class="emoji vs-emoji"'
          assert_includes result, "and text"
          assert result.start_with?("<p>")
          assert result.end_with?("</p>")
        end

        def test_should_replace_wave_dash_with_fullwidth_tilde
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)
          html = "<p>10〜20ページ</p>"

          result = processor.process(html)

          refute_includes result, "\u301C"
          assert_includes result, "\uFF5E"
          assert_includes result, "10～20ページ"
        end

        def test_should_post_process_html_files_idempotently
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)

          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write('sample.html', "<html><head></head><body><p>10〜20</p></body></html>")

              processor.post_process_html_files!(['sample.html'])
              first = File.read('sample.html')
              processor.post_process_html_files!(['sample.html'])
              second = File.read('sample.html')

              assert_equal first, second
              assert_equal 1, second.scan('Vivlio Starter Techbook CSS BEGIN').count
              refute_includes second, "\u301C"
              assert_includes second, "10～20"
            end
          end
        end

        def test_should_normalize_subsection_marker_spans_for_css_rendering
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)

          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write('sample.html', '<html><head></head><body><h3><span class="subsection-marker">♣</span><span>Title</span></h3></body></html>')

              processor.post_process_html_files!(['sample.html'])
              result = File.read('sample.html')

              assert_includes result, '<span class="subsection-marker" aria-hidden="true" role="presentation"></span>'
              refute_includes result, 'alt="♣"'
            end
          end
        end

        def test_should_replace_circled_numbers_with_webp_images
          config = Common.wrap_config({ output: { pdf: { techbook: true } } })
          processor = Processor.new(config)
          html = "<p>① 手順と⑩補足</p>"

          result = processor.process(html)

          refute_includes result, "①"
          refute_includes result, "⑩"
          assert_includes result, '<img src="stylesheets/twemoji/vs-techbook/circled-1.webp" alt="1" aria-label="1" class="emoji vs-emoji vs-circled-number"'
          assert_includes result, '<img src="stylesheets/twemoji/vs-techbook/circled-10.webp" alt="10" aria-label="10" class="emoji vs-emoji vs-circled-number"'
        end

        def test_should_not_replace_wave_dash_when_disabled
          config = Common.wrap_config({ output: { pdf: { techbook: false } } })
          processor = Processor.new(config)
          html = "<p>10〜20ページ</p>"

          result = processor.process(html)

          assert_includes result, "\u301C"
        end
      end
    end
  end
end
