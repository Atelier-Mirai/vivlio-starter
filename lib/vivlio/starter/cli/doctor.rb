# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: DoctorCommands
      # ------------------------------------------------------------------------------
      # 必要な外部ツール(Xcode Command Line Tools, qpdf, pdfinfo, gs, ImageMagick 他)の存在チェックと、
      # macOS + Homebrew 環境での自動インストール支援を行うコマンド。
      # ==============================================================================
      module DoctorCommands
        module_function

        DOCTOR_DESC = {
          short: '必要ツール(Xcode Command Line Tools, qpdf, pdfinfo, gs, ImageMagick)の診断とセットアップを行います',
          long: <<~DESC
            環境診断を行い、以下の外部コマンドの存在をチェックします:
              - Xcode Command Line Tools (macOS)
              - qpdf
              - pdfinfo (poppler)
              - node
              - vivliostyle
              - gs
              - imagemagick

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

        def included(base)
          base.class_eval do
            desc 'doctor', DOCTOR_DESC[:short]
            long_desc DOCTOR_DESC[:long]
            method_option :fix, type: :boolean, default: false, desc: '不足ツールを自動インストール (macOS Homebrew)'
            method_option :yes, aliases: '-y', type: :boolean, default: false, desc: '確認を省略して実行'
            def doctor
              ENV['VERBOSE'] = '1' if options[:verbose]

              missing = []
              os = RbConfig::CONFIG['host_os']
              is_macos = os =~ /darwin/i

              # まず macOS の場合に Xcode Command Line Tools をチェック
              if is_macos
                clt_ok = system('xcode-select -p >/dev/null 2>&1')
                if clt_ok
                  Common.echo_always('✅ Xcode Command Line Tools: OK')
                else
                  Common.echo_always('❌ Xcode Command Line Tools: 見つかりません')
                  missing << 'xcode-command-line-tools'
                end
              end

              # コマンド存在チェック定義
              checks = {
                'node' => 'node',
                'vivliostyle' => 'vivliostyle',
                'qpdf' => 'qpdf',
                'pdfinfo' => 'pdfinfo',
                'gs' => 'gs', # Ghostscript
                'imagemagick' => nil # 特殊判定（convert か magick のどちらか）
              }

              Common.echo_always('🔎 環境診断を開始します…')
              checks.each do |label, cmd|
                ok = false
                if label == 'imagemagick'
                  ok = system('which convert >/dev/null 2>&1') || system('which magick >/dev/null 2>&1')
                elsif cmd
                  ok = system("which #{cmd} >/dev/null 2>&1")
                end
                if ok
                  Common.echo_always("✅ #{label}: OK")
                else
                  Common.echo_always("❌ #{label}: 見つかりません")
                  missing << label
                end
              end

              if is_macos
                if ssl_certificate_configured?
                  Common.echo_always('✅ Google Fonts 用 SSL 証明書: OK')
                else
                  Common.echo_always('❌ Google Fonts 用 SSL 証明書: 未設定 (Google Fonts のダウンロードに必要)')
                  missing << 'ssl-certificates'
                end
              end

              if missing.empty?
                Common.echo_always('🎉 すべての必要ツールが見つかりました')
                return
              end

              Common.echo_always("不足しているツール: #{describe_missing(missing).join(', ')}")

              unless options[:fix]
                Common.echo_always('ヒント: macOS の場合は `vs doctor --fix` で自動インストールを試行できます')
                if missing.include?('xcode-command-line-tools')
                  Common.echo_always('  Xcode Command Line Tools は手動でも `xcode-select --install` で導入できます')
                end
                return
              end

              # --fix: 自動インストール試行
              unless is_macos
                Common.echo_always('自動インストールは macOS(Homebrew) のみ対応です。手動でインストールしてください。')
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
                  Common.echo_always('Xcode Command Line Tools のインストーラを起動します…')
                  system('xcode-select --install >/dev/null 2>&1 || true')
                  # ポーリングで最大 5 分間待機（5 秒間隔）
                  waited = 0
                  until system('xcode-select -p >/dev/null 2>&1') || waited >= 300
                    sleep 5
                    waited += 5
                  end
                  if system('xcode-select -p >/dev/null 2>&1')
                    Common.echo_always('✅ Xcode Command Line Tools が確認できました')
                    missing.delete('xcode-command-line-tools')
                  else
                    Common.echo_always('⚠️ インストールの確認ができませんでした。インストーラ完了後に再実行してください。')
                  end
                else
                  Common.echo_always('Xcode Command Line Tools の自動インストールをスキップします。必要に応じて `xcode-select --install` を実行してください。')
                end
              end

              unless system('which brew >/dev/null 2>&1')
                Common.echo_always('Homebrew が見つかりません。自動インストールを試みます。')
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
                  Common.echo_always('Homebrew をインストールしないため、自動インストール処理を中止します。手動で https://brew.sh/ を参照してください。')
                  return
                end
                unless system('which brew >/dev/null 2>&1')
                  Common.echo_always('Homebrew コマンドが見つかりませんでした。シェルの再起動や PATH 設定を確認してください。')
                  return
                end
              end

              Common.echo_always('🛠 Homebrew による不足ツールのインストールを実行します…')
              begin
                # Node.js（node@20 を優先）
                if missing.include?('node')
                  Common.echo_always('node をインストールします（node@20 優先）…')
                  ok = system('brew install node@20')
                  ok ||= system('brew install node')
                  Common.echo_always('node の Homebrew インストールに失敗しました。手動インストールをご検討ください。') unless ok
                end

                # qpdf / pdfinfo(poppler)
                system('brew install qpdf') if missing.include?('qpdf')
                system('brew install poppler') if missing.include?('pdfinfo')

                # Ghostscript
                system('brew install ghostscript') if missing.include?('gs')

                # ImageMagick
                system('brew install imagemagick') if missing.include?('imagemagick')

                if missing.include?('ssl-certificates')
                  install_ssl_certificates!
                end
              rescue StandardError => e
                Common.log_warn("brew 実行でエラー: #{e}")
              end

              # Vivliostyle CLI（npm -g）
              begin
                if missing.include?('vivliostyle')
                  if system('which npm >/dev/null 2>&1')
                    Common.echo_always('Vivliostyle CLI(@vivliostyle/cli) をグローバルインストールします…')
                    system('npm install -g @vivliostyle/cli')
                  else
                    Common.echo_always('npm が見つかりません。node のインストール後に `npm install -g @vivliostyle/cli` を実行してください。')
                  end
                end
              rescue StandardError => e
                Common.log_warn("npm 実行でエラー: #{e}")
              end

              # 再診断
              Common.echo_always('🔁 インストール後の再診断…')
              still_missing = []
              checks.each do |label, cmd|
                ok = false
                if label == 'imagemagick'
                  ok = system('which convert >/dev/null 2>&1') || system('which magick >/dev/null 2>&1')
                elsif cmd
                  ok = system("which #{cmd} >/dev/null 2>&1")
                end
                still_missing << label unless ok
              end
              if is_macos && !ssl_certificate_configured?
                still_missing << 'ssl-certificates'
              end
              if still_missing.empty?
                Common.echo_always('✅ すべてのツールがインストールされました')
              else
                Common.echo_always("❗ まだ見つからないツールがあります: #{describe_missing(still_missing).join(', ')}。手動でのセットアップをご確認ください。")
              end
            end
          end
        end
      end
    end
  end
end

module Vivlio
  module Starter
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
          Common.echo_always('Google Fonts 用に ca-certificates / openssl@3 を設定します…')
          system('brew update >/dev/null 2>&1')
          system('brew install openssl@3') unless system('brew list --versions openssl@3 >/dev/null 2>&1')
          system('brew reinstall ca-certificates')

          openssl_prefix = capture_command('brew --prefix openssl@3').strip
          openssl_prefix = File.join(capture_command('brew --prefix').strip, 'opt', 'openssl@3') if openssl_prefix.empty?

          cert_file = File.join(openssl_prefix, 'etc', 'openssl@3', 'cert.pem')
          cert_dir  = File.join(openssl_prefix, 'etc', 'openssl@3', 'certs')

          if File.file?(cert_file)
            ENV['SSL_CERT_FILE'] = cert_file
            ENV['SSL_CERT_DIR'] = cert_dir if Dir.exist?(cert_dir)

            persist_env('SSL_CERT_FILE', cert_file)
            persist_env('SSL_CERT_DIR', cert_dir) if Dir.exist?(cert_dir)

            Common.echo_always("✅ SSL_CERT_FILE を #{cert_file} に設定しました")
            Common.echo_always("✅ SSL_CERT_DIR を #{cert_dir} に設定しました") if Dir.exist?(cert_dir)
          else
            Common.echo_always("⚠️ 証明書ファイルが見つかりませんでした。#{openssl_prefix} に openssl@3 が存在するか確認してください。")
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

        def describe_missing(keys)
          return [] unless keys

          label_map = {
            'xcode-command-line-tools' => 'Xcode Command Line Tools',
            'node' => 'node',
            'vivliostyle' => 'Vivliostyle CLI',
            'qpdf' => 'qpdf',
            'pdfinfo' => 'pdfinfo (poppler)',
            'gs' => 'Ghostscript',
            'imagemagick' => 'ImageMagick',
            'ssl-certificates' => 'Google Fonts 用 SSL 証明書'
          }
          keys.uniq.map { |key| label_map[key] || key }
        end
      end
    end
  end
end
