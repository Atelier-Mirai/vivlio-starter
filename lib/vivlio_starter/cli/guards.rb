# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/guards.rb
# ================================================================
# 責務:
#   各コマンドの実行前に「成立するための最低限の前提条件」を検証し、
#   違反時はスタックトレースではなく行動可能なメッセージで早期に停止する。
#
# 設計（docs/specs/precondition-guard-spec.md）:
#   - Guard 層: コマンド冒頭で致命的な前提だけを高速検証（違反で GuardError）
#   - Check 層: 単一責務の検証オブジェクト群（preflight / doctor からも再利用可能）
#
# 依存:
#   - Common: ログ出力・パス定数
#   - TokenResolver / Build::CatalogLoader: カタログ解析
# ================================================================

require_relative 'token_resolver'
require_relative 'build/catalog_loader'
require_relative 'guards/base_check'
require_relative 'guards/relaxed_check'
require_relative 'guards/project_root_check'
require_relative 'guards/catalog_file_check'
require_relative 'guards/catalog_entries_check'
require_relative 'guards/orphan_file_check'
require_relative 'guards/contents_dir_check'
require_relative 'guards/node_check'
require_relative 'guards/images_dir_check'
require_relative 'guards/image_filename_check'
require_relative 'guards/code_fence_check'
require_relative 'guards/pdf_artifact_check'
require_relative 'guards/config_validity_check'

module VivlioStarter
  module CLI
    module Guards
      # 前提条件違反（:error）が1件以上ある場合に送出される。
      # 各コマンドの call で捕捉し、メッセージ表示の上で終了コード 1 を返す。
      class GuardError < StandardError; end

      # コマンド冒頭で Check 群をまとめて実行する入口
      module Guard
        module_function

        # 全 Check を実行し、違反を 🔴（error）/ 🟡（warn）でログ出力する。
        # @param checks [Array<BaseCheck>] 実行する Check 群
        # @raise [GuardError] :error 違反が1件以上あれば送出（本処理に入らせない）
        def run!(*checks)
          violations = checks.flat_map(&:validate)
          warns, errors = violations.partition(&:warn?)

          warns.each  { Common.log_warn(it.message, detail: join_detail(it.detail)) }
          errors.each { Common.log_error(it.message, detail: join_detail(it.detail)) }

          return if errors.empty?

          raise GuardError,
                "前提条件を満たしていません（エラー #{errors.size} 件 / 警告 #{warns.size} 件）"
        end

        # Common.format_detail は改行区切りの String を期待するため、
        # Check が行の配列で detail を返した場合はここで連結する
        def join_detail(detail) = detail.is_a?(Array) ? detail.join("\n") : detail
      end

      module_function

      # コマンドの call 冒頭用ヘルパー。Guard を実行し、
      # 違反時は要約を 🔴 で表示して終了コード 1 を返す（合格時は nil）。
      #
      # 使用例:
      #   guard_failure = Guards.precheck(Guards::ProjectRootCheck.new)
      #   return guard_failure if guard_failure
      def precheck(*checks)
        Guard.run!(*checks)
        nil
      rescue GuardError => e
        Common.log_error(e.message)
        1
      end
    end
  end
end
