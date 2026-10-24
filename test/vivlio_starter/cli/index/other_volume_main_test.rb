# frozen_string_literal: true

# ================================================================
# Test: other_volume_main_test.rb
# ================================================================
# テスト対象（index-other-volume-main-spec.md R1・R3）:
#   OtherVolumeMain.guides — 主要参照が別の巻にある語の案内「上巻 第7章」
#
# 2 巻だけで確かめると「組む巻でなければもう一方」という思い込みが隠れるので、上中下の 3 巻で確かめる。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module IndexCommands
      class OtherVolumeMainTest < Minitest::Test
        CATALOG = <<~YAML
          VOLUMES:
            - name: 上巻
              id: upper
              PREFACE:
                - 00-preface
              CHAPTERS:
                - 01-intro
                - 02-basics
              APPENDICES:
                - 90-how-to-ask
            - name: 中巻
              id: middle
              PREFACE:
                - 10-vol2-intro
              CHAPTERS:
                - 11-apply
              APPENDICES:
                - 91-tools
            - name: 下巻
              id: lower
              CHAPTERS:
                - 21-final
        YAML

        BASENAMES = %w[00-preface 01-intro 02-basics 90-how-to-ask 10-vol2-intro 11-apply 91-tools 21-final].freeze

        def teardown
          Build::Volumes.select!(nil)
        end

        def guides_in(volume_id, mains)
          terms = mains.each_with_index.map { |main, i| { 'term' => "語#{i}", 'main' => main } }
          Build::Volumes.select!(Build::Volumes.find(volume_id))
          OtherVolumeMain.guides(terms).transform_keys { it.delete_prefix('語').to_i }
        end

        # 章扉と同じ数え方（中巻は上巻の 2 章の続き）・付録の記号・節の指定は章で案内する
        def test_should_name_volume_and_chapter_like_the_chapter_page
          with_project do
            guides = guides_in('lower', [['02-basics'], ['11-apply'], ['91-tools'], ['02-basics#節の名前']])

            assert_equal({ 0 => '上巻 第2章', 1 => '中巻 第3章', 2 => '中巻 付録 B', 3 => '上巻 第2章' }, guides)
          end
        end

        # 二つ以上の巻にあれば目次の順に並べる。組む巻の章は案内に入れない
        def test_should_join_volumes_in_catalog_order_and_skip_local_chapters
          with_project do
            guides = guides_in('lower', [%w[11-apply 01-intro], %w[21-final 01-intro], ['21-final']])

            assert_equal({ 0 => '上巻 第1章・中巻 第3章', 1 => '上巻 第1章' }, guides)
          end
        end

        # 章番号を振らない章は章題で案内する
        def test_should_use_title_for_unnumbered_chapter
          with_project do
            File.write('contents/10-vol2-intro.md', "# 中巻の **はじめに**\n\n本文\n")

            assert_equal({ 0 => '中巻「中巻の はじめに」' }, guides_in('upper', [['10-vol2-intro']]))
          end
        end

        # 合本（巻を選ばない）では案内しない（R3）
        def test_should_be_empty_without_a_selected_volume
          with_project do
            assert_empty OtherVolumeMain.guides([{ 'term' => '語', 'main' => ['11-apply'] }])
          end
        end

        private

        def with_project
          Dir.mktmpdir('vs-other-volume-main') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(%w[config contents])
              File.write('config/catalog.yml', CATALOG)
              BASENAMES.each { File.write("contents/#{it}.md", "# #{it}\n") }
              Common.stub(:log_info, nil) { yield }
            end
          end
        end
      end
    end
  end
end
