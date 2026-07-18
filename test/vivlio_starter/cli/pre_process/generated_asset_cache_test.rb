# frozen_string_literal: true

# ================================================================
# Test: generated_asset_cache_test.rb
# ================================================================
# テスト対象:
#   PreProcessCommands::GeneratedAssetCache（生成資産の永続キャッシュ）
#
# 検証内容:
#   - fetch: ミス時にブロックで生成 → キャッシュ＋ワークスペース両方に揃う
#   - fetch: ヒット時はブロックを呼ばずワークスペースへ写すだけ
#   - fetch: ワークスペースに揃っていれば何もしない（同一ビルド内の再訪）
#   - fetch: 生成失敗（ブロック false）・書き忘れ（true でもファイル無し）は縮退 false
#   - materialize: キャッシュに揃っていれば写す／不足なら false
#   - クリーンビルド相当（ワークスペース削除）を跨いで再生成しない
# ================================================================

require_relative '../../../test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/pre_process/generated_asset_cache'

class GeneratedAssetCacheTest < Minitest::Test
  C = VivlioStarter::CLI::PreProcessCommands::GeneratedAssetCache

  def in_project(&)
    Dir.mktmpdir { |dir| Dir.chdir(dir, &) }
  end

  def write_assets(dir, files)
    FileUtils.mkdir_p(dir)
    files.each { File.write(File.join(dir, it), "content of #{it}") }
  end

  def test_fetch_generates_on_miss_and_populates_both_sides
    in_project do
      calls = 0
      ok = C.fetch('mermaid', %w[k.svg k.png], out_dir: 'ws') do |cache_dir|
        calls += 1
        write_assets(cache_dir, %w[k.svg k.png])
        true
      end

      assert ok
      assert_equal 1, calls
      assert_path_exists File.join('.cache', 'vs', 'mermaid', 'k.svg')
      assert_path_exists 'ws/k.svg'
      assert_path_exists 'ws/k.png'
    end
  end

  def test_fetch_skips_generation_on_cache_hit
    in_project do
      write_assets(C.dir('mermaid'), %w[k.svg k.png])

      called = false
      ok = C.fetch('mermaid', %w[k.svg k.png], out_dir: 'ws') { called = true }

      assert ok
      refute called, 'キャッシュヒット時は生成ブロックを呼ばない'
      assert_equal 'content of k.svg', File.read('ws/k.svg')
    end
  end

  def test_fetch_is_noop_when_workspace_already_has_the_files
    in_project do
      write_assets('ws', %w[k.svg k.png])

      called = false
      ok = C.fetch('mermaid', %w[k.svg k.png], out_dir: 'ws') { called = true }

      assert ok
      refute called
      refute_path_exists File.join('.cache', 'vs', 'mermaid', 'k.svg'), 'キャッシュ側への複製もしない'
    end
  end

  def test_fetch_degrades_when_the_generator_fails
    in_project do
      ok = C.fetch('mermaid', %w[k.svg], out_dir: 'ws') { false }

      refute ok
      refute_path_exists 'ws/k.svg'
    end
  end

  # 生成側が true を返してもファイルが揃っていなければ縮退（書き忘れの防波堤）。
  def test_fetch_degrades_when_the_generator_forgets_to_write
    in_project do
      ok = C.fetch('mermaid', %w[k.svg k.png], out_dir: 'ws') do |cache_dir|
        write_assets(cache_dir, %w[k.svg]) # png を書き忘れ
        true
      end

      refute ok
      refute_path_exists 'ws/k.svg'
    end
  end

  def test_materialize_copies_from_cache_or_returns_false
    in_project do
      refute C.materialize('math', %w[f.svg], out_dir: 'ws'), 'キャッシュ不足は false'

      write_assets(C.dir('math'), %w[f.svg])

      assert C.materialize('math', %w[f.svg], out_dir: 'ws')
      assert_path_exists 'ws/f.svg'
    end
  end

  # final clean 相当（ワークスペース削除）を跨いでも生成し直さない。
  def test_survives_a_workspace_clean_without_regenerating
    in_project do
      C.fetch('mermaid', %w[k.svg], out_dir: 'ws') do |cache_dir|
        write_assets(cache_dir, %w[k.svg])
        true
      end
      FileUtils.rm_rf('ws')

      calls = 0
      ok = C.fetch('mermaid', %w[k.svg], out_dir: 'ws') { calls += 1 }

      assert ok
      assert_equal 0, calls
      assert_path_exists 'ws/k.svg'
    end
  end
end
