# frozen_string_literal: true

# ================================================================
# Test: contract/warning_delivery_test.rb
# ================================================================
# CLI 警告到達性テスト — cli-warning-delivery-spec.md §6
#
# 検証内容:
#   WD-01: `bin/vs` 経由で無効入力のエラーメッセージが stderr へ届く
#   WD-02: VS_DEBUG の有無で出力が変わらない
#   WD-03: 通常実行で Ruby 由来の警告が stderr へ漏れない（-W0 は残す）
#   WD-04: -W0 が Kernel#warn を捨て $stderr.puts は通す（機構の実測）
#   WD-05: lib/ に Kernel#warn が残っていない（再発防止）
#
# **なぜ子プロセスなのか。**
# `bin/vs` は起動時に `RUBYOPT=-W0` を付けて自身を再実行しており、`-W0` は
# `Kernel#warn` の出力を丸ごと捨てる。同一プロセスで `CLI.start` を呼ぶ既存の
# 契約テスト（cli_contract_test.rb）はこの再実行を経由しないため、警告が
# 握り潰されていても素通りする——実際 2026-08-18 の発覚まで全テストが通っていた。
# ここだけは本物の `bin/vs` を起動して、著者が見る出力そのものを検査する。
# ================================================================

require 'test_helper'
require 'open3'

module VivlioStarter
  module CLI
    class WarningDeliveryTest < Minitest::Test
      REPO_ROOT = File.expand_path('../../..', __dir__)
      BIN_VS    = File.join(REPO_ROOT, 'bin', 'vs')
      LIB_DIR   = File.join(REPO_ROOT, 'lib')

      # 本物の `bin/vs` を子プロセスで起動する（再実行を含めて素の状態で通す）。
      # VS_DEBUG / VS_WARNINGS / VS_NO_REEXEC は明示的に空にする——親の環境に
      # 残っていると再実行がスキップされ、検証したい経路を通らなくなる。
      def run_vs(*args, env: {})
        base = { 'VS_DEBUG' => nil, 'VS_WARNINGS' => nil, 'VS_NO_REEXEC' => nil, 'RUBYOPT' => nil }
        Open3.capture3(base.merge(env), RbConfig.ruby, "-I#{LIB_DIR}", BIN_VS, *args, chdir: REPO_ROOT)
      end

      # WD-01: Samovar の解析エラーは「何が読めなかったか」が唯一の手がかりなので、
      # 著者へ必ず届かねばならない。-W0 に捨てられていた頃は stderr が空だった。
      def test_should_deliver_invalid_input_message_to_stderr
        _out, err, status = run_vs('--bogus-option')

        assert_equal 1, status.exitstatus, '無効入力は非 0 で終わる'
        assert_includes err, '--bogus-option', '読めなかったトークンを著者へ知らせるべき'
      end

      # WD-02: VS_DEBUG=1 は再実行をスキップするため、-W0 に依存した実装では
      # 「デバッグ時だけ症状が消える」形になる。両者で同じものが出ることを見る。
      def test_should_deliver_the_same_message_with_and_without_debug
        _out, plain,    = run_vs('--bogus-option')
        _out, debugging = run_vs('--bogus-option', env: { 'VS_DEBUG' => '1' })

        assert_includes plain,     '--bogus-option'
        assert_includes debugging, '--bogus-option'
      end

      # WD-03: -W0 は残す方針（gem 更新で処理系の警告が復活しうる）。
      # 正常系で著者に無関係な警告が漏れていないことを確かめる。
      def test_should_not_leak_interpreter_warnings_on_normal_run
        _out, err, status = run_vs('--version')

        assert_equal 0, status.exitstatus
        assert_empty err.strip, "通常実行の stderr は空であるべき:\n#{err}"
      end

      # WD-04: 問題の機構そのものを実測で残す。この 2 行が同じ振る舞いになったら
      # （＝Ruby 側が -W0 の扱いを変えたら）本仕様の前提が崩れたことを意味する。
      def test_should_confirm_dash_w0_swallows_kernel_warn_but_not_stderr_puts
        _out, swallowed, = Open3.capture3(RbConfig.ruby, '-W0', '-e', 'warn "きえる"')
        _out, delivered, = Open3.capture3(RbConfig.ruby, '-W0', '-e', '$stderr.puts "とどく"')

        assert_empty swallowed.strip, '-W0 は Kernel#warn を捨てる'
        assert_includes delivered, 'とどく', '-W0 でも $stderr.puts は通る'
      end

      # WD-05: 再発防止。lib/ で `Kernel#warn` を呼んだ瞬間、その出力は
      # `vs` 経由で消える。用途に応じて $stderr.puts か Common.log_warn を使う。
      def test_should_not_call_kernel_warn_anywhere_in_lib
        offenders = Dir.glob(File.join(LIB_DIR, '**', '*.rb')).select do |path|
          File.foreach(path).any? { |line| line.match?(/^\s*warn[ (]/) }
        end

        assert_empty offenders.map { it.delete_prefix("#{REPO_ROOT}/") },
                     'Kernel#warn は bin/vs の -W0 に捨てられる。' \
                     '$stderr.puts（最後の砦）か Common.log_warn（通常の警告）を使うこと'
      end
    end
  end
end
