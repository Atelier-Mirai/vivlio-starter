# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/token_resolver'

module Vivlio
  module Starter
    module CLI
      module TokenResolver
        class ResolverTest < Minitest::Test
          # --- Normalization Tests ---

          def test_zero_pads_single_digit_number
            resolver = build_resolver_with_catalog(['01-foo'])

            result = resolver.resolve(['1'])

            assert_equal ['01'], result.map(&:number)
          end

          def test_expands_range_ascending
            resolver = build_resolver_with_catalog(%w[01-a 02-b 03-c])

            result = resolver.resolve(['1-3'])

            assert_equal %w[01 02 03], result.map(&:number)
          end

          def test_expands_range_descending
            resolver = build_resolver_with_catalog(%w[03-a 04-b 05-c])

            result = resolver.resolve(['5-3'])

            assert_equal %w[03 04 05], result.map(&:number)
          end

          def test_handles_mixed_input_with_comma
            resolver = build_resolver_with_catalog(%w[01-a 02-b 03-c 05-d])

            result = resolver.resolve(['1-3,5'])

            assert_equal %w[01 02 03 05], result.map(&:number)
          end

          def test_removes_duplicates
            resolver = build_resolver_with_catalog(%w[01-a 02-b])

            result = resolver.resolve(['1', '2', '1'])

            assert_equal %w[01 02], result.map(&:number)
          end

          def test_normalizes_slug_with_zero_padding
            resolver = build_resolver_with_catalog(['01-life'])

            result = resolver.resolve(['1-life'])

            assert_equal ['01-life'], result.map(&:basename)
          end

          def test_strips_contents_prefix_and_extension
            resolver = build_resolver_with_catalog(['01-foo'])

            result = resolver.resolve(['contents/01-foo.md'])

            assert_equal ['01-foo'], result.map(&:basename)
          end

          # --- Catalog Loading Tests ---

          def test_returns_all_catalog_entries_when_no_tokens
            resolver = build_resolver_with_catalog(%w[01-a 02-b 03-c])

            result = resolver.resolve([])

            assert_equal %w[01 02 03], result.map(&:number)
          end

          def test_loads_nested_yaml_structure
            Dir.mktmpdir do |dir|
              catalog_path = File.join(dir, 'catalog.yml')
              File.write(catalog_path, <<~YAML)
                CHAPTERS:
                  - 歴史篇:
                      - 01-life
                      - 02-history
                  - 実践篇:
                      - 11-env
              YAML

              resolver = Resolver.new(catalog_path:, contents_dir: dir)
              result = resolver.resolve([])

              assert_equal %w[01 02 11], result.map(&:number)
              # label はネストしたキー名を保持
              assert_equal '歴史篇', result.find { it.number == '01' }.label
              assert_equal '実践篇', result.find { it.number == '11' }.label
            end
          end

          def test_handles_flat_yaml_structure
            Dir.mktmpdir do |dir|
              catalog_path = File.join(dir, 'catalog.yml')
              File.write(catalog_path, <<~YAML)
                CHAPTERS:
                  - 01-intro
                  - 02-setup
              YAML

              resolver = Resolver.new(catalog_path:, contents_dir: dir)
              result = resolver.resolve([])

              assert_equal %w[01 02], result.map(&:number)
              # フラット構造の場合、label はセクション名
              assert_equal 'CHAPTERS', result.first.label
            end
          end

          def test_returns_empty_when_catalog_not_exists
            resolver = Resolver.new(catalog_path: '/nonexistent/catalog.yml', contents_dir: 'contents')

            result = resolver.resolve([])

            assert_empty result
          end

          # --- Matching Tests ---

          def test_returns_catalog_entry_when_found
            resolver = build_resolver_with_catalog(['01-life'])

            result = resolver.resolve(['1'])
            entry = result.first

            assert_equal '01', entry.number
            assert_equal 'life', entry.slug
            assert entry.in_catalog?
            assert entry.valid?
          end

          def test_returns_new_entry_when_not_in_catalog
            resolver = build_resolver_with_catalog(['01-life'])

            result = resolver.resolve(['2-new'])
            entry = result.first

            assert_equal '02', entry.number
            assert_equal 'new', entry.slug
            refute entry.in_catalog?
            assert entry.valid?
            assert_equal 'NEW', entry.label
          end

          def test_returns_invalid_entry_for_non_numeric_token
            resolver = build_resolver_with_catalog([])

            result = resolver.resolve(['foobar'])
            entry = result.first

            assert_equal '??', entry.number
            assert_equal 'foobar', entry.slug
            refute entry.valid?
            refute entry.in_catalog?
          end

          def test_skips_missing_catalog_entries_in_range
            # catalog に 02 が存在しない場合
            resolver = build_resolver_with_catalog(%w[01-install 03-option])

            result = resolver.resolve(['1-3'])

            # 01, 02, 03 が展開されるが、02 は in_catalog: false
            assert_equal 3, result.size
            assert result.find { it.number == '01' }.in_catalog?
            refute result.find { it.number == '02' }.in_catalog?
            assert result.find { it.number == '03' }.in_catalog?
          end

          # --- Filesystem Slug Completion Tests ---

          def test_completes_slug_from_filesystem_when_not_in_catalog
            Dir.mktmpdir do |dir|
              catalog_path = File.join(dir, 'catalog.yml')
              contents_dir = File.join(dir, 'contents')
              FileUtils.mkdir_p(contents_dir)

              # カタログには 01-life のみ登録、02-history はファイルのみ存在
              File.write(catalog_path, { 'CHAPTERS' => ['01-life'] }.to_yaml)
              File.write(File.join(contents_dir, '01-life.md'), '# life')
              File.write(File.join(contents_dir, '02-history.md'), '# history')

              resolver = Resolver.new(catalog_path:, contents_dir:)
              result = resolver.resolve(['2'])
              entry = result.first

              assert_equal '02', entry.number
              assert_equal 'history', entry.slug
              assert_equal '02-history', entry.basename
              assert entry.exists?
              refute entry.in_catalog?
              assert entry.valid?
            end
          end

          def test_completes_slug_from_filesystem_for_range
            Dir.mktmpdir do |dir|
              catalog_path = File.join(dir, 'catalog.yml')
              contents_dir = File.join(dir, 'contents')
              FileUtils.mkdir_p(contents_dir)

              # カタログには 01-life のみ、02-history と 03-person はファイルのみ
              File.write(catalog_path, { 'CHAPTERS' => ['01-life'] }.to_yaml)
              File.write(File.join(contents_dir, '01-life.md'), '# life')
              File.write(File.join(contents_dir, '02-history.md'), '# history')
              File.write(File.join(contents_dir, '03-person.md'), '# person')

              resolver = Resolver.new(catalog_path:, contents_dir:)
              result = resolver.resolve(['2-3'])

              assert_equal %w[02 03], result.map(&:number)
              assert_equal 'history', result.find { it.number == '02' }.slug
              assert_equal 'person', result.find { it.number == '03' }.slug
            end
          end

          def test_falls_back_to_number_only_when_no_file_on_disk
            Dir.mktmpdir do |dir|
              catalog_path = File.join(dir, 'catalog.yml')
              contents_dir = File.join(dir, 'contents')
              FileUtils.mkdir_p(contents_dir)

              # カタログにもファイルシステムにも 02 は存在しない
              File.write(catalog_path, { 'CHAPTERS' => ['01-life'] }.to_yaml)
              File.write(File.join(contents_dir, '01-life.md'), '# life')

              resolver = Resolver.new(catalog_path:, contents_dir:)
              result = resolver.resolve(['2'])
              entry = result.first

              assert_equal '02', entry.number
              assert_nil entry.slug
              refute entry.exists?
            end
          end

          # --- Kind Detection Tests ---

          def test_assigns_preface_kind_for_00
            resolver = build_resolver_with_catalog(['00-preface'])

            result = resolver.resolve(['0'])

            assert_equal :preface, result.first.kind
          end

          def test_assigns_chapter_kind_for_01_to_89
            resolver = build_resolver_with_catalog(['50-middle'])

            result = resolver.resolve(['50'])

            assert_equal :chapter, result.first.kind
          end

          def test_assigns_appendix_kind_for_90_to_98
            resolver = build_resolver_with_catalog(['91-books'])

            result = resolver.resolve(['91'])

            assert_equal :appendix, result.first.kind
          end

          def test_assigns_postface_kind_for_99
            resolver = build_resolver_with_catalog(['99-postface'])

            result = resolver.resolve(['99'])

            assert_equal :postface, result.first.kind
          end

          # --- Entry Attribute Tests ---

          def test_entry_basename_with_slug
            entry = Entry.new(number: '01', slug: 'life', kind: :chapter, label: 'TEST', path: '', exists: false, in_catalog: true, valid: true)

            assert_equal '01-life', entry.basename
          end

          def test_entry_basename_without_slug
            entry = Entry.new(number: '01', slug: nil, kind: :chapter, label: 'TEST', path: '', exists: false, in_catalog: true, valid: true)

            assert_equal '01', entry.basename
          end

          def test_entry_exists_reflects_file_presence
            Dir.mktmpdir do |dir|
              catalog_path = File.join(dir, 'catalog.yml')
              contents_dir = File.join(dir, 'contents')
              FileUtils.mkdir_p(contents_dir)

              # 01-exists.md は存在、02-missing.md は不存在
              File.write(File.join(contents_dir, '01-exists.md'), '# Exists')

              File.write(catalog_path, <<~YAML)
                CHAPTERS:
                  - 01-exists
                  - 02-missing
              YAML

              resolver = Resolver.new(catalog_path:, contents_dir:)
              result = resolver.resolve([])

              assert result.find { it.number == '01' }.exists?
              refute result.find { it.number == '02' }.exists?
            end
          end

          # --- System Page Path Tests ---

          def test_titlepage_resolves_to_cache_dir
            resolver = build_resolver_with_catalog([])
            entry = resolver.resolve(['_titlepage']).first

            assert entry.valid?
            assert_equal :titlepage, entry.kind
            assert_equal '.cache/vs/_titlepage.md', entry.path
          end

          def test_legalpage_resolves_to_cache_dir
            resolver = build_resolver_with_catalog([])
            entry = resolver.resolve(['_legalpage']).first

            assert entry.valid?
            assert_equal :legalpage, entry.kind
            assert_equal '.cache/vs/_legalpage.md', entry.path
          end

          def test_colophon_resolves_to_cache_dir
            resolver = build_resolver_with_catalog([])
            entry = resolver.resolve(['_colophon']).first

            assert entry.valid?
            assert_equal :colophon, entry.kind
            assert_equal '.cache/vs/_colophon.md', entry.path
          end

          def test_toc_still_resolves_to_contents_dir
            resolver = build_resolver_with_catalog([])
            entry = resolver.resolve(['_toc']).first

            assert entry.valid?
            assert_equal :toc, entry.kind
            assert_match %r{contents/_toc\.md\z}, entry.path
          end

          private

          # テスト用のカタログを作成してResolverを返す
          def build_resolver_with_catalog(basenames)
            dir = Dir.mktmpdir
            catalog_path = File.join(dir, 'catalog.yml')
            contents_dir = File.join(dir, 'contents')
            FileUtils.mkdir_p(contents_dir)

            # catalog.yml を生成
            yaml_content = { 'CHAPTERS' => basenames }.to_yaml
            File.write(catalog_path, yaml_content)

            # 各章のファイルを作成（exists を true にするため）
            basenames.each do |basename|
              File.write(File.join(contents_dir, "#{basename}.md"), "# #{basename}")
            end

            Resolver.new(catalog_path:, contents_dir:)
          end
        end
      end
    end
  end
end
