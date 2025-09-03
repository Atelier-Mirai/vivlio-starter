# frozen_string_literal: true

require 'fileutils'
module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: renumber（章番号の付け直しユーティリティ）
      # ------------------------------------------------
      # - 目的: 全章の連番付け直し、または特定章の番号変更（rename の別名）
      # - 提供コマンド: renumber
      # - 補足: 付録(91..97)は appendix-letter を自動調整
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module RenumberCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'renumber [OLD NEW]', 'rename の別名（単体変更 or 一括連番）'
            long_desc <<~DESC
              このコマンドは rename の完全な別名です。
              ・引数あり: 章のスラッグ/番号の単体変更（旧: rename と同じ）
              ・引数なし: 一括連番（旧: renumber の機能）

              例:
                vs renumber            # 一括連番（--chapter-step/-S 使用可）
                vs renumber 17 16      # 単体番号変更
            DESC
            # rename と同じオプションをそのまま転送（Thor のヘルプ表示互換のため定義）
            method_option :dry_run, type: :boolean, aliases: '-n', desc: '変更予定のみ表示（実行しない）'
            method_option :force,   type: :boolean, aliases: %w[-f -y], desc: '確認なしで変更を実行'
            method_option :chapter_step, type: :numeric, aliases: '-S', desc: '章番号の刻み幅（rename と同じ）'
            method_option :step,         type: :numeric, desc: '[互換] 章番号の刻み幅（rename と同じ）'
            # ================================================================
            # Command: renumber（章番号の付け直し/変更）
            # ------------------------------------------------
            # - 概要: 引数なしで全体の連番を再構築。OLD NEW 指定時は特定章の番号変更（rename を呼び出し）
            # - 入力: なし、または OLD NEW
            # - オプション: --dry-run (-n), --force (-f, -y), --verbose (-v)
            # ================================================================
            def renumber(old_arg = nil, new_arg = nil)
              # 完全委譲
              invoke :rename, [old_arg, new_arg].compact, options
            end
          end
        end
      end
    end
  end
end
