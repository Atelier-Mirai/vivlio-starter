# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/spinner.rb
# ================================================================
# 責務:
#   時間のかかる処理の進行を TTY 上で示す簡易スピナー。
#   表示条件を満たさないときは何もせず、ブロックをそのまま実行する。
#
# なぜ必要か:
#   `vs build` は数十秒〜数分かかるが、既定ログレベルではステップ間の出力が
#   ないため「止まっている」のと区別が付かない。
#
# なぜ自作か:
#   ora / cli-spinners は Node の資産で Ruby CLI には持ち込めず、gem を足す
#   ほどの規模でもない（スレッド＋`\r` 書き換えで済む）。
#
# 表示条件（すべて満たすときのみ）:
#   - $stdout が TTY（リダイレクト・パイプ・CI では出さない）
#   - ログレベルが既定（warn）以下——`--log` 指定時は逐次ログが流れるため
#     不要であり、行の書き換えが互いに干渉する
#   - VS_DEBUG が未設定
#   - VS_NO_SPINNER が未設定（エスケープハッチ）
#
# 仕様: command-feedback-spinner-spec.md §2
# ================================================================

module VivlioStarter
  module CLI
    # TTY 向けの簡易スピナー
    class Spinner
      FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
      INTERVAL = 0.08
      # 行頭へ戻って行末まで消す（描画済みの残骸を残さない）
      CLEAR_LINE = "\r\e[K"

      class << self
        # 現在描画中のスピナー。ログ出力側が行を消すために参照する
        attr_accessor :active

        # スピナーを回しながらブロックを実行する
        def while(label, output: $stdout, &) = new(label, output: output).run(&)

        # ログを出す直前に呼ぶ。消さないとスピナーの残骸とログが同じ行に重なる
        def clear_active_line = active&.clear_line
      end

      def initialize(label, output: $stdout)
        @label = label
        @output = output
        # 描画スレッドとログ出力スレッドから同じ行を触るため排他する
        @mutex = Mutex.new
        @drawn = false
      end

      def run
        @enabled = enabled?
        return yield unless @enabled

        start
        yield
      ensure
        # 例外時も必ず行を消す（残骸で 🔴 メッセージを汚さない）
        stop
      end

      # 描画済みの行を消す。ログ出力の割り込み時にも呼ばれる
      def clear_line
        @mutex.synchronize do
          return unless @drawn

          @output.print(CLEAR_LINE)
          @output.flush
          @drawn = false
        end
      end

      private

      # 出力先が差し替えられているスレッド（並列ビルドの子枝）では回さない。
      # スピナーは @output へ直に書くので Common.emit の差し替えを素通りしてしまい、
      # 2 本のスピナーが同じ TTY を奪い合う（build-target-parallelization-spec.md §3.4）。
      def enabled?
        Thread.current[Common::EMIT_SINK_KEY].nil? &&
          @output.respond_to?(:tty?) && @output.tty? &&
          Common.current_log_level <= Common::DEFAULT_LOG_LEVEL &&
          ENV['VS_DEBUG'] != '1' &&
          ENV['VS_NO_SPINNER'].to_s.empty?
      end

      def start
        self.class.active = self
        @stopping = false
        @thread = Thread.new do
          FRAMES.cycle do |frame|
            break if @stopping

            draw(frame)
            sleep(INTERVAL)
          end
        end
      end

      def stop
        return unless @enabled

        @stopping = true
        @thread&.join
        clear_line
        self.class.active = nil
      end

      def draw(frame)
        @mutex.synchronize do
          @output.print("#{CLEAR_LINE}#{frame} #{@label}")
          @output.flush
          @drawn = true
        end
      end
    end
  end
end
