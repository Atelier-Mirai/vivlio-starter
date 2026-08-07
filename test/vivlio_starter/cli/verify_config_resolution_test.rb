# frozen_string_literal: true

# ================================================================
# Test: verify_config_resolution_test.rb
# ================================================================
# テスト対象:
#   LinkImageValidator.resolve_config — book.yml の verify.* と
#   CLI オプション（--no-verify / --verify-links）の優先順位
#
# 背景:
#   BuildCommand / PreflightCommand の setup_verify_options! が
#   verify_images / verify_bare_urls / verify_external_links を**常に**
#   スレッドローカルへ立てていたため、resolve_config の
#   `cli_opts.fetch(:verify_images, 設定側の既定)` が一度も既定値に落ちず、
#   book.yml の verify.images / bare_urls / external_links が
#   丸ごと無視されていた（2026-08-07 修正）。
#
#   キー名は resolve_config に出現するため book_yml_consumption_test は
#   素通りする。「値が実際に効くか」はここで固定する。
#
# 検証方法:
#   CONFIG を差し替えて resolve_config の戻り値を直接見る。
#   CLI 側は setup_verify_options! が載せるのと同じ形の Hash を渡す。
# ================================================================

require 'test_helper'
require_relative '../../../lib/vivlio_starter/cli/pre_process/link_image_validator'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class VerifyConfigResolutionTest < Minitest::Test
        # setup_verify_options! が実際に載せる 3 通り
        NO_OPTIONS    = {}.freeze                              # 素の vs build / vs preflight
        VERIFY_LINKS  = { verify_external_links: true }.freeze # --verify-links
        NO_VERIFY     = { no_verify: true }.freeze             # --no-verify

        def teardown
          Thread.current[:vs_verify_options] = nil
          CLI::Common.reload_configuration!(silent: true)
        end

        # book.yml の verify.* が CLI 無指定時に効くこと（回帰の本体）
        def test_should_apply_book_yml_values_when_no_cli_option_given
          with_verify_config(images: false, bare_urls: false, external_links: true)
          Thread.current[:vs_verify_options] = NO_OPTIONS

          config = LinkImageValidator.send(:resolve_config)

          assert_equal false, config[:verify_images], 'verify.images: false が効くはずです'
          assert_equal false, config[:verify_bare_urls], 'verify.bare_urls: false が効くはずです'
          assert_equal true, config[:verify_external_links], 'verify.external_links: true が効くはずです'
        end

        # 未設定時の既定（images/bare_urls は有効、external_links は無効）
        def test_should_fall_back_to_defaults_when_book_yml_omits_verify
          with_verify_config({})
          Thread.current[:vs_verify_options] = NO_OPTIONS

          config = LinkImageValidator.send(:resolve_config)

          assert_equal true, config[:verify_images]
          assert_equal true, config[:verify_bare_urls]
          assert_equal false, config[:verify_external_links]
          assert_equal 10, config[:timeout]
          assert_equal 5, config[:max_concurrency]
        end

        # timeout / max_concurrency は book.yml から読む
        def test_should_read_timeout_and_concurrency_from_book_yml
          with_verify_config(timeout: 99, max_concurrency: 42)
          Thread.current[:vs_verify_options] = NO_OPTIONS

          config = LinkImageValidator.send(:resolve_config)

          assert_equal 99, config[:timeout]
          assert_equal 42, config[:max_concurrency]
        end

        # --verify-links は book.yml の external_links: false に勝つ
        def test_should_let_verify_links_option_override_book_yml
          with_verify_config(external_links: false)
          Thread.current[:vs_verify_options] = VERIFY_LINKS

          assert_equal true, LinkImageValidator.send(:resolve_config)[:verify_external_links]
        end

        # --no-verify は book.yml の指定によらず全無効
        def test_should_disable_everything_with_no_verify_option
          with_verify_config(images: true, bare_urls: true, external_links: true)
          Thread.current[:vs_verify_options] = NO_VERIFY

          config = LinkImageValidator.send(:resolve_config)

          assert_equal false, config[:verify_images]
          assert_equal false, config[:verify_bare_urls]
          assert_equal false, config[:verify_external_links]
        end

        private

        # CONFIG の verify セクションだけ差し替える
        def with_verify_config(values)
          raw = { verify: values.transform_keys(&:to_sym) }
          merged = CLI::Common.merge_hardcoded_defaults(raw)
          CLI::Common.install_configuration!(CLI::Common.wrap_config(merged).freeze)
        end
      end
    end
  end
end
