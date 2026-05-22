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

        def test_should_generate_custom_marker_assets_when_provided_in_config
          config = Common.wrap_config({
            theme: {
              color: "blue",
              markers: {
                h3: "♥",
                h4: "♠"
              }
            },
            output: { pdf: { techbook: true } }
          })
          processor = Processor.new(config)

          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              # Create dummy HTML file to avoid early return
              File.write('sample.html', "<html><head></head><body><p>Test</p></body></html>")
              # Create dummy stylesheets/twemoji directory with 2665.svg and 2660.svg to mimic project
              FileUtils.mkdir_p("stylesheets/twemoji")
              File.write("stylesheets/twemoji/2665.svg", %(<svg viewBox="0 0 36 36"><path fill="#FF0000" d="M12 4 C6 4 2 8 2 14 C2 22 18 34 18 34 C18 34 34 22 34 14 C34 8 30 4 24 4 C20 4 18 8 18 8 C18 8 16 4 12 4 Z"/></svg>))
              File.write("stylesheets/twemoji/2660.svg", %(<svg viewBox="0 0 36 36"><path fill="#000000" d="M18 2 C18 2 2 18 2 24 C2 30 8 34 14 34 L18 34 L22 34 C28 34 34 30 34 24 C34 18 18 2 Z"/></svg>))

              # Mock ResizeCommands.convert_svg_to_webp to do nothing
              mock_resize = Minitest::Mock.new
              mock_resize.expect :call, nil, [Array]
              ResizeCommands.stub :convert_svg_to_webp, mock_resize do
                processor.post_process_html_files!(['sample.html'], inject_css: false)
              end

              h3_svg_path = "stylesheets/twemoji/vs-techbook/marker-h3.svg"
              h4_svg_path = "stylesheets/twemoji/vs-techbook/marker-h4.svg"
              assert File.exist?(h3_svg_path)
              assert File.exist?(h4_svg_path)

              h3_svg = File.read(h3_svg_path)
              h4_svg = File.read(h4_svg_path)

              # Accent color for "blue" is #0ea5e9. Check fill replacement.
              assert_includes h3_svg, 'fill="#0ea5e9"'
              assert_includes h4_svg, 'fill="#0ea5e9"'
              mock_resize.verify
            end
          end
        end

        def test_should_generate_fallback_marker_shapes_for_common_symbols
          config = Common.wrap_config({
            theme: {
              color: "yellow",
              markers: {
                h3: "■",
                h4: "★"
              }
            },
            output: { pdf: { techbook: true } }
          })
          processor = Processor.new(config)

          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              # Create dummy HTML file to avoid early return
              File.write('sample.html', "<html><head></head><body><p>Test</p></body></html>")
              # We do not create twemoji SVG files to force fallback shapes
              FileUtils.mkdir_p("stylesheets/twemoji")

              mock_resize = Minitest::Mock.new
              mock_resize.expect :call, nil, [Array]
              ResizeCommands.stub :convert_svg_to_webp, mock_resize do
                processor.post_process_html_files!(['sample.html'], inject_css: false)
              end

              h3_svg_path = "stylesheets/twemoji/vs-techbook/marker-h3.svg"
              h4_svg_path = "stylesheets/twemoji/vs-techbook/marker-h4.svg"
              assert File.exist?(h3_svg_path)
              assert File.exist?(h4_svg_path)

              h3_svg = File.read(h3_svg_path)
              h4_svg = File.read(h4_svg_path)

              # Accent color for "yellow" is #f0a000.
              # "■" fallback is rect: <rect x="2" y="2" width="32" height="32" rx="2" ry="2" fill="#f0a000"/>
              assert_includes h3_svg, "<rect"
              assert_includes h3_svg, 'fill="#f0a000"'

              # "★" fallback is star: <path d="M18 2 L22 13 L34 13 L24 20 L28 32 L18 24 L8 32 L12 20 L2 13 L14 13 Z" fill="#f0a000"/>
              assert_includes h4_svg, "<path d=\"M18 2 L22 13"
              assert_includes h4_svg, 'fill="#f0a000"'
              mock_resize.verify
            end
          end
        end

        def test_should_keep_original_colors_for_natively_colored_emojis
          config = Common.wrap_config({
            theme: {
              color: "blue",
              markers: {
                h3: "🌸",
                h4: "♠"
              }
            },
            output: { pdf: { techbook: true } }
          })
          processor = Processor.new(config)

          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              # Create dummy HTML file to avoid early return
              File.write('sample.html', "<html><head></head><body><p>Test</p></body></html>")
              
              # Create dummy stylesheets/twemoji directory
              FileUtils.mkdir_p("stylesheets/twemoji")
              
              # 🌸 codepoint is 1f338
              File.write("stylesheets/twemoji/1f338.svg", %(<svg viewBox="0 0 36 36"><path fill="#FFC0CB" d="M18 2 L22 13"/></svg>))
              # ♠ codepoint is 2660
              File.write("stylesheets/twemoji/2660.svg", %(<svg viewBox="0 0 36 36"><path fill="#000000" d="M18 2 C18 2"/></svg>))

              # Mock ResizeCommands.convert_svg_to_webp to do nothing
              mock_resize = Minitest::Mock.new
              mock_resize.expect :call, nil, [Array]
              ResizeCommands.stub :convert_svg_to_webp, mock_resize do
                processor.post_process_html_files!(['sample.html'], inject_css: false)
              end

              h3_svg_path = "stylesheets/twemoji/vs-techbook/marker-h3.svg"
              h4_svg_path = "stylesheets/twemoji/vs-techbook/marker-h4.svg"
              assert File.exist?(h3_svg_path)
              assert File.exist?(h4_svg_path)

              h3_svg = File.read(h3_svg_path)
              h4_svg = File.read(h4_svg_path)

              # 🌸 (h3) should NOT be recolored to blue (#0ea5e9); it must retain #FFC0CB
              assert_includes h3_svg, 'fill="#FFC0CB"'
              refute_includes h3_svg, 'fill="#0ea5e9"'

              # ♠ (h4) SHOULD be recolored to blue (#0ea5e9)
              assert_includes h4_svg, 'fill="#0ea5e9"'
              refute_includes h4_svg, 'fill="#000000"'

              mock_resize.verify
            end
          end
        end
      end
    end
  end
end
