# frozen_string_literal: true

# ================================================================
# Test: theme_image_resolver_ratio_test.rb
# ================================================================
# テスト対象:
#   ThemeImageResolver の frontispiece アスペクト比ロジック
#
# 検証内容:
#   - binding_safe_portrait_ratio がページ設定（幅・高さ・綴じ側マージン）
#     から動的に算出され、MIN_BINDING_RATIO/MAX_BINDING_RATIO でクランプされること
#   - ratio_accepted_for_frontispiece? が許容誤差5%以内の比のみ true を返すこと
#     （42-frontispiece.md にあった「4:3 も使える」という誤記の回帰テスト）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    class ThemeImageResolverRatioTest < Minitest::Test
      TIR = PreProcessCommands::ThemeImageResolver

      def teardown
        restore_config
      end

      # A5相当のページ設定から、綴じ側マージン差分を差し引いた実効幅で比が算出されることを確認
      def test_binding_safe_portrait_ratio_reflects_page_settings
        stub_page_config(width: '148mm', height: '210mm', margin_inner: '20mm', margin_outer: '15mm')

        # effective_width = 148 - (20 - 15) = 143mm → ratio = 210 / 143
        assert_in_delta(210.0 / 143, TIR.binding_safe_portrait_ratio, 0.001)
      end

      # 綴じ側マージンが極端に大きい場合でも実効幅は下限（幅の40%）を割らず、
      # 結果として算出比が MAX_BINDING_RATIO(2.2) でクランプされることを確認
      def test_binding_safe_portrait_ratio_clamps_to_max
        stub_page_config(width: '100mm', height: '200mm', margin_inner: '200mm', margin_outer: '0mm')

        assert_equal 2.2, TIR.binding_safe_portrait_ratio
      end

      # 横長ページなど算出比が小さくなりすぎる場合、MIN_BINDING_RATIO(1.35)でクランプされることを確認
      def test_binding_safe_portrait_ratio_clamps_to_min
        stub_page_config(width: '300mm', height: '200mm', margin_inner: '0mm', margin_outer: '0mm')

        assert_equal 1.35, TIR.binding_safe_portrait_ratio
      end

      # A4相当のページでは √2:1（約1.414）が許容誤差5%以内として受理されることを確認
      def test_ratio_accepted_for_frontispiece_accepts_root_two
        stub_page_config(width: '210mm', height: '297mm', margin_inner: '0mm', margin_outer: '0mm')

        assert TIR.ratio_accepted_for_frontispiece?(1.414)
      end

      # 4:3（1.333）は許容誤差5%を超えるため拒否されることを確認
      def test_ratio_accepted_for_frontispiece_rejects_four_by_three
        stub_page_config(width: '210mm', height: '297mm', margin_inner: '0mm', margin_outer: '0mm')

        refute TIR.ratio_accepted_for_frontispiece?(4.0 / 3)
      end

      private

      # binding_safe_portrait_ratio が参照する Common::CONFIG.page を一時的に差し替える。
      # 本物と同じ Data ラッパーで包む（Hash 直渡しは仕様で廃止・spec §2.4）
      def stub_page_config(width:, height:, margin_inner:, margin_outer:)
        @original_config = Common::CONFIG
        @config_stubbed = true
        Common.send(:remove_const, :CONFIG)
        Common.const_set(:CONFIG, Common.wrap_config(
                                    page: {
                                      width: width,
                                      height: height,
                                      margin_inner: margin_inner,
                                      margin_outer: margin_outer
                                    }
                                  ))
      end

      # 元の CONFIG が nil/false でも確実に復元する（他テストへの汚染防止）
      def restore_config
        return unless @config_stubbed

        Common.send(:remove_const, :CONFIG)
        Common.const_set(:CONFIG, @original_config)
        @config_stubbed = false
      end
    end
  end
end
