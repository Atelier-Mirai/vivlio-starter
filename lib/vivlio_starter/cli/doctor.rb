# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/doctor.rb
# ================================================================
# 責務:
#   Vivlio Starter の動作に必要な外部ツールの診断と自動インストールを行う。
#   あわせて config/ 配下の設定ファイルを診断し、--fix 時は scaffold から
#   復元する（docs/specs/doctor-restore-and-plugin-tools-spec.md Phase 5）。
#
# 診断対象ツール:
#   - Xcode Command Line Tools (macOS): ビルドツールチェーン
#   - node: JavaScript ランタイム（Vivliostyle CLI の依存）
#   - vivliostyle: PDF 生成エンジン
#   - textlint: 文章校正ツール
#   - qpdf: PDF 分割・結合・ページ操作（11 以上必須。入稿用 PDF 導出の
#     --update-from-json / --overlay を使用する）
#   - pdfinfo / pdftoppm (poppler): PDF メタデータ取得・ページ画像化
#   - gs (Ghostscript): PDF 圧縮
#   - imagemagick: 画像変換・リサイズ
#   - inkscape: ImageMagick が SVG を読む際の delegate（カバー生成の
#     ラスタライズ・フォールバック用。主経路は rsvg-convert）
#   - rsvg-convert (librsvg): EPUB 扉絵/節絵の合成画像ラスタライズ・カバー SVG 変換の主経路
#   - vips (libvips): 高速画像処理（Enhanced Mode の OCR 用）
#   - tesseract / tesseract-lang: OCR エンジンと日本語データ（Enhanced Mode 用）
#   - mecab: 索引機能の読み自動推測
#   - rouge: コードブロック言語推定（Ruby gem）
#   - mathjax (mathjax-full): 数式の SVG 化（npm パッケージ）
#   - waifu2x-ncnn-vulkan: AI 画像拡大（オプション）
#   - kindlepreviewer (Kindle Previewer 3): Kindle(KPF) 変換（任意・targets: kindle 用）
#   - Google Fonts 用 SSL 証明書 (macOS): Web フォント取得
#
# 自動インストール:
#   - macOS + Homebrew 環境でのみ対応
#   - --fix オプションで不足ツールを自動インストール
#   - Node.js ツール（vivliostyle, textlint）は npm -g でインストール
#
# 依存:
#   - Common: ログ出力
#   - Homebrew: macOS でのパッケージ管理
#   - npm: Node.js パッケージ管理
# ================================================================

require 'rbconfig'
require 'fileutils'
require 'net/http'
require 'uri'
require 'tempfile'
require 'digest'
require 'shellwords'
require 'open-uri'
require 'tmpdir'
require 'json'

require_relative 'guards'
require_relative 'doctor/config_salvager'

module VivlioStarter
  module CLI
    # 環境診断・ツールインストールコマンド
    module DoctorCommands
      module_function

      # scaffold 側 config/ への絶対パス（設定ファイル復元の供給元）
      SCAFFOLD_CONFIG_DIR = File.expand_path('../../project_scaffold/config', __dir__).freeze

      # 必須 YAML（Common::REQUIRED_YAML_FILES）以外で scaffold から復元する設定ファイル。
      # 破損判定はせず「欠落時のみ」復元する（spec §3.1）
      OPTIONAL_CONFIG_FILES = %w[textlint_allowlist.yml textlint_prh.yml .textlintrc.yml _README.md].freeze

      # 欠落時のみ scaffold から再帰コピーで復元する辞書ディレクトリ（中身の個別検証はしない）
      CONFIG_DIR_ENTRIES = %w[spellcheck_dictionaries textlint_dictionaries].freeze

      # Enhanced Mode（vivlio-starter-pdf）専用の OCR 系ツール。
      # プラグイン未導入時は不足してもエラー扱いせず 🟡 注記に回す（spec §5.1）。
      # poppler（pdfinfo / pdftoppm）は本体のビルドでも使うため含めない
      OCR_OPTIONAL_TOOLS = %w[tesseract tesseract-lang vips].freeze

      # Kindle Previewer 3 同梱の CLI（targets: kindle の KPF 変換専用の任意ツール）。
      # Build::EpubBuilder::KINDLEPREVIEWER_COMMAND と同値だが、doctor を軽量に保つため
      # epub_builder を require せず独立に持つ。kindle を使わない利用者には不足を
      # ハードエラーにせず 🟡 注記に回す。
      KINDLEPREVIEWER_COMMAND = 'kindlepreviewer'
      # macOS の Kindle Previewer 3 アプリ内 CLI 実行ファイル（ラッパーが呼ぶ実体）。
      KINDLE_PREVIEWER_APP_BIN = '/Applications/Kindle Previewer 3.app/Contents/MacOS/Kindle Previewer 3'

      # Enhanced Mode プラグインの gem 名（Pdf::PLUGIN_GEM_NAME と同値。
      # provider.rb は pdf/reader 等の重い require を伴うため doctor からは参照しない）
      PDF_PLUGIN_GEM_NAME = 'vivlio-starter-pdf'

      TEXTLINT_NPM_PACKAGES = %w[
        textlint
        textlint-rule-preset-ja-technical-writing
        textlint-rule-preset-japanese
        textlint-rule-prh
        textlint-filter-rule-node-types
        textlint-filter-rule-allowlist
        textlint-filter-rule-comments
        textlint-rule-no-dropping-the-ra
        textlint-rule-max-ten
        textlint-rule-ja-no-mixed-period
        textlint-rule-no-doubled-conjunction@3.0.0
        textlint-rule-no-doubled-joshi
        textlint-rule-ja-no-successive-word
        textlint-rule-preset-ja-spacing
        textlint-rule-spellcheck-tech-word
        textlint-rule-no-dead-link
        textlint-rule-ng-word
      ].freeze

      # img2pdfの依存排除に伴い、診断対象および説明からimg2pdfを削除しています。
      DOCTOR_DESC = {
        short: '必要ツール(Xcode Command Line Tools, qpdf, pdfinfo, pdftoppm, gs, ImageMagick, Inkscape)の診断とセットアップを行います',
        long: <<~DESC
          環境診断を行い、以下の外部コマンドの存在をチェックします:
            - Xcode Command Line Tools (macOS)
            - qpdf
            - pdfinfo / pdftoppm (poppler)
            - node
            - vivliostyle
            - textlint
            - gs
            - imagemagick
            - inkscape
            - rsvg-convert (librsvg)
            - vips / tesseract / tesseract-lang (Enhanced Mode の OCR 用)
            - mecab
            - rouge
            - mathjax (mathjax-full)
            - waifu2x
            - kindlepreviewer (Kindle Previewer 3・targets: kindle の KPF 変換時のみ。任意)

          役割の補足:
            - 圧縮は Ghostscript(pdfwrite) を使用します
            - qpdf は分割/結合・ページ抽出などの PDF 操作用に使用します（圧縮用途ではありません）。
              入稿用 PDF の導出（--update-from-json / --overlay）にバージョン 11 以上が必要です

          --fix オプション指定時、macOS かつ Homebrew が利用可能であれば
          不足しているツールの自動インストールを試みます。

          例:
            vs doctor
            vs doctor --fix
        DESC
      }.freeze

      # 後方互換用の空フック
      def included(base); end

      # 環境診断を実行し、不足ツールを報告・インストールする
      #
      # @param command [Hash, Object, nil] コマンドコンテキスト
      #   - Hash: { options: { fix: true, yes: true, verbose: false } }
      #   - Object: #options で Hash を返すオブジェクト
      # @return [void]
      #
      # オプション:
      #   - :fix [Boolean] 不足ツールを自動インストール（macOS + Homebrew のみ）
      #   - :yes [Boolean] 確認プロンプトをスキップ
      #   - :verbose [Boolean] 詳細ログを出力
      def execute_doctor(command = nil)
        options = extract_options(command)
        ENV['VERBOSE'] = '1' if options[:verbose]

        missing = []
        os = RbConfig::CONFIG['host_os']
        is_macos = os =~ /darwin/i

        Common.log_always('🔎 環境診断を開始します…')

        # --- Phase: 設定ファイル診断・復元（書籍プロジェクト内のみ）---
        diagnose_config_files!(options)

        # --- Phase: 外部ツール診断 ---
        # macOS では Xcode Command Line Tools が多くのビルドツールの前提条件
        if is_macos
          clt_ok = system('xcode-select -p >/dev/null 2>&1')
          if clt_ok
            Common.log_always('✅ Xcode Command Line Tools: OK')
          else
            Common.log_error('Xcode Command Line Tools: 見つかりません')
            missing << 'xcode-command-line-tools'
          end
        end

        # コマンド存在チェック定義
        # ※ img2pdfはJPEGからPDFへの結合に独自実装 JpegToPdf を使用するため依存排除されました。
        checks = {
          'node' => 'node',
          'textlint' => 'textlint',
          'vivliostyle' => 'vivliostyle',
          'qpdf' => 'qpdf',
          'pdfinfo' => 'pdfinfo',
          'pdftoppm' => 'pdftoppm',
          'gs' => 'gs', # Ghostscript
          'imagemagick' => nil,
          # inkscape はここには含めない。カバー SVG ラスタライズの主経路は rsvg-convert で、
          # inkscape は ImageMagick の SVG フォールバックでしか使われない任意ツールのため、
          # kindlepreviewer と同様にループ外で個別に診断する（ハードエラーにしない）。
          'vips' => 'vips',
          'tesseract' => 'tesseract',
          'tesseract-lang' => nil,
          'waifu2x' => nil,
          'mecab' => 'mecab', # 索引機能の読み自動推測用
          'rouge' => nil, # コードブロック言語推定用
          'mathjax' => nil, # 数式の SVG 化用（mathjax-full・npm パッケージ）
          'rsvg-convert' => 'rsvg-convert' # EPUB 扉絵/節絵の合成画像ラスタライズ用（librsvg）
        }

        plugin_installed = pdf_plugin_installed?
        ocr_optional_missing = []

        checks.each do |label, cmd|
          ok = case label
               when 'imagemagick'
                 command_exists?('convert') || command_exists?('magick')
               when 'tesseract-lang'
                 tesseract_language_available?('jpn')
               when 'waifu2x'
                 waifu2x_available?
               when 'rouge'
                 rouge_gem_available?
               when 'mathjax'
                 mathjax_full_available?
               else
                 command_exists?(cmd)
               end

          if ok
            Common.log_always("✅ #{label}: OK")
          elsif OCR_OPTIONAL_TOOLS.include?(label) && !plugin_installed
            # Enhanced Mode 専用ツールはプラグイン未導入の利用者にとってノイズのため
            # エラーにせず、後段でまとめて 🟡 注記を出す（spec §5.1）
            ocr_optional_missing << label
          else
            Common.log_error("#{label}: 見つかりません")
            missing << label
          end
        end

        # inkscape は任意ツール（カバー SVG ラスタライズの主経路は rsvg-convert。inkscape は
        # ImageMagick の SVG フォールバックでしか使われない）。存在＋起動可能なら ✅、
        # 壊れ/不在は --fix(macOS) で復旧を試み、それ以外は 🟡 案内（ハードエラーにしない）。
        # command_runnable? を使うのは、半壊ラッパー（在るのに exit 126）まで見抜くため。
        inkscape_ok = command_runnable?('inkscape')
        Common.log_always('✅ inkscape: OK') if inkscape_ok

        # kindlepreviewer（Kindle Previewer 3）は targets: kindle 専用の任意ツール。
        # 存在すれば ✅、無ければ後段で 🟡 案内（ハードエラーにはしない）。
        kindle_previewer_present = command_exists?(KINDLEPREVIEWER_COMMAND)
        Common.log_always('✅ kindlepreviewer (Kindle Previewer 3): OK') if kindle_previewer_present

        if is_macos
          if ssl_certificate_configured?
            Common.log_always('✅ Google Fonts 用 SSL 証明書: OK')
          else
            Common.log_error('Google Fonts 用 SSL 証明書: 未設定 (Google Fonts のダウンロードに必要)')
            missing << 'ssl-certificates'
          end
        end

        # Vivliostyle の headless Chrome キャッシュの健全性（中断ビルド等で壊れた残骸を掃除）
        # ※ missing.empty? の早期 return より前に実行し、他ツールが揃っていても修復できるようにする
        handle_vivliostyle_chrome(options)

        report_ocr_optional_tools(ocr_optional_missing)
        # --fix 時は OCR ツールも従来どおり先回りインストールする（spec §5.1）
        missing.concat(ocr_optional_missing) if options[:fix]

        # kindlepreviewer が不足の場合、--fix(macOS) ならインストール対象に積み（後段で導入）、
        # それ以外は 🟡 案内に留める（OCR ツールと同じ「任意ツールは fix 時だけ missing に積む」方式）。
        unless kindle_previewer_present
          if options[:fix] && is_macos
            missing << KINDLEPREVIEWER_COMMAND
          else
            report_kindle_previewer_optional(is_macos)
          end
        end

        # inkscape も同方式（任意ツール）。--fix(macOS) なら復旧を試み、それ以外は 🟡 案内。
        unless inkscape_ok
          if options[:fix] && is_macos
            missing << 'inkscape'
          else
            report_inkscape_optional(is_macos)
          end
        end

        os_family = detect_os_family(os)
        waifu2x_install_root = nil
        if options[:fix] && missing.include?('waifu2x')
          if os_family != :macos
            Common.log_warn('waifu2x の自動インストールは現在 macOS のみ対応しています。Linux / Windows では手動セットアップを行ってください。')
          elsif install_waifu2x_macos! do |paths|
                  waifu2x_install_root = paths[:install]
                end
            missing.delete('waifu2x') if waifu2x_available?
          else
            Common.log_warn('waifu2x の自動インストールに失敗しました。手動セットアップを確認してください。')
          end
        end

        if missing.empty?
          Common.log_always('🎉 すべての必要ツールが見つかりました')
          return
        end

        Common.log_always("不足しているツール: #{describe_missing(missing).join(', ')}")

        unless options[:fix]
          Common.log_always('ヒント: macOS の場合は `vs doctor --fix` で自動インストールを試行できます')
          if missing.include?('xcode-command-line-tools')
            Common.log_always('  Xcode Command Line Tools は手動でも `xcode-select --install` で導入できます')
          end
          return
        end

        # --fix: 自動インストール試行
        unless is_macos
          Common.log_always('自動インストールは macOS(Homebrew) のみ対応です。手動でインストールしてください。')
          return
        end

        # 先に CLT を処理（GUI 承認が必要）
        if missing.include?('xcode-command-line-tools')
          proceed = options[:yes]
          if !proceed && $stdin.tty?
            $stdout.print('Xcode Command Line Tools をインストールしますか？ [y/N]: ')
            ans = $stdin.gets
            proceed = ans && ans.strip.downcase == 'y'
          end
          if proceed
            Common.log_always('Xcode Command Line Tools のインストーラを起動します…')
            system('xcode-select --install >/dev/null 2>&1 || true')
            # ポーリングで最大 5 分間待機（5 秒間隔）
            waited = 0
            until system('xcode-select -p >/dev/null 2>&1') || waited >= 300
              sleep 5
              waited += 5
            end
            if system('xcode-select -p >/dev/null 2>&1')
              Common.log_always('✅ Xcode Command Line Tools が確認できました')
              missing.delete('xcode-command-line-tools')
            else
              Common.log_warn('インストールの確認ができませんでした。インストーラ完了後に再実行してください。')
            end
          else
            Common.log_always('Xcode Command Line Tools の自動インストールをスキップします。必要に応じて `xcode-select --install` を実行してください。')
          end
        end

        unless system('which brew >/dev/null 2>&1')
          Common.log_always('Homebrew が見つかりません。自動インストールを試みます。')
          proceed = options[:yes]
          if !proceed && $stdin.tty?
            $stdout.print('Homebrew をインストールしますか？ [y/N]: ')
            ans = $stdin.gets
            proceed = ans && ans.strip.downcase == 'y'
          end
          if proceed
            begin
              # 公式インストーラ実行（要ネットワーク）
              cmd = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
              system(cmd)
            rescue StandardError => e
              Common.log_warn("Homebrew のインストールでエラー: #{e}")
            end
            # PATH 調整（Apple Silicon / Intel を想定）
            brew_bins = ['/opt/homebrew/bin', '/usr/local/bin']
            brew_bin = brew_bins.find { |p| File.exist?(File.join(p, 'brew')) }
            ENV['PATH'] = [brew_bin, ENV.fetch('PATH', nil)].compact.join(':') if brew_bin
          else
            Common.log_always('Homebrew をインストールしないため、自動インストール処理を中止します。手動で https://brew.sh/ を参照してください。')
            return
          end
          unless system('which brew >/dev/null 2>&1')
            Common.log_always('Homebrew コマンドが見つかりませんでした。シェルの再起動や PATH 設定を確認してください。')
            return
          end
        end

        Common.log_always('🛠 Homebrew による不足ツールのインストールを実行します…')
        begin
          # Node.js（node@20 を優先）
          if missing.include?('node')
            Common.log_always('node をインストールします（node@20 優先）…')
            ok = system('brew install node@20')
            ok ||= system('brew install node')
            Common.log_always('node の Homebrew インストールに失敗しました。手動インストールをご検討ください。') unless ok
          end

          # qpdf / poppler(pdfinfo, pdftoppm)
          system('brew install qpdf') if missing.include?('qpdf')
          system('brew install poppler') if missing.any? { %w[pdfinfo pdftoppm].include?(it) }

          # Ghostscript
          system('brew install ghostscript') if missing.include?('gs')

          # ImageMagick
          system('brew install imagemagick') if missing.include?('imagemagick')

          # Inkscape（任意・カバー SVG フォールバック用）。半壊 cask も復旧できるよう force 対応。
          install_inkscape_macos! if missing.include?('inkscape')

          # librsvg（rsvg-convert）: EPUB 扉絵/節絵の合成画像ラスタライズ用
          system('brew install librsvg') if missing.include?('rsvg-convert')

          system('brew install vips') if missing.include?('vips')

          system('brew install tesseract') if missing.include?('tesseract')
          system('brew install tesseract-lang') if missing.include?('tesseract-lang')

          # MeCab（索引機能の読み自動推測用）
          if missing.include?('mecab')
            Common.log_always('MeCab（索引機能の読み自動推測用）をインストールします…')
            system('brew install mecab mecab-ipadic')
          end

          # Rouge（コードブロック言語推定用）
          if missing.include?('rouge')
            Common.log_always('Rouge（コードブロック言語推定用）をインストールします…')
            system('gem install rouge')
          end

          # mathjax-full（数式の SVG 化用・npm パッケージ）
          if missing.include?('mathjax')
            if system('which npm >/dev/null 2>&1')
              Common.log_always('数式の SVG 化用 mathjax-full をインストールします…')
              system('npm install --loglevel=error -g mathjax-full')
            else
              Common.log_always('npm が見つかりません。node のインストール後に `npm install -g mathjax-full` を実行してください。')
            end
          end

          # Kindle Previewer 3（kindlepreviewer）: cask 導入＋アプリ内 CLI への PATH ラッパー作成
          install_kindlepreviewer_macos! if missing.include?(KINDLEPREVIEWER_COMMAND)

          install_ssl_certificates! if missing.include?('ssl-certificates')
        rescue StandardError => e
          Common.log_warn("brew 実行でエラー: #{e}")
        end

        # Vivliostyle CLI（npm -g）
        begin
          if missing.include?('vivliostyle')
            if system('which npm >/dev/null 2>&1')
              Common.log_always('Vivliostyle CLI(@vivliostyle/cli) をグローバルインストールします…')
              system('npm install --loglevel=error -g @vivliostyle/cli')
            else
              Common.log_always('npm が見つかりません。node のインストール後に `npm install -g @vivliostyle/cli` を実行してください。')
            end
          end
        rescue StandardError => e
          Common.log_warn("npm 実行でエラー: #{e}")
        end

        # textlint と推奨ルール
        begin
          if missing.include?('textlint')
            if system('which npm >/dev/null 2>&1')
              Common.log_always('textlint と推奨 Textlint ルールをグローバルインストールします…')
              packages = TEXTLINT_NPM_PACKAGES.map { |pkg| Shellwords.escape(pkg) }.join(' ')
              system("npm install --loglevel=error -g #{packages}")
            else
              Common.log_always('npm が見つかりません。node のインストール後に `npm install -g textlint textlint-rule-preset-ja-technical-writing ...` を実行してください。')
            end
          end
        rescue StandardError => e
          Common.log_warn("npm 実行でエラー: #{e}")
        end

        # 再診断
        Common.log_always('🔁 インストール後の再診断…')
        still_missing = []
        checks.each do |label, cmd|
          ok = case label
               when 'imagemagick'
                 command_exists?('convert') || command_exists?('magick')
               when 'tesseract-lang'
                 tesseract_language_available?('jpn')
               when 'waifu2x'
                 waifu2x_available? || (waifu2x_install_root && waifu2x_present_at?(waifu2x_install_root, os_family))
               when 'rouge'
                 rouge_gem_available?
               when 'mathjax'
                 mathjax_full_available?
               else
                 command_exists?(cmd)
               end
          still_missing << label unless ok
        end
        still_missing << 'ssl-certificates' if is_macos && !ssl_certificate_configured?
        # プラグイン未導入の利用者には OCR ツールの不足を ❗ として残さない（spec §5.1）
        still_missing.reject! { OCR_OPTIONAL_TOOLS.include?(it) } unless plugin_installed

        # inkscape は任意ツール。--fix で導入を試みてもなお壊れている場合はハード ❗ ではなく
        # 🟡 で補足する（主経路は rsvg-convert なのでカバー生成自体は可能）。
        if missing.include?('inkscape') && !command_runnable?('inkscape')
          report_inkscape_optional(is_macos, install_failed: true)
        end

        if still_missing.empty?
          Common.log_always('✅ すべてのツールがインストールされました')
        else
          Common.log_always("❗ まだ見つからないツールがあります: #{describe_missing(still_missing).join(', ')}。手動でのセットアップをご確認ください。")
        end
      end
      module_function :execute_doctor

      def extract_options(command_or_ctx)
        source =
          if command_or_ctx.nil?
            {}
          elsif command_or_ctx.is_a?(Hash)
            command_or_ctx[:options] || command_or_ctx
          elsif command_or_ctx.respond_to?(:options)
            command_or_ctx.options || {}
          else
            command_or_ctx
          end

        symbolize_option_keys(source || {})
      end
      module_function :extract_options

      def symbolize_option_keys(hash)
        return {} unless hash.respond_to?(:each_with_object)

        hash.each_with_object({}) do |(key, value), result|
          sym_key = key.is_a?(String) ? key.to_sym : key
          result[sym_key || key] = value
        end
      end
      module_function :symbolize_option_keys
    end
  end
end

module VivlioStarter
  module CLI
    module DoctorCommands
      module_function

      def ssl_certificate_configured?
        test_cmd = "ruby -ropen-uri -e 'URI.open(\"https://fonts.googleapis.com/css2?family=Roboto&display=swap\") { |r| exit(r.status.first == \"200\" ? 0 : 1) }'"
        system(test_cmd)
      rescue StandardError
        false
      end

      def install_ssl_certificates!
        Common.log_always('Google Fonts 用に ca-certificates / openssl@3 を設定します…')
        system('brew update >/dev/null 2>&1')
        system('brew install openssl@3') unless system('brew list --versions openssl@3 >/dev/null 2>&1')
        system('brew reinstall ca-certificates')

        openssl_prefix = capture_command('brew --prefix openssl@3').strip
        if openssl_prefix.empty?
          openssl_prefix = File.join(capture_command('brew --prefix').strip, 'opt',
                                     'openssl@3')
        end

        cert_file = File.join(openssl_prefix, 'etc', 'openssl@3', 'cert.pem')
        cert_dir  = File.join(openssl_prefix, 'etc', 'openssl@3', 'certs')

        if File.file?(cert_file)
          ENV['SSL_CERT_FILE'] = cert_file
          ENV['SSL_CERT_DIR'] = cert_dir if Dir.exist?(cert_dir)

          persist_env('SSL_CERT_FILE', cert_file)
          persist_env('SSL_CERT_DIR', cert_dir) if Dir.exist?(cert_dir)

          Common.log_always("✅ SSL_CERT_FILE を #{cert_file} に設定しました")
          Common.log_always("✅ SSL_CERT_DIR を #{cert_dir} に設定しました") if Dir.exist?(cert_dir)
        else
          Common.log_warn("証明書ファイルが見つかりませんでした。#{openssl_prefix} に openssl@3 が存在するか確認してください。")
        end
      end

      def capture_command(cmd)
        `#{cmd}`
      rescue StandardError
        ''
      end

      def persist_env(key, value)
        return if value.nil? || value.empty?

        line = %(export #{key}="#{value}")
        profiles = %w[~/.zshrc ~/.bash_profile ~/.bashrc]
        profiles.each do |path|
          expanded = File.expand_path(path)
          begin
            if File.exist?(expanded)
              next if File.read(expanded, encoding: 'utf-8').include?(line)

              File.open(expanded, 'a', encoding: 'utf-8') do |f|
                f.puts unless File.read(expanded, encoding: 'utf-8').end_with?("\n")
                f.puts(line)
              end
            else
              FileUtils.mkdir_p(File.dirname(expanded))
              File.write(expanded, "#{line}\n", mode: 'a', encoding: 'utf-8')
            end
          rescue StandardError => e
            Common.log_warn("環境変数 #{key} の永続化に失敗しました (#{expanded}): #{e.class}: #{e.message}")
          end
        end
      end

      # ============================================================
      # 設定ファイルの診断・復元（spec §3 機能 A / §3D 機能 D）
      # ============================================================
      # 旧 copy_textlint_* 群はここへ統合した（scaffold ルート直下を参照して
      # いたため実際には何もコピーされない不具合も同時に解消）。

      # config/ 配下を診断し、--fix 時は scaffold から復元する。
      # 無関係なディレクトリに config/ を生成しないため、書籍プロジェクトの
      # 痕跡（config/ または vivliostyle.config.js）が無い場所では何もしない。
      def diagnose_config_files!(options)
        return unless book_project_dir?

        # --- Phase: 検出 ---
        # 必須 YAML は破損（YAML 解析不能）まで判定し、その他は欠落のみを見る
        broken = {}
        Common::REQUIRED_YAML_FILES.each do |path|
          case Guards::ConfigValidityCheck.diagnose(path)
          in [:ok, _] then next
          in [:missing, _]
            broken[path] = :missing
            Common.log_error("設定ファイルが見つかりません: #{path}")
          in [:corrupt, detail]
            broken[path] = :corrupt
            Common.log_error("設定ファイルが不正です: #{path}（YAML 解析に失敗）", detail:)
          end
        end

        missing_files = missing_optional_config_files
        missing_dirs = missing_config_dirs
        missing_files.each { Common.log_warn("設定ファイルが見つかりません: config/#{it}") }
        missing_dirs.each  { Common.log_warn("設定ディレクトリが見つかりません: config/#{it}/") }

        if broken.empty? && missing_files.empty? && missing_dirs.empty?
          Common.log_always('✅ config/ 設定ファイル: OK')
          return
        end

        unless options[:fix]
          Common.log_always('        修復するには vs doctor --fix を実行してください（破損ファイルはバックアップを取得します）')
          return
        end

        return unless confirm_config_restore?(options)

        # --- Phase: 復元 ---
        FileUtils.mkdir_p(Common::CONFIG_DIR)
        broken.each { |path, status| restore_required_yaml!(path, corrupt: status == :corrupt) }
        missing_files.each { restore_scaffold_file!(it) }
        missing_dirs.each  { restore_scaffold_dir!(it) }
      rescue StandardError => e
        Common.log_warn("設定ファイルの診断・復元に失敗しました: #{e.class}: #{e.message}")
      end

      # 書籍プロジェクトの中かどうか（復元対象の config/ か、プロジェクトの
      # 目印である vivliostyle.config.js があれば対象とみなす）
      def book_project_dir? = Dir.exist?(Common::CONFIG_DIR) || File.file?(Common::VIVLIOSTYLE_CONFIG_FILE)

      def missing_optional_config_files
        OPTIONAL_CONFIG_FILES.reject { File.file?(File.join(Common::CONFIG_DIR, it)) }
                             .select { File.file?(File.join(SCAFFOLD_CONFIG_DIR, it)) }
      end

      def missing_config_dirs
        CONFIG_DIR_ENTRIES.reject { Dir.exist?(File.join(Common::CONFIG_DIR, it)) }
                          .select { Dir.exist?(File.join(SCAFFOLD_CONFIG_DIR, it)) }
      end

      # 復元の最終確認。--yes または非対話（パイプ実行・CI）では自動で進める。
      # 破損ファイルは必ず .bak へ退避するため、非対話でも非破壊（spec §3.2）
      def confirm_config_restore?(options)
        return true if options[:yes] || !$stdin.tty?

        $stdout.print('設定ファイルを初期状態から復元しますか？（破損ファイルはバックアップを取得します） [y/N]: ')
        ans = $stdin.gets
        return true if ans && ans.strip.downcase == 'y'

        Common.log_always('設定ファイルの復元をスキップしました。')
        false
      end

      # 必須 YAML 1 件を復元する。破損時は必ず .bak へ退避した上で（spec §3.2）、
      # サルベージ（機能 D）→ 失敗なら素の scaffold 復元の順で試みる。
      def restore_required_yaml!(path, corrupt:)
        scaffold_path = File.join(SCAFFOLD_CONFIG_DIR, File.basename(path))
        return Common.log_warn("scaffold に同名ファイルが無いため復元できません: #{path}") unless File.file?(scaffold_path)

        backup_path = nil
        salvaged = nil
        if corrupt
          corrupt_content = File.read(path, encoding: 'utf-8')
          backup_path = backup_corrupt_file!(path)
          # サルベージは best-effort。失敗は握りつぶして素の scaffold 復元へ進む（spec §3D.1）
          salvaged = begin
            ConfigSalvager.salvage(path, corrupt_content, scaffold_path)
          rescue StandardError => e
            Common.log_debug("サルベージに失敗したため初期状態から復元します: #{e.class}: #{e.message}")
            nil
          end
        end

        if salvaged
          File.write(path, salvaged.content, encoding: 'utf-8')
          Common.log_always("✅ #{salvaged.summary}")
          salvaged.notes.each { Common.log_always("        #{it}") }
        else
          # book.yml はテンプレートのため、素の復元でもプレースホルダを既定値へ展開する
          content = if File.basename(path) == 'book.yml'
                      ConfigSalvager.render_book_yml(scaffold_path)
                    else
                      File.read(scaffold_path, encoding: 'utf-8')
                    end
          File.write(path, content, encoding: 'utf-8')
          Common.log_always("✅ #{path} を初期状態から復元しました")
        end
        Common.log_always("        以前の設定は #{backup_path} から書き戻せます") if backup_path
      end

      # 破損ファイルを <path>.bak.<timestamp> へ退避する（機能 A の安全規約）
      def backup_corrupt_file!(path)
        backup_path = "#{path}.bak.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        FileUtils.mv(path, backup_path)
        Common.log_always("        破損したファイルを #{backup_path} へ退避しました")
        backup_path
      end

      def restore_scaffold_file!(basename)
        FileUtils.cp(File.join(SCAFFOLD_CONFIG_DIR, basename), File.join(Common::CONFIG_DIR, basename))
        Common.log_always("✅ config/#{basename} を初期状態から復元しました")
      end

      def restore_scaffold_dir!(basename)
        FileUtils.cp_r(File.join(SCAFFOLD_CONFIG_DIR, basename), File.join(Common::CONFIG_DIR, basename))
        Common.log_always("✅ config/#{basename}/ を初期状態から復元しました")
      end

      # ============================================================
      # プラグイン外部ツールの診断統合（spec §5 機能 C）
      # ============================================================

      # Enhanced Mode プラグインの導入有無（OCR ツールの診断ラベル出し分け用）。
      # provider.rb と異なり require はせず、インストール済み gemspec の有無のみを見る
      # （doctor は判定だけが目的で、プラグイン本体や HexaPDF のロードは不要なため）
      def pdf_plugin_installed?
        Gem.path.any? { Dir.glob(File.join(it, 'specifications', "#{PDF_PLUGIN_GEM_NAME}-*.gemspec")).any? }
      rescue StandardError
        false
      end

      # プラグイン未導入時の OCR ツール案内（不足でもエラー扱いにしない / spec §5.2）
      def report_ocr_optional_tools(labels)
        return if labels.empty?

        lines = []
        lines << '- tesseract / tesseract-lang（OCR エンジン）' if labels.intersect?(%w[tesseract tesseract-lang])
        lines << '- vips（画像処理）' if labels.include?('vips')
        lines << "gem install #{PDF_PLUGIN_GEM_NAME} 後、vs doctor --fix でまとめて導入できます"
        Common.log_warn('任意ツール（pdf:read Enhanced Mode 用・vivlio-starter-pdf 利用時に必要）:',
                        detail: lines.join("\n"))
      end

      # kindlepreviewer 未導入時の案内（targets: kindle の KPF 変換時のみ必要・不足はエラーにしない）
      def report_kindle_previewer_optional(is_macos)
        detail = if is_macos
                   'macOS では vs doctor --fix で自動導入できます（Homebrew cask kindle-previewer ＋ PATH ラッパー作成）。'
                 else
                   'Amazon KDP のサイトから Kindle Previewer 3 を導入し、kindlepreviewer に PATH を通してください。'
                 end
        Common.log_warn('任意ツール kindlepreviewer（Kindle Previewer 3・targets: kindle の KPF 変換時のみ必要）:',
                        detail:)
      end

      # inkscape 不在/破損時の 🟡 案内（任意ツール）。
      # カバー SVG のラスタライズ主経路は rsvg-convert なので、無くてもカバー生成は通る。
      # 半壊 cask（記録は在るのに app 本体が消え、ラッパーが exit 126）の復旧には
      # 通常の brew install ではなく --force 再インストールが要る点を明示する。
      #
      # @param is_macos [Boolean]
      # @param install_failed [Boolean] --fix で導入を試みた後の案内か（見出しを変える）
      def report_inkscape_optional(is_macos, install_failed: false)
        heading = if install_failed
                    '任意ツール inkscape の導入に失敗しました（主経路は rsvg-convert なのでカバー生成は可能）:'
                  else
                    '任意ツール inkscape（ImageMagick の SVG フォールバック用・主経路は rsvg-convert）:'
                  end
        detail = if is_macos
                   "macOS では次で導入/復旧できます:\n" \
                     '  brew reinstall --cask --force inkscape   # 半壊 cask（app 本体欠落）の復旧\n' \
                     '  brew install --cask inkscape             # 未導入からの新規インストール'
                 else
                   'https://inkscape.org/ から導入し、inkscape に PATH を通してください。'
                 end
        Common.log_warn(heading, detail:)
      end

      # inkscape を macOS へ導入/復旧する（任意ツール）。
      # 通常の `brew install --cask inkscape` を先に試し、失敗（半壊 cask のアップグレード扱いで
      # purge に失敗する等）した場合は `brew reinstall --cask --force inkscape` で復旧する。
      #
      # @return [Boolean] 導入/復旧に成功したか
      def install_inkscape_macos!
        unless system('which brew >/dev/null 2>&1')
          Common.log_warn('Homebrew が見つからないため inkscape を導入できません。')
          return false
        end

        Common.log_always('Inkscape を導入します（Homebrew cask）…')
        return true if system('brew install --cask inkscape')

        # 半壊 cask（記録は在るのに /Applications/Inkscape.app が無い等）は通常インストールが
        # アップグレード扱いになり purge に失敗する。--force 再インストールで上書き復旧する。
        Common.log_warn('通常インストールに失敗しました。壊れた cask を --force で再インストールします…')
        system('brew reinstall --cask --force inkscape')
      end

      # Kindle Previewer 3（kindlepreviewer）を macOS へ導入する。
      # cask でアプリ本体（Pkg・管理者パスワードを求められることがある）を入れた後、
      # 単体では PATH に乗らない CLI を呼ぶラッパーを Homebrew の bin へ作成する
      # （アプリ内 "Kindle Previewer 3" 実行ファイルを引数透過で呼ぶ定石を自動化）。
      def install_kindlepreviewer_macos!
        unless system('which brew >/dev/null 2>&1')
          Common.log_warn('Homebrew が見つからないため kindlepreviewer を導入できません。')
          return false
        end

        Common.log_always('Kindle Previewer 3（kindlepreviewer）を導入します（Homebrew cask）…')
        system('brew install --cask kindle-previewer')

        unless File.exist?(KINDLE_PREVIEWER_APP_BIN)
          Common.log_warn("Kindle Previewer 3 の実行ファイルが見つかりません: #{KINDLE_PREVIEWER_APP_BIN}")
          return false
        end

        bin_dir = homebrew_bin_dir
        unless bin_dir
          Common.log_warn('Homebrew の bin ディレクトリを特定できず、kindlepreviewer ラッパーを作成できません。')
          return false
        end

        !create_kindlepreviewer_wrapper!(KINDLE_PREVIEWER_APP_BIN, bin_dir).nil?
      end

      # アプリ内 CLI（app_bin）を引数透過で呼ぶ kindlepreviewer ラッパーを bin_dir に作成する。
      # 既存の手動セットアップと同形の sh ラッパーを生成し、実行権限を付与する。
      # @return [String, nil] 作成したラッパーのパス（失敗時 nil）
      def create_kindlepreviewer_wrapper!(app_bin, bin_dir)
        wrapper = File.join(bin_dir, 'kindlepreviewer')
        File.write(wrapper, %(#!/bin/sh\n"#{app_bin}" "$@"\n))
        FileUtils.chmod('+x', wrapper)
        Common.log_always("kindlepreviewer ラッパーを作成しました: #{wrapper}")
        wrapper
      rescue StandardError => e
        Common.log_warn("kindlepreviewer ラッパー作成に失敗: #{e}")
        nil
      end

      # Homebrew の bin ディレクトリ（PATH 上）を返す。特定できなければ nil。
      def homebrew_bin_dir
        prefix = `brew --prefix 2>/dev/null`.strip
        return nil if prefix.empty?

        bin = File.join(prefix, 'bin')
        Dir.exist?(bin) ? bin : nil
      end

      # 不足しているツールの表示名マッピングを返します。
      # ※ img2pdfは依存排除されたため削除されています。
      def describe_missing(keys)
        return [] unless keys

        label_map = {
          'xcode-command-line-tools' => 'Xcode Command Line Tools',
          'node' => 'node',
          'vivliostyle' => 'Vivliostyle CLI',
          'textlint' => 'textlint',
          'qpdf' => 'qpdf',
          'pdfinfo' => 'pdfinfo (poppler)',
          'pdftoppm' => 'pdftoppm (poppler)',
          'gs' => 'Ghostscript',
          'imagemagick' => 'ImageMagick',
          'inkscape' => 'Inkscape',
          'vips' => 'vips (libvips)',
          'tesseract' => 'Tesseract OCR',
          'tesseract-lang' => 'Tesseract 日本語学習データ',
          'waifu2x' => 'waifu2x-ncnn-vulkan',
          'ssl-certificates' => 'Google Fonts 用 SSL 証明書',
          'mecab' => 'MeCab (索引機能用)',
          'rouge' => 'Rouge (コードブロック言語推定用)',
          'mathjax' => '数式SVG化 (mathjax-full)',
          'kindlepreviewer' => 'Kindle Previewer 3 (kindlepreviewer・targets: kindle 用)'
        }
        keys.uniq.map { |key| label_map[key] || key }
      end

      def command_exists?(cmd)
        return false if cmd.nil? || cmd.strip.empty?

        candidate = cmd.strip
        return file_executable?(candidate) if candidate.include?(File::SEPARATOR) || candidate.include?('\\')

        pathext = windows_platform? ? ENV.fetch('PATHEXT', '').split(';').map(&:downcase) : ['']
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
          pathext.any? do |ext|
            extname = ext.empty? || candidate.downcase.end_with?(ext) ? candidate : "#{candidate}#{ext.downcase}"
            resolved = File.join(path, extname)
            file_executable?(resolved)
          end
        end
      end

      # コマンドが存在し、かつ実際に起動できるかを検証する。
      # presence チェック（command_exists?）は「ファイルが在り実行ビットが立つ」だけを見るため、
      # Homebrew cask のラッパーが削除済みアプリ本体を exec する等の「在るのに動かない」壊れ方を
      # 見抜けない（例: /opt/homebrew/bin/inkscape が欠落した Inkscape.app を指し exit 126）。
      # version_arg の実起動で終了ステータスまで確認し、壊れたラッパーを MISSING として扱う。
      def command_runnable?(cmd, version_arg: '--version')
        return false unless command_exists?(cmd)

        require 'open3'
        _out, _err, status = Open3.capture3(cmd, version_arg)
        status.success?
      rescue StandardError
        false
      end

      def rouge_gem_available?
        require 'rouge'
        true
      rescue LoadError
        false
      end

      # Vivliostyle が PDF レンダリングに使う headless Chrome のキャッシュを点検し、
      # 中断したダウンロード/展開で壊れた残骸があれば（--fix 時に）掃除する。
      # ビルドを Ctrl+C で中断すると不完全な Chrome が残り、起動失敗 →「PDFの生成に失敗」
      # （本文欠落）になるため、著者がキャッシュを手で消さずに済むよう doctor が面倒を見る。
      # 掃除後は次回ビルドで自動的に正しい Chrome が再取得される。
      def handle_vivliostyle_chrome(options)
        broken = broken_vivliostyle_chrome_entries
        if broken.empty?
          Common.log_info('Vivliostyle の Chrome キャッシュは正常です')
          return
        end

        if options[:fix]
          broken.each { |path| FileUtils.rm_rf(path) }
          Common.log_success(
            "不完全な Vivliostyle Chrome を削除しました（次回ビルド時に自動再取得されます・#{broken.size}件）"
          )
        else
          Common.log_warn(
            'Vivliostyle の Chrome が不完全です（ビルド中断などで破損）。`vs doctor --fix` で修復できます。'
          )
        end
      end

      # vivliostyle のブラウザキャッシュ内で「不完全な Chrome」のパス一覧を返す。
      # 中断時は (1) 展開途中の .zip が残り（成功時は削除される）、(2) バージョン
      # ディレクトリの Framework 本体が欠落する。健全な版は対象に含めない。
      def broken_vivliostyle_chrome_entries
        base = vivliostyle_browsers_cache_dir
        return [] unless Dir.exist?(base)

        entries = Dir.glob(File.join(base, '**', '*.zip'))
        Dir.glob(File.join(base, 'chrome', '*')).each do |version_dir|
          next unless File.directory?(version_dir)

          entries << version_dir unless chrome_framework_present?(version_dir)
        end
        entries.uniq
      end

      # vivliostyle が Chrome を保存するキャッシュディレクトリ（macOS）。
      def vivliostyle_browsers_cache_dir
        File.join(Dir.home, 'Library', 'Caches', 'vivliostyle', 'browsers')
      end

      # バージョンディレクトリ配下に Chrome の Framework 本体があるか（= 展開が完了しているか）。
      def chrome_framework_present?(version_dir)
        pattern = File.join(version_dir, '**', 'Frameworks', '*Framework.framework', 'Versions', '*', '*Framework')
        !Dir.glob(pattern).empty?
      end

      # mathjax-full（数式 SVG 化用の npm パッケージ）が解決できるか。
      # 数式は前処理で Node 上の MathJax を「SVG 生成器」として呼び出すため、
      # node の存在に加え mathjax-full がローカル/グローバルの node_modules にあるかを見る。
      # 未導入時は数式が SVG 化されず、Vivliostyle の MathJax 経路（PDF のみ）へ縮退する。
      def mathjax_full_available?
        return false unless command_exists?('node')

        local = File.join(Dir.pwd, 'node_modules', 'mathjax-full')
        return true if File.directory?(local)

        global = capture_command('npm root -g 2>/dev/null').to_s.strip
        !global.empty? && File.directory?(File.join(global, 'mathjax-full'))
      rescue StandardError
        false
      end

      def tesseract_language_available?(language)
        return false unless command_exists?('tesseract')

        output = capture_command('tesseract --list-langs 2>/dev/null')
        output.lines.map(&:strip).include?(language.to_s)
      rescue StandardError
        false
      end

      def waifu2x_available?
        os_family = detect_os_family(RbConfig::CONFIG['host_os'])
        paths = waifu2x_paths(os_family)

        candidates = [ENV.fetch('WAIFU2X_BIN', nil),
                      'waifu2x-ncnn-vulkan',
                      'waifu2x-ncnn-vulkan.exe']

        if paths
          %w[waifu2x-ncnn-vulkan waifu2x-ncnn-vulkan.exe].each do |name|
            candidates << File.join(paths[:bin], name)
            candidates << File.join(paths[:bundle], name)
          end
          candidates << paths[:binary]
        end

        candidates.compact.any? { |cmd| command_exists?(cmd) }
      end

      def windows_platform?
        RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/i
      end

      def detect_os_family(host_os)
        case host_os
        when /mswin|mingw|cygwin/i then :windows
        when /darwin/i then :macos
        when /linux/i then :linux
        else :unknown
        end
      end

      def install_waifu2x_macos!
        paths = waifu2x_paths(:macos)
        unless paths
          Common.log_warn('macOS 用のインストール先を決定できませんでした')
          return false
        end

        FileUtils.mkdir_p(paths[:bin])
        FileUtils.mkdir_p(paths[:bundle])

        release = fetch_waifu2x_release
        return false unless release

        asset = Array(release['assets']).find { |a| a['name'].to_s.include?('macos') }
        unless asset
          Common.log_warn('macOS 用 waifu2x アセットが見つかりませんでした')
          return false
        end

        Dir.mktmpdir('waifu2x-install') do |tmpdir|
          archive_path = File.join(tmpdir, asset['name'])
          return false unless download_asset(asset['browser_download_url'], archive_path)

          return false unless verify_asset_digest(asset['digest'], archive_path)

          extracted_dir = File.join(tmpdir, 'extracted')
          FileUtils.mkdir_p(extracted_dir)
          return false unless extract_archive(archive_path, extracted_dir)

          payload_root = detect_payload_root(extracted_dir)
          return false unless payload_root

          # 既存の waifu2x 一式を削除
          clean_waifu2x_bins(paths[:bin], paths[:bundle])
          FileUtils.rm_rf(paths[:bundle])
          FileUtils.mkdir_p(paths[:bundle])

          Dir.children(payload_root).each do |child|
            src = File.join(payload_root, child)
            dst = File.join(paths[:bundle], child)
            FileUtils.cp_r(src, dst, preserve: true, remove_destination: true)
          end

          binary_path = locate_waifu2x_binary(paths[:bundle], :macos)
          unless binary_path
            Common.log_warn('waifu2x 実行ファイルが見つかりませんでした')
            return false
          end

          FileUtils.chmod(0o755, binary_path)

          Common.log_always("✅ waifu2x を #{paths[:bundle]} に配置しました")
          Common.log_always("   実行ファイル: #{binary_path}")
          unless path_included?(paths[:bin])
            if ensure_zsh_path(paths[:bin])
              Common.log_always('ℹ️ ~/.zshrc に PATH を追記しました。新しいシェルで有効になります')
            else
              Common.log_always(path_hint_message(paths[:bin], :macos))
            end
          end
          yield(paths) if block_given?
          return true
        end
      rescue StandardError => e
        Common.log_warn("waifu2x 自動インストールで例外: #{e.class}: #{e.message}")
        false
      end

      def waifu2x_paths(os_family = :macos)
        return nil unless os_family == :macos

        base_dir = File.join(Dir.home, '.local')
        bin_dir = File.join(base_dir, 'bin')
        bundle_dir = File.join(bin_dir, 'waifu2x')
        binary_path = File.join(bundle_dir, 'waifu2x-ncnn-vulkan')
        { install: bundle_dir, bin: bin_dir, bundle: bundle_dir, binary: binary_path }
      end

      def fetch_waifu2x_release
        uri = URI.parse('https://api.github.com/repos/nihui/waifu2x-ncnn-vulkan/releases/tags/20250915')
        response = uri.open('User-Agent' => 'vivlio-starter')
        JSON.parse(response.read)
      rescue StandardError => e
        Common.log_warn("waifu2x リリース情報の取得に失敗しました: #{e.class}: #{e.message}")
        nil
      end

      def download_asset(url, destination)
        URI.parse(url).open('User-Agent' => 'vivlio-starter') do |data|
          File.open(destination, 'wb') { |f| IO.copy_stream(data, f) }
        end
        true
      rescue StandardError => e
        Common.log_warn("waifu2x アセットのダウンロードに失敗しました: #{e.class}: #{e.message}")
        false
      end

      def verify_asset_digest(digest_field, file_path)
        return true unless digest_field.to_s.start_with?('sha256:')

        expected = digest_field.split(':', 2).last
        actual = Digest::SHA256.file(file_path).hexdigest
        return true if actual.casecmp?(expected)

        Common.log_warn('ダウンロードした waifu2x アセットの SHA256 が一致しません')
        false
      end

      def extract_archive(archive_path, destination, os_family = :macos)
        if os_family == :windows
          extract_with_powershell(archive_path, destination)
        else
          extract_with_unzip(archive_path, destination)
        end
      end

      def extract_with_unzip(archive_path, destination)
        cmd = ['unzip', '-qq', archive_path, '-d', destination]
        system(*cmd)
      rescue Errno::ENOENT
        Common.log_warn('unzip コマンドが見つかりません。手動で解凍してください。')
        false
      end

      def extract_with_powershell(archive_path, destination)
        ps = %(powershell -NoLogo -NoProfile -Command "Expand-Archive -Force -LiteralPath '#{archive_path.gsub("'",
                                                                                                               "''")}' -DestinationPath '#{destination.gsub(
                                                                                                                 "'", "''"
                                                                                                               )}'")
        system(ps)
      rescue Errno::ENOENT
        Common.log_warn('PowerShell が見つかりません。手動で解凍してください。')
        false
      end

      def detect_payload_root(extracted_dir)
        entries = Dir.children(extracted_dir)
        return extracted_dir if entries.empty?

        first = File.join(extracted_dir, entries.first)
        File.directory?(first) ? first : extracted_dir
      rescue StandardError
        nil
      end

      def locate_waifu2x_binary(install_root, os_family)
        pattern = os_family == :windows ? 'waifu2x-ncnn-vulkan.exe' : 'waifu2x-ncnn-vulkan'
        Dir.glob(File.join(install_root, '**', pattern)).find { |path| File.file?(path) }
      end

      def waifu2x_present_at?(install_root, os_family)
        return false unless install_root && File.directory?(install_root)

        binary = locate_waifu2x_binary(install_root, os_family)
        models = Dir.glob(File.join(install_root, 'models-*')).any? { |path| File.directory?(path) }
        binary && models
      end

      def clean_waifu2x_bins(bin_dir, bundle_dir)
        targets = []
        targets.concat(Dir.glob(File.join(bin_dir, 'waifu2x*')))
        targets << File.join(bin_dir, 'waifu2x-ncnn-vulkan.cmd')
        targets << File.join(bin_dir, 'waifu2x-ncnn-vulkan.exe')
        targets << bundle_dir
        targets.uniq.each do |path|
          next unless path.start_with?(bin_dir)

          FileUtils.rm_rf(path)
        end
      end

      def ensure_zsh_path(bin_dir)
        zshrc = File.join(Dir.home, '.zshrc')
        export_line = %(export PATH="#{bin_dir}:$PATH")

        contents = File.exist?(zshrc) ? File.read(zshrc) : ''
        return true if contents.include?(bin_dir)

        FileUtils.mkdir_p(File.dirname(zshrc)) unless File.directory?(File.dirname(zshrc))
        File.open(zshrc, 'a', encoding: 'utf-8') do |file|
          file.puts "\n# Added by vs doctor"
          file.puts export_line
        end
        true
      rescue StandardError => e
        Common.log_warn("PATH 追記に失敗しました: #{e.class}: #{e.message}")
        false
      end

      def file_executable?(path)
        return false unless File.exist?(path)

        windows_platform? || File.executable?(path)
      end

      def path_included?(dir)
        normalized = File.expand_path(dir)
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |entry|
          next if entry.nil? || entry.empty?

          File.expand_path(entry) == normalized
        end
      end

      def path_hint_message(bin_dir, os_family)
        display_path = case os_family
                       when :windows then '%LOCALAPPDATA%\\vs\\bin'
                       when :macos, :linux then '$HOME/.local/bin'
                       else bin_dir
                       end
        "ℹ️ PATH に #{display_path} を追加すると waifu2x-ncnn-vulkan が利用可能になります"
      end
    end
  end
end
