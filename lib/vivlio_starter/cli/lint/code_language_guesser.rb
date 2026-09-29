# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/code_language_guesser.rb
# ================================================================
# 責務:
#   言語名のないコードブロックの言語を Guesslang で推定する（二段目）。
#   仕様: code-language-detection-spec.md §3.2〜§3.4・§4.2。
#
# なぜ Guesslang か:
#   Rouge は中身だけでは shebang や <!DOCTYPE> のある物しか当てられず、highlight.js は
#   関連度で実行結果と本物のコードを分けられなかった。Guesslang（VS Code の言語の
#   自動判定と同じモデル）は確信度が当たり外れをよく表す（仕様 §1）。
#
# 呼び出し方:
#   Guesslang は npm パッケージ（@vscode/vscode-languagedetection）なので、同梱の
#   guess_code_language.mjs を node で 1 回だけ起動し、全章の推定待ちをまとめて渡す
#   （モデルの読み込みが 1 回で済む）。パッケージはプロジェクトの node_modules を優先し、
#   無ければ npm のグローバル（vs doctor --fix が入れる場所）から読む。
# ================================================================

require 'json'
require 'open3'

module VivlioStarter
  module CLI
    module Lint
      # Guesslang を node で呼んで言語を推定する
      class CodeLanguageGuesser
        PACKAGE = '@vscode/vscode-languagedetection'
        SCRIPT = File.expand_path('guess_code_language.mjs', __dir__)

        # これより確信度の低い推定は知らせない。0.3 以上なら、本書と練習帳の実行結果・
        # 木・盤面に 1 件も言語が付かなかった（仕様 §1.5）。0.1〜0.3 は誤りが多い。
        MIN_CONFIDENCE = 0.3

        # Guesslang の言語 ID → Prism の言語名（仕様 §4.3）。ここに無い言語は推定の結果にしない。
        GUESSLANG_TO_PRISM = {
          'html' => 'html', 'css' => 'css', 'js' => 'javascript', 'ts' => 'typescript',
          'rb' => 'ruby', 'py' => 'python', 'c' => 'c', 'cpp' => 'cpp', 'java' => 'java',
          'go' => 'go', 'rs' => 'rust', 'json' => 'json', 'yaml' => 'yaml', 'sql' => 'sql',
          'sh' => 'bash', 'md' => 'markdown'
        }.freeze

        # 推定を頼む 1 件。candidates は Prism の言語名。
        Request = Data.define(:id, :body, :candidates)
        # 推定の結果
        Guess = Data.define(:language, :confidence)

        class Error < StandardError; end

        # node と Guesslang の両方が見つかるか
        def available? = node? && !package_dir.nil?

        # @param requests [Array<Request>]
        # @return [Hash{Object => Guess}] 確信度が MIN_CONFIDENCE 以上だったものだけ
        def guess(requests)
          return {} if requests.empty?

          payload = JSON.generate(package: package_dir, languages: GUESSLANG_TO_PRISM,
                                  items: requests.map { { id: it.id, body: it.body, candidates: it.candidates } })
          stdout, stderr, status = Open3.capture3('node', SCRIPT, stdin_data: payload)
          raise Error, "Guesslang の実行に失敗しました: #{stderr.lines.last&.strip}" unless status.success?

          JSON.parse(stdout).filter_map do |result|
            next if result['confidence'] < MIN_CONFIDENCE

            [result['id'], Guess.new(language: result['language'], confidence: result['confidence'])]
          end.to_h
        end

        # Guesslang の置き場所（パッケージのディレクトリ）。見つからなければ nil。
        def package_dir
          return @package_dir if defined?(@package_dir)

          roots = [File.join(Dir.pwd, 'node_modules'), npm_global_root].compact
          @package_dir = roots.map { File.join(it, PACKAGE) }.find { File.directory?(it) }
        end

        private

        def node?
          _out, status = Open3.capture2e('node', '--version')
          status.success?
        rescue SystemCallError
          false
        end

        def npm_global_root
          out, status = Open3.capture2('npm', 'root', '-g', err: File::NULL)
          root = out.strip
          status.success? && !root.empty? ? root : nil
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
