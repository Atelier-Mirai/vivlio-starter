# frozen_string_literal: true

# ================================================================
# Class: PageMappingExtractor
# ================================================================
# 責務:
#   vivliostyle preview をヘッドレスで起動し、Playwright 経由で
#   各 glossary-link のページ配置マッピングを取得する。
#
# 処理フロー:
#   1. vivliostyle preview --no-open-viewer をバックグラウンド起動
#   2. サーバー起動完了を待機（ポート応答確認）
#   3. Node.js スクリプト（extract_page_mapping.mjs）を実行
#   4. JSON 結果をパースして返却
#   5. preview プロセスを終了
#
# 依存:
#   - Node.js + Playwright（ブラウザ自動化）
#   - vivliostyle CLI（preview サーバー）
# ================================================================

require 'json'
require 'open3'
require 'socket'
require 'tempfile'
require 'timeout'

module VivlioStarter
  module CLI
    module Build
      # Vivliostyle preview + Playwright でページマッピングを抽出する
      class PageMappingExtractor
        # デフォルト設定
        DEFAULT_PORT = 13_100
        DEFAULT_HOST = 'localhost'
        DEFAULT_TIMEOUT_MS = 300_000 # 416ページ規模のビルドに対応するため5分に延長
        SERVER_STARTUP_TIMEOUT = 30 # 秒
        MAPPING_SCRIPT = File.expand_path('extract_page_mapping.mjs', __dir__)

        # 抽出結果を保持する Data オブジェクト
        PageMapping = Data.define(:mappings, :backlink_mappings, :index_mappings, :total_pages, :extracted_at)

        # 個別マッピングエントリ
        MappingEntry = Data.define(:anchor_id, :href, :page_index, :spine_index)

        # バックリンクマッピングエントリ
        BacklinkEntry = Data.define(:href, :page_index, :spine_index)

        # 索引語マッピングエントリ
        IndexMappingEntry = Data.define(:anchor_id, :page_index, :spine_index)

        def initialize(port: DEFAULT_PORT, timeout_ms: DEFAULT_TIMEOUT_MS)
          @port = port
          @timeout_ms = timeout_ms
          @preview_pid = nil
          @preview_url = nil
          @log_file = nil
          @externally_managed = false
        end

        # ページマッピングを抽出するメインメソッド
        # @return [PageMapping] 抽出結果
        def extract!
          validate_dependencies!

          Common.log_action('[backlink-dedup] vivliostyle preview をヘッドレスで起動します…')
          start_preview_server!

          Common.log_action('[backlink-dedup] Playwright でページマッピングを抽出します…')
          raw_json = run_extraction_script!

          Common.log_success("[backlink-dedup] ページマッピングを取得しました（#{raw_json[:mappings].size} 件）")
          parse_result(raw_json)
        ensure
          stop_preview_server!
        end

        private

        attr_reader :port, :timeout_ms, :preview_pid, :externally_managed

        # 必要な依存ツールの存在を確認
        def validate_dependencies!
          raise "extract_page_mapping.mjs が見つかりません: #{MAPPING_SCRIPT}" unless File.exist?(MAPPING_SCRIPT)

          # Playwright のインストール確認
          _out, _err, status = Open3.capture3('npx', 'playwright', '--version')
          return if status.success?

          raise 'Playwright がインストールされていません。npm install playwright を実行してください'
        end

        # --- vivliostyle preview サーバーの管理 ---

        # preview サーバーをバックグラウンドで起動
        # ポートが既に応答する場合は外部管理と見なし、起動をスキップする
        def start_preview_server!
          if port_open?(DEFAULT_HOST, port)
            @externally_managed = true
            @preview_url = build_fallback_url
            Common.log_info("[backlink-dedup] 既存の preview サーバーを検出しました (port: #{port})。起動をスキップします")
            return
          end

          launch_preview_process!
        end

        # preview プロセスを新規起動する内部メソッド
        def launch_preview_process!
          cmd = [
            'npx', 'vivliostyle', 'preview',
            '-c', 'vivliostyle.config.js',
            '--no-open-viewer',
            '--port', port.to_s
          ]

          env = { 'NO_COLOR' => '1', 'FORCE_COLOR' => '0', 'NODE_NO_WARNINGS' => '1' }
          @log_file = Tempfile.new(['vivliostyle-preview', '.log'])
          @preview_pid = spawn(env, *cmd, out: @log_file.path, err: @log_file.path, pgroup: true)
          Common.log_info("[backlink-dedup] preview サーバーを起動しました (PID: #{@preview_pid}, port: #{port})")

          wait_for_server_ready!
          extract_preview_url!
        end

        # サーバーがリクエストを受け付けるまで待機
        def wait_for_server_ready!
          Timeout.timeout(SERVER_STARTUP_TIMEOUT) do
            loop do
              break if port_open?(DEFAULT_HOST, port)

              # プロセスが死んでいないか確認
              begin
                Process.waitpid(@preview_pid, Process::WNOHANG)
              rescue Errno::ECHILD
                raise 'vivliostyle preview プロセスが起動に失敗しました'
              end

              sleep 0.5
            end
          end
          Common.log_info("[backlink-dedup] preview サーバーが応答可能になりました (port: #{port})")
        rescue Timeout::Error
          raise "vivliostyle preview が #{SERVER_STARTUP_TIMEOUT} 秒以内に起動しませんでした"
        end

        # Preview URL を設定する
        #
        # 【正規処理とフォールバックについて】
        # 本来は vivliostyle preview のログから "Preview URL: http://..." を抽出していた。
        # しかし vivliostyle CLI 10.4〜10.5 で terminalLink() が導入されたことで
        # 出力タイミングや形式が変わり、spawn でファイルリダイレクトした場合に
        # ログへの書き込みが間に合わなくなった（Node.js の stdout バッファリングが原因と推測）。
        #
        # 一方、--port と -c vivliostyle.config.js を指定した場合、vivliostyle preview は
        # 常に固定パターンの URL で起動することが確認されている。
        # フォールバック URL はそのパターンをハードコードしたものであり、
        # 正規処理で取得できていた URL と完全に一致するため、動作上の差異は一切ない。
        # そのため、フォールバック URL を正規処理として採用する。
        #
        # 旧実装（ログからの抽出）は参考のためコメントアウトして残す。
        def extract_preview_url!
          @preview_url = build_fallback_url
          Common.log_info("[backlink-dedup] Preview URL: #{@preview_url}")

          # --- 旧実装: ログファイルから Preview URL を抽出 ---
          # vivliostyle CLI 10.5.0 以降、spawn + ファイルリダイレクト環境では
          # Node.js の stdout バッファリングにより Preview URL がログに書き込まれないため廃止。
          #
          # Timeout.timeout(10) do
          #   loop do
          #     log_content = File.read(@log_file.path, encoding: 'utf-8') rescue ''
          #     clean_content = log_content.gsub(/\e\[[0-9;]*[mGKHF]/, '').gsub(/\e\][^\a]*\a/, '')
          #     if (match = clean_content.match(/Preview URL:\s*(https?:\/\/[^\s\n]+)/))
          #       @preview_url = match[1].strip
          #       return
          #     end
          #     sleep 0.5
          #   end
          # end
          # --- 旧実装ここまで ---
        end

        # 指定ポートが開いているか確認
        def port_open?(host, check_port)
          TCPSocket.new(host, check_port).close
          true
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT
          false
        end

        # preview サーバーを停止
        # 外部管理のサーバーは停止しない
        def stop_preview_server!
          if externally_managed
            Common.log_info('[backlink-dedup] 外部管理の preview サーバーのため停止をスキップします')
            return
          end
          return unless @preview_pid

          Common.log_info("[backlink-dedup] preview サーバーを停止します (PID: #{@preview_pid})")
          begin
            # プロセスグループごとシグナルを送信（子プロセスも含め確実に停止）
            Process.kill('-TERM', @preview_pid)
            Process.waitpid(@preview_pid, Process::WNOHANG)
          rescue Errno::ESRCH, Errno::ECHILD
            # すでに停止済み
          end
          @preview_pid = nil
          cleanup_log_file!
        end

        # フォールバック用の Preview URL を組み立てる
        def build_fallback_url
          "http://#{DEFAULT_HOST}:#{port}/__vivliostyle-viewer/index.html" \
            "#src=http://#{DEFAULT_HOST}:#{port}/vivliostyle/publication.json" \
            '&bookMode=true&renderAllPages=true'
        end

        # テンポラリログファイルを削除
        def cleanup_log_file!
          return unless @log_file

          @log_file.close
          @log_file.unlink
        rescue StandardError
          nil
        ensure
          @log_file = nil
        end

        # --- Playwright スクリプトの実行 ---

        # extract_page_mapping.mjs を実行して JSON を取得
        # @return [Hash] パース済み JSON
        def run_extraction_script!
          cmd = ['node', MAPPING_SCRIPT, @preview_url, timeout_ms.to_s]

          # グローバル npm パッケージを node が解決できるよう NODE_PATH を設定
          env = {}
          global_root = `npm root -g 2>/dev/null`.strip
          unless global_root.empty?
            existing = ENV.fetch('NODE_PATH', '')
            env['NODE_PATH'] = [global_root, existing].reject(&:empty?).join(File::PATH_SEPARATOR)
          end

          stdout, stderr, status = Open3.capture3(env, *cmd)

          unless status.success?
            Common.log_error('[backlink-dedup] Playwright スクリプトがエラーで終了しました')
            Common.log_error("[backlink-dedup] stderr: #{stderr}") unless stderr.empty?
            raise "ページマッピング抽出に失敗しました: #{stderr}"
          end

          JSON.parse(stdout, symbolize_names: true)
        rescue JSON::ParserError => e
          raise "ページマッピング JSON のパースに失敗しました: #{e.message}"
        end

        # --- 結果のパース ---

        # JSON 結果を Data オブジェクトに変換
        # @param raw [Hash] パース済み JSON
        # @return [PageMapping]
        def parse_result(raw)
          mappings = Array(raw[:mappings]).map do |entry|
            MappingEntry.new(
              anchor_id: entry[:anchor_id],
              href: entry[:href],
              page_index: entry[:page_index],
              spine_index: entry[:spine_index]
            )
          end

          backlink_mappings = Array(raw[:backlink_mappings]).map do |entry|
            BacklinkEntry.new(
              href: entry[:href],
              page_index: entry[:page_index],
              spine_index: entry[:spine_index]
            )
          end

          index_mappings = Array(raw[:index_mappings]).map do |entry|
            IndexMappingEntry.new(
              anchor_id: entry[:anchor_id],
              page_index: entry[:page_index],
              spine_index: entry[:spine_index]
            )
          end

          PageMapping.new(
            mappings:,
            backlink_mappings:,
            index_mappings:,
            total_pages: raw[:total_pages] || 0,
            extracted_at: raw[:extracted_at]
          )
        end
      end
    end
  end
end
