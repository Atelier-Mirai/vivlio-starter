# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/doctor.rb
# ================================================================
# 責務:
#   Vivlio Starter の動作に必要な外部ツールの診断と自動インストールを行う。
#
# 診断対象ツール:
#   - Xcode Command Line Tools (macOS): ビルドツールチェーン
#   - node: JavaScript ランタイム（Vivliostyle CLI の依存）
#   - vivliostyle: PDF 生成エンジン
#   - textlint: 文章校正ツール
#   - qpdf: PDF 分割・結合・ページ操作
#   - pdfinfo / pdftoppm (poppler): PDF メタデータ取得・ページ画像化
#   - gs (Ghostscript): PDF 圧縮
#   - img2pdf: JPEG から PDF への再結合
#   - imagemagick: 画像変換・リサイズ
#   - inkscape: SVG編集・変換（カバー生成用）
#   - waifu2x-ncnn-vulkan: AI 画像拡大（オプション）
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

module VivlioStarter
  module CLI
    # 環境診断・ツールインストールコマンド
    module DoctorCommands
      module_function

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
            - gs
            - imagemagick
            - inkscape
            - waifu2x

          役割の補足:
            - 圧縮は Ghostscript(pdfwrite) を使用します
            - qpdf は分割/結合・ページ抽出などの PDF 操作用に使用します（圧縮用途ではありません）

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
          'inkscape' => 'inkscape',
          'vips' => 'vips',
          'tesseract' => 'tesseract',
          'tesseract-lang' => nil,
          'waifu2x' => nil,
          'playwright' => nil, # バックリンク重複排除用（npm パッケージ）
          'chromium' => nil,   # Playwright 用ヘッドレスブラウザ
          'mecab' => 'mecab', # 索引機能の読み自動推測用
          'rouge' => nil # コードブロック言語推定用
        }

        checks.each do |label, cmd|
          ok = case label
               when 'imagemagick'
                 command_exists?('convert') || command_exists?('magick')
               when 'inkscape'
                 command_exists?('inkscape')
               when 'tesseract-lang'
                 tesseract_language_available?('jpn')
               when 'waifu2x'
                 waifu2x_available?
               when 'rouge'
                 rouge_gem_available?
               when 'playwright'
                 playwright_npm_available?
               when 'chromium'
                 chromium_available?
               else
                 command_exists?(cmd)
               end

          if ok
            Common.log_always("✅ #{label}: OK")
          else
            Common.log_error("#{label}: 見つかりません")
            missing << label
          end
        end

        if is_macos
          if ssl_certificate_configured?
            Common.log_always('✅ Google Fonts 用 SSL 証明書: OK')
          else
            Common.log_error('Google Fonts 用 SSL 証明書: 未設定 (Google Fonts のダウンロードに必要)')
            missing << 'ssl-certificates'
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
          copy_textlint_assets_from_scaffold! if options[:fix]
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

          # Inkscape
          system('brew install inkscape') if missing.include?('inkscape')

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

          # Playwright npm パッケージ（グローバルインストール）
          if missing.include?('playwright')
            if system('which npm >/dev/null 2>&1')
              Common.log_always('Playwright（バックリンク重複排除用）をインストールします…')
              system('npm install --loglevel=error -g playwright')
            else
              Common.log_always('npm が見つかりません。node のインストール後に `npm install -g playwright` を実行してください。')
            end
          end

          # Chromium ブラウザ
          if missing.include?('chromium')
            Common.log_always('Chromium（Playwright 用ブラウザ）をインストールします…')
            installed_any = false

            if File.exist?('node_modules/playwright/cli.js')
              system('node node_modules/playwright/cli.js install chromium')
              installed_any = true
            end

            global_root = begin
              `npm root -g 2>/dev/null`.strip
            rescue StandardError
              ''
            end
            has_global_playwright = !global_root.empty? && File.exist?(File.join(global_root, 'playwright', 'package.json'))

            if has_global_playwright || (!installed_any && system('which npx >/dev/null 2>&1'))
              system('npx playwright install chromium')
              installed_any = true
            end

            unless installed_any
              Common.log_always('npx が見つかりません。Playwright インストール後に `npx playwright install chromium` を実行してください。')
            end
          end

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
              installed = system("npm install --loglevel=error -g #{packages}")
              copy_textlint_assets_from_scaffold! if installed
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
               when 'inkscape'
                 command_exists?('inkscape')
               when 'tesseract-lang'
                 tesseract_language_available?('jpn')
               when 'waifu2x'
                 waifu2x_available? || (waifu2x_install_root && waifu2x_present_at?(waifu2x_install_root, os_family))
               when 'rouge'
                 rouge_gem_available?
               when 'playwright'
                 playwright_npm_available?
               when 'chromium'
                 chromium_available?
               else
                 command_exists?(cmd)
               end
          still_missing << label unless ok
        end
        still_missing << 'ssl-certificates' if is_macos && !ssl_certificate_configured?
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

      def copy_textlint_assets_from_scaffold!
        gem_root = File.expand_path('../../..', __dir__)
        scaffold_root = File.join(gem_root, 'lib', 'project_scaffold')
        target_config_dir = File.join(Dir.pwd, 'config')

        FileUtils.mkdir_p(target_config_dir)

        copy_textlint_config(scaffold_root, target_config_dir)
        copy_textlint_allowlist(scaffold_root, target_config_dir)
        copy_textlint_prh(scaffold_root, target_config_dir)
        copy_textlint_dictionaries(scaffold_root, target_config_dir)
      rescue StandardError => e
        Common.log_warn("textlint 設定ファイルのコピーに失敗しました: #{e.class}: #{e.message}")
      end

      def copy_textlint_config(scaffold_root, target_config_dir)
        source_config = File.join(scaffold_root, '.textlintrc.yml')
        return unless File.file?(source_config)

        dest_config = File.join(target_config_dir, '.textlintrc.yml')
        if File.exist?(dest_config)
          Common.log_always('ℹ️ config/.textlintrc.yml は既に存在するためコピーをスキップしました。')
        else
          FileUtils.cp(source_config, dest_config)
          Common.log_always('✅ config/.textlintrc.yml を配置しました。')
        end
      end

      def copy_textlint_allowlist(scaffold_root, target_config_dir)
        source_allowlist = File.join(scaffold_root, 'textlint_allowlist.yml')
        return unless File.file?(source_allowlist)

        dest_allowlist = File.join(target_config_dir, 'textlint_allowlist.yml')
        if File.exist?(dest_allowlist)
          Common.log_always('ℹ️ config/textlint_allowlist.yml は既に存在するためコピーをスキップしました。')
        else
          FileUtils.cp(source_allowlist, dest_allowlist)
          Common.log_always('✅ config/textlint_allowlist.yml を配置しました。')
        end
      end

      def copy_textlint_prh(scaffold_root, target_config_dir)
        source_prh = File.join(scaffold_root, 'textlint_prh.yml')
        return unless File.file?(source_prh)

        dest_prh = File.join(target_config_dir, 'textlint_prh.yml')
        if File.exist?(dest_prh)
          Common.log_always('ℹ️ config/textlint_prh.yml は既に存在するためコピーをスキップしました。')
        else
          FileUtils.cp(source_prh, dest_prh)
          Common.log_always('✅ config/textlint_prh.yml を配置しました。')
        end
      end

      def copy_textlint_dictionaries(scaffold_root, target_config_dir)
        source_dir = File.join(scaffold_root, 'textlint_dictionaries')
        return unless Dir.exist?(source_dir)

        dest_dir = File.join(target_config_dir, 'textlint_dictionaries')
        FileUtils.mkdir_p(dest_dir)

        copied = false
        Dir.children(source_dir).each do |entry|
          src = File.join(source_dir, entry)
          dst = File.join(dest_dir, entry)
          next if File.exist?(dst)

          if File.directory?(src)
            FileUtils.cp_r(src, dst)
          else
            FileUtils.cp(src, dst)
          end
          copied = true
        end

        if copied
          Common.log_always('✅ config/textlint_dictionaries/ を更新しました。')
        else
          Common.log_always('ℹ️ config/textlint_dictionaries/ は既に最新です。')
        end
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
          'playwright' => 'Playwright (バックリンク重複排除用)',
          'chromium' => 'Chromium (Playwright 用ブラウザ)',
          'rouge' => 'Rouge (コードブロック言語推定用)'
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

      def rouge_gem_available?
        require 'rouge'
        true
      rescue LoadError
        false
      end

      def tesseract_language_available?(language)
        return false unless command_exists?('tesseract')

        output = capture_command('tesseract --list-langs 2>/dev/null')
        output.lines.map(&:strip).include?(language.to_s)
      rescue StandardError
        false
      end

      def playwright_npm_available?
        # ローカル node_modules を優先確認
        return true if File.exist?(File.join('node_modules', 'playwright', 'package.json'))

        # グローバルインストールを確認
        global_root = `npm root -g 2>/dev/null`.strip
        return false if global_root.empty?

        File.exist?(File.join(global_root, 'playwright', 'package.json'))
      rescue StandardError
        false
      end

      def chromium_available?
        return false unless playwright_npm_available?

        chromium_path = `node -e "try { const { chromium } = require('playwright'); console.log(chromium.executablePath()); } catch(e) {}" 2>/dev/null`.strip
        return true if !chromium_path.empty? && File.exist?(chromium_path)

        # グローバルの playwright から検出
        global_root = `npm root -g 2>/dev/null`.strip
        return false if global_root.empty?

        chromium_path = `NODE_PATH=#{global_root} node -e "try { const { chromium } = require('playwright'); console.log(chromium.executablePath()); } catch(e) {}" 2>/dev/null`.strip
        !chromium_path.empty? && File.exist?(chromium_path)
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
