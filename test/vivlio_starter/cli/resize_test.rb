# frozen_string_literal: true

# ================================================================
# Test: cli/resize_test.rb
# ================================================================
# テスト対象:
#   ResizeCommands の WebP プリセットと並列変換（lib/vivlio_starter/cli/resize.rb）
#
# 検証内容:
#   RS-01: WEBP_PRESETS の method が 4（6 に戻すと初回ビルドが桁で遅くなる）
#   RS-02: プリセットは quality / max_px で差を付け、method では付けない
#   RS-03: each_in_parallel が全要素をちょうど 1 回ずつ処理する
#   RS-04: 並列度 1（VIVLIO_IMAGE_CONCURRENCY=1）でも全要素を処理する
#   RS-05: image_concurrency は環境変数で上書きでき、上限 8 に収まる
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/resize'

module VivlioStarter
  module CLI
    class ResizeTest < Minitest::Test
      def teardown
        ENV.delete('VIVLIO_IMAGE_CONCURRENCY')
      end

      # RS-01: method=6 は 5 → 6 で時間が 22 倍に跳ねる崖の上にあり、
      # 見返りはサイズ 1.5% 減しかない。透過を持つ絵で特に遅く、戻すと初回ビルドが桁で遅くなる
      def test_should_not_use_the_slowest_webp_method
        methods = ResizeCommands::WEBP_PRESETS.values.map { it[:method] }

        assert_equal [4, 4, 4], methods,
                     'webp:method は libwebp 既定の 4。6 に戻してはならない（resize.rb のコメント参照）'
      end

      # RS-02: method は画質と無関係なので、プリセットの差は quality と max_px で付ける
      def test_should_differentiate_presets_by_quality_and_size_only
        presets = ResizeCommands::WEBP_PRESETS

        assert_equal [90, 85, 75], presets.values.map { it[:quality] }
        assert_equal [2048, 1600, 1200], presets.values.map { it[:max_px] }
        assert_equal 1, presets.values.map { it[:method] }.uniq.size,
                     'method は画質ではないので、プリセットごとに変えない'
      end

      # RS-03: 並列で走らせても、取りこぼしも二重処理も起きない
      def test_should_process_every_item_exactly_once_in_parallel
        items = (1..200).to_a
        seen = []
        lock = Mutex.new

        ResizeCommands.each_in_parallel(items) { |i| lock.synchronize { seen << i } }

        assert_equal items, seen.sort
        assert_equal items.size, seen.size, '二重に処理してはならない'
      end

      # RS-04: 逐次に落としても振る舞いは同じ
      def test_should_process_every_item_when_running_sequentially
        ENV['VIVLIO_IMAGE_CONCURRENCY'] = '1'
        seen = []

        ResizeCommands.each_in_parallel(%w[a b c]) { seen << it }

        assert_equal %w[a b c], seen
      end

      # RS-05: 並列度は環境変数で上書きでき、既定は CPU コア数（上限 8）
      def test_should_resolve_concurrency_from_environment_within_bounds
        ENV['VIVLIO_IMAGE_CONCURRENCY'] = '3'
        assert_equal 3, ResizeCommands.image_concurrency

        ENV.delete('VIVLIO_IMAGE_CONCURRENCY')
        assert_includes 1..8, ResizeCommands.image_concurrency,
                        'magick は 1 プロセスあたり画像 1 枚をメモリに載せるので上限を設ける'
      end
    end
  end
end
