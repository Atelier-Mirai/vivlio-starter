# frozen_string_literal: true

# ================================================================
# Test: mermaid_renderer_test.rb
# ================================================================
# 検証内容（mermaid-diagram-spec.md §9・§6）:
#   - mmdc の実行は重く環境依存のため、ここでは「不在時に安全側へ倒れる」ことだけを見る。
#     available? が false／version が空文字／render が nil を返し、例外を投げないこと。
#   - 実際の描画（mmdc 起動）は上位（MermaidTransformer）が DI で FakeRenderer に
#     差し替えて検証する。mmdc が入っている環境では available? が例外なく応答することも見る。
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/mermaid_renderer'

class MermaidRendererTest < Minitest::Test
  R = VivlioStarter::CLI::PreProcessCommands::MermaidRenderer

  # mmdc の有無に関わらず、公開 API は真偽値・文字列・nil を例外なく返す。
  def test_public_api_never_raises
    renderer = R.new

    assert_includes [true, false], renderer.available?
    assert_kind_of String, renderer.version
  end

  # mmdc 不在時（available? が false）は render が必ず nil を返す（縮退の土台）。
  def test_render_returns_nil_when_unavailable
    renderer = R.new
    skip 'mmdc が導入済みの環境では不在時経路を検証できない' if renderer.available?

    assert_nil renderer.render("graph LR\n  A --> B", format: :svg)
    assert_nil renderer.render("graph LR\n  A --> B", format: :png)
  end

  # 空ソースは（mmdc の有無に関わらず）描画対象にせず nil を返す。
  def test_render_returns_nil_for_blank_source
    assert_nil R.new.render("   \n", format: :svg)
  end
end
