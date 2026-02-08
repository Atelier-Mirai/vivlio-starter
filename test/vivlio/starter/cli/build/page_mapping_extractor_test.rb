# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'socket'

# PageMappingExtractor のテストに必要な最小限のスタブ
module Vivlio
  module Starter
    module CLI
      module Common
        module_function

        def log_info(msg) = nil
        def log_action(msg) = nil
        def log_success(msg) = nil
        def log_warn(msg) = nil
        def log_error(msg) = nil
      end
    end
  end
end

require 'vivlio/starter/cli/build/page_mapping_extractor'

class PageMappingExtractorTest < Minitest::Test
  Extractor = Vivlio::Starter::CLI::Build::PageMappingExtractor

  # --- 既存 preview サーバー検知（方策 D）---

  def test_should_reuse_existing_server_when_port_is_already_open
    # Arrange: テスト用 TCP サーバーを起動してポートを占有
    server = TCPServer.new('localhost', 0)
    port = server.addr[1]

    extractor = Extractor.new(port:)

    # Act: port_open? 相当の内部状態を検証するため start_preview_server! を呼ぶ
    # validate_dependencies! をスキップするため send で直接呼び出し
    extractor.send(:start_preview_server!)

    # Assert: 外部管理フラグが立ち、PID は nil（プロセス未起動）
    assert extractor.send(:externally_managed),
           '既存サーバー検出時に externally_managed が true になること'
    assert_nil extractor.send(:preview_pid),
               '既存サーバー検出時に preview_pid が nil であること'

    # Preview URL がフォールバック形式で構築されること
    expected_url = "http://localhost:#{port}/__vivliostyle-viewer/index.html" \
                   "#src=http://localhost:#{port}/vivliostyle/publication.json" \
                   '&bookMode=true&renderAllPages=true'
    assert_equal expected_url, extractor.instance_variable_get(:@preview_url)
  ensure
    server&.close
  end

  def test_should_not_kill_externally_managed_server_on_stop
    # Arrange: 外部管理状態を模擬
    server = TCPServer.new('localhost', 0)
    port = server.addr[1]

    extractor = Extractor.new(port:)
    extractor.send(:start_preview_server!)

    # Act: stop_preview_server! が例外を出さずに完了すること
    # 外部管理のため Process.kill は呼ばれない
    extractor.send(:stop_preview_server!)

    # Assert: サーバーがまだ生きていることを確認（kill されていない）
    socket = TCPSocket.new('localhost', port)
    assert socket, '外部管理のサーバーが stop 後も生存していること'
    socket.close
  ensure
    server&.close
  end

  def test_should_attempt_launch_when_port_is_not_open
    # Arrange: 未使用ポートを取得（bind して即閉じ）
    temp_server = TCPServer.new('localhost', 0)
    free_port = temp_server.addr[1]
    temp_server.close

    extractor = Extractor.new(port: free_port)

    # Act: ポートが閉じている → launch_preview_process! が呼ばれるはず
    # 実際に vivliostyle を起動すると重いので、launch_preview_process! の
    # 呼び出しをスタブして検証する
    launch_called = false
    extractor.stub(:launch_preview_process!, -> { launch_called = true }) do
      extractor.send(:start_preview_server!)
    end

    # Assert
    assert launch_called, 'ポートが閉じている場合に launch_preview_process! が呼ばれること'
    refute extractor.send(:externally_managed),
           'ポートが閉じている場合に externally_managed が false であること'
  end

  # --- build_fallback_url ---

  def test_should_build_correct_fallback_url
    extractor = Extractor.new(port: 13100)
    url = extractor.send(:build_fallback_url)

    assert_includes url, 'localhost:13100'
    assert_includes url, '__vivliostyle-viewer/index.html'
    assert_includes url, 'publication.json'
    assert_includes url, 'renderAllPages=true'
  end

  def test_should_include_custom_port_in_fallback_url
    extractor = Extractor.new(port: 9999)
    url = extractor.send(:build_fallback_url)

    assert_includes url, 'localhost:9999'
  end
end
