# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/mermaid_renderer.rb
# ================================================================
# 責務:
#   ```mermaid の図ソースを `@mermaid-js/mermaid-cli`（`mmdc`）で
#   SVG（PDF 用・ベクタ）／PNG（EPUB・Kindle 用・ラスター）へ描画する低レベルラッパ。
#   （mermaid-diagram-spec.md §4.3）
#
# なぜ mmdc なのか（§3.1・案 A）:
#   公式 CLI でオフライン描画でき、SVG 出力でベクタ品質を得られる。puppeteer 経由で
#   Chromium を起動して mermaid.js を評価するため描画は本家に追従する。HTTP サービス
#   （Kroki 等）は原稿の外部送信・再現性のサービス依存があり不採用（§11）。
#
# CJK フォント（§5.1・案 1）:
#   PDF では Vivliostyle が SVG の <text> を描画するため、図中テキストの font-family に
#   本書の和文フォントが解決できないと豆腐になる。mmdc の themeVariables.fontFamily を
#   本書の見出しフォント＋和文フォールバックに固定して SVG を出す（EPUB/Kindle は
#   ラスター化でレンダリング環境のフォントを焼き込むためこの問題は出ない）。
#
# テスト:
#   mmdc の実行は重く環境依存のため、上位（MermaidTransformer）はこのクラスを DI で
#   差し替える。ここでは Open3 で mmdc を叩く既定実装だけを持つ（§9）。
# ================================================================

require 'json'
require 'open3'
require 'tempfile'
require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # mmdc を呼び出して mermaid ソースを SVG / PNG へ描画する既定レンダラ。
      class MermaidRenderer
        # 既定テーマ（§5.2・第一段階はライト固定）。
        DEFAULT_THEME = 'neutral'

        # PNG（EPUB/Kindle 用ラスター）の解像度倍率。リーダー側の縮小表示で鮮明に見せる。
        RASTER_SCALE = 2

        # mmdc の実行が可能か（コマンドが解決でき --version が起動するか）。
        def available?
          !mmdc_command.nil?
        end

        # 導入済み mmdc のバージョン文字列（キャッシュキーの一部・図の再生成判定に使う）。
        # 取得できないときは空文字（キーの決定性は保たれる）。
        def version
          return @version if defined?(@version)

          @version = resolve_version
        end

        # mermaid ソースを 1 つ描画してバイト列を返す。失敗時は nil。
        #
        # @param source [String] mermaid の図ソース（フェンス内テキスト）
        # @param format [Symbol] :svg（PDF 用ベクタ）/ :png（EPUB/Kindle 用ラスター）
        # @param font_family [String, nil] 図中テキストの font-family（§5.1）
        # @param theme [String] mermaid テーマ（既定 neutral）
        # @return [String, nil] SVG 文字列 / PNG バイト列（失敗時 nil）
        def render(source, format:, font_family: nil, theme: DEFAULT_THEME)
          cmd = mmdc_command
          return nil if cmd.nil? || source.to_s.strip.empty?

          with_temp_files(source, font_family, format) do |input_path, config_path, puppeteer_path, output_path|
            argv = [cmd, '-i', input_path, '-o', output_path, '-b', 'transparent',
                    '-t', theme, '-c', config_path, '-p', puppeteer_path]
            argv.push('-s', RASTER_SCALE.to_s) if format == :png

            _out, status = Open3.capture2e(*argv)
            next nil unless status.success? && File.exist?(output_path) && !File.empty?(output_path)

            format == :svg ? File.read(output_path, encoding: 'utf-8') : File.binread(output_path)
          end
        rescue StandardError => e
          Common.log_debug("[mermaid] mmdc 実行でエラー: #{e.class}: #{e.message}")
          nil
        end

        private

        # 一時 .mmd / config / puppeteer / 出力ファイルを用意してブロックへ渡す。
        # Tempfile.new の GC 削除バグを避け Tempfile.create を使う（§4.3）。
        def with_temp_files(source, font_family, format)
          Tempfile.create(['vs-mermaid', '.mmd']) do |input|
            input.write(source)
            input.flush
            Tempfile.create(['vs-mermaid-config', '.json']) do |config|
              config.write(mermaid_config_json(font_family))
              config.flush
              Tempfile.create(['vs-mermaid-pptr', '.json']) do |puppeteer|
                puppeteer.write(PUPPETEER_CONFIG_JSON)
                puppeteer.flush
                Tempfile.create(['vs-mermaid-out', ".#{format}"]) do |output|
                  yield input.path, config.path, puppeteer.path, output.path
                end
              end
            end
          end
        end

        # mmdc へ渡す mermaid 設定 JSON。
        #
        # htmlLabels:false が肝——mermaid は既定で図中ラベルを <foreignObject> 内の HTML
        # （<div>/<span>）で描く。だが本書は SVG を <img src> で参照するため、ブラウザ
        # （Vivliostyle の PDF エンジン＝Chromium）は <img> 経由の SVG 内の foreignObject を
        # 描画しない仕様で、**PDF だとラベルだけ消える**（§5.1 案 1 の前提が崩れる）。
        # htmlLabels:false にすると native な <text>/<tspan> で描かれ、font-family を
        # Vivliostyle が解決できる（<br/> は tspan の複数行に分割される）。EPUB/Kindle 用の
        # PNG は mmdc（Chromium）が自前でラスタライズするためどちらでも文字は出るが、SVG も
        # native text に揃えて PDF と一致させる。
        #
        # fontFamily を本書の和文フォントへ固定し（§5.1 案 1）、useMaxWidth:false で SVG に
        # 実寸（intrinsic size）を持たせる（vivliostyle-css-pitfalls-notes: SVG intrinsic size）。
        def mermaid_config_json(font_family)
          config = { 'theme' => DEFAULT_THEME,
                     'htmlLabels' => false,
                     'flowchart' => { 'useMaxWidth' => false, 'htmlLabels' => false } }
          config['themeVariables'] = { 'fontFamily' => font_family } if font_family && !font_family.empty?
          JSON.generate(config)
        end

        # Chromium サンドボックスは CI / root 実行で起動に失敗しうるため無効化する
        # （Vivliostyle も同様の実行環境を通る前例に倣う）。
        PUPPETEER_CONFIG_JSON = JSON.generate({ 'args' => ['--no-sandbox', '--disable-setuid-sandbox'] })

        # mmdc コマンドを解決する。プロジェクト直下の node_modules/.bin を優先し、
        # 無ければ PATH 上の mmdc を使う（mathjax_root のローカル優先と同じ流儀）。
        def mmdc_command
          return @mmdc_command if defined?(@mmdc_command)

          @mmdc_command = resolve_mmdc_command
        end

        def resolve_mmdc_command
          local = File.join(Dir.pwd, 'node_modules', '.bin', 'mmdc')
          return local if File.executable?(local)

          return 'mmdc' if system('mmdc', '--version', out: File::NULL, err: File::NULL)

          nil
        end

        def resolve_version
          cmd = mmdc_command
          return '' if cmd.nil?

          out, status = Open3.capture2(cmd, '--version')
          status.success? ? out.strip : ''
        rescue StandardError
          ''
        end
      end
    end
  end
end
