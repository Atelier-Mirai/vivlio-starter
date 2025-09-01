# frozen_string_literal: true

require 'rbconfig'

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
        extend self
        def included(base)
          base.class_eval do
            desc 'doctor', '必要ツール(Xcode Command Line Tools, qpdf, pdfinfo, gs, ImageMagick)の診断とセットアップを行います'
            long_desc <<~DESC
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
                'node'        => 'node',
                'vivliostyle' => 'vivliostyle',
                'qpdf'        => 'qpdf',
                'pdfinfo'     => 'pdfinfo',
                'gs'          => 'gs',               # Ghostscript
                'imagemagick' => nil                 # 特殊判定（convert か magick のどちらか）
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

              if missing.empty?
                Common.echo_always('🎉 すべての必要ツールが見つかりました')
                return
              end

              Common.echo_always("不足しているツール: #{missing.join(', ')}")

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
                unless proceed
                  if $stdin.tty?
                    $stdout.print('Xcode Command Line Tools をインストールしますか？ [y/N]: ')
                    ans = $stdin.gets
                    proceed = ans && ans.strip.downcase == 'y'
                  end
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
                unless proceed
                  if $stdin.tty?
                    $stdout.print('Homebrew をインストールしますか？ [y/N]: ')
                    ans = $stdin.gets
                    proceed = ans && ans.strip.downcase == 'y'
                  end
                end
                if proceed
                  begin
                    # 公式インストーラ実行（要ネットワーク）
                    cmd = %q{/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"}
                    system(cmd)
                  rescue => e
                    Common.log_warn("Homebrew のインストールでエラー: #{e}")
                  end
                  # PATH 調整（Apple Silicon / Intel を想定）
                  brew_bins = ['/opt/homebrew/bin', '/usr/local/bin']
                  brew_bin = brew_bins.find { |p| File.exist?(File.join(p, 'brew')) }
                  ENV['PATH'] = [brew_bin, ENV['PATH']].compact.join(':') if brew_bin
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
                  unless ok
                    Common.echo_always('node の Homebrew インストールに失敗しました。手動インストールをご検討ください。')
                  end
                end

                # qpdf / pdfinfo(poppler)
                system('brew install qpdf') if missing.include?('qpdf')
                system('brew install poppler') if missing.include?('pdfinfo')

                # Ghostscript
                system('brew install ghostscript') if missing.include?('gs')

                # ImageMagick
                if missing.include?('imagemagick')
                  system('brew install imagemagick')
                end
              rescue => e
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
              rescue => e
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
              if still_missing.empty?
                Common.echo_always('✅ すべてのツールがインストールされました')
              else
                Common.echo_always("❗ まだ見つからないツールがあります: #{still_missing.join(', ')}。手動でのセットアップをご確認ください。")
              end
            end
          end
        end
      end
    end
  end
end
