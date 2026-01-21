# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/token_shorthand/resolver'

module Vivlio
  module Starter
    module CLI
      module TokenShorthand
        class ResolverTest < Minitest::Test
          def test_resolves_numbers_and_ranges_with_zero_padding
            entries = build_catalog_entries(%w[01-foo 02-bar 03-baz])

            result = Resolver.resolve(tokens: ['1', '2-3'], catalog_entries: entries)

            assert_equal %w[01-foo 02-bar 03-baz], result.map(&:basename)
          end

          def test_resolves_numbered_slug_with_zero_padding
            entries = build_catalog_entries(['01-alpha'])

            result = Resolver.resolve(tokens: ['1-alpha'], catalog_entries: entries)

            assert_equal ['01-alpha'], result.map(&:basename)
          end

          def test_resolves_slug_only_when_allowed
            entries = build_catalog_entries(['11-hello'])

            result = Resolver.resolve(tokens: ['hello'], catalog_entries: entries, allow_slug_only: true)

            assert_equal ['11-hello'], result.map(&:basename)
          end

          def test_allows_new_number_without_slug
            result = Resolver.resolve(tokens: ['1'], catalog_entries: [], allow_new: true, allow_missing_slug: true, contents_dir: 'contents')
            entry = result.first

            assert_equal '01', entry.number
            assert_nil entry.slug
            assert_equal '01', entry.basename
            assert_equal File.join('contents', '01.md'), entry.path
          end

          def test_requires_slug_when_allow_new_without_missing_slug
            assert_raises(Errors::MissingChapterSlug) do
              Resolver.resolve(tokens: ['1'], catalog_entries: [], allow_new: true, allow_missing_slug: false)
            end
          end

          def test_rejects_unknown_token_when_allow_new_false
            assert_raises(Errors::UnknownChapterToken) do
              Resolver.resolve(tokens: ['1'], catalog_entries: [])
            end
          end

          def test_rejects_special_token_when_not_allowed
            assert_raises(Errors::UnsupportedSpecialFile) do
              Resolver.resolve(tokens: ['_toc.md'], catalog_entries: [])
            end
          end

          def test_allows_special_token_when_auxiliary_enabled
            entries = Resolver.resolve(tokens: ['_toc.md'], catalog_entries: [], allow_auxiliary: true)
            toc = entries.find { |entry| entry.path == '_toc.md' }

            refute_nil toc
            assert_equal :auxiliary, toc.kind
            assert toc.special?
          end

          def test_loads_metrics_cache_entries_when_enabled
            Dir.mktmpdir do |dir|
              cache_dir = File.join(dir, '.cache', 'metrics')
              FileUtils.mkdir_p(cache_dir)
              File.write(File.join(cache_dir, '11-sample.yml'), "---\n")

              entries = Resolver.resolve(tokens: [], catalog_entries: [], allow_metrics_cache: true, metrics_cache_dir: cache_dir)
              cache_entry = entries.find { |entry| entry.path == File.join(cache_dir, '11-sample.yml') }

              refute_nil cache_entry
              assert_equal :metrics_cache, cache_entry.kind
              assert cache_entry.special?
            end
          end

          private

          def build_catalog_entries(basenames)
            basenames.map { |basename| build_catalog_entry(basename) }
          end

          def build_catalog_entry(basename)
            number, slug = basename.split('-', 2)
            Data::CatalogEntry.new(
              number:,
              slug:,
              kind: :chapter,
              basename:,
              path: File.join('contents', "#{basename}.md"),
              ext: '.md',
              exists: true
            )
          end
        end
      end
    end
  end
end
