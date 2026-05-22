# frozen_string_literal: true

require 'rake/testtask'

# ==================================================================
# 拡張：rake -T の出力を、安全かつ確実に指定の順序で表示する
# ==================================================================
class << Rake.application
  def display_tasks_and_comments
    # コメントが設定されているタスクのみを抽出
    displayable_tasks = tasks.select { |t| t.comment }

    # 引数による絞り込み（rake -T pattern）が指定されている場合は安全に考慮
    if options.respond_to?(:show_task_pattern) && options.show_task_pattern
      displayable_tasks = displayable_tasks.select { |t| t.name =~ options.show_task_pattern }
    end

    # 【重要】出力させたい理想の順番を明示的に指定
    custom_order = ['test', 'test:layout', 'reinstall']
    displayable_tasks = displayable_tasks.sort_by { |t| custom_order.index(t.name) || 999 }

    # 表示幅を計算して綺麗にフォーマット出力
    width = displayable_tasks.map { |t| t.name.length }.max || 10
    displayable_tasks.each do |t|
      printf "rake %-#{width}s  # %s\n", t.name, t.comment
    end
  end
end

# ------------------------------------------------------------------
# 通常テストタスク
# ------------------------------------------------------------------
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude(
    "test/**/page_layout/**/*_test.rb"
  )
  t.warning = false
end

# 既存の "Run tests" を完全にクリアしてから上書き
Rake::Task["test"].clear_comments
Rake::Task["test"].comment = "通常テストスイーツを実行"

# ------------------------------------------------------------------
# 判型確認用専用テスト
# ------------------------------------------------------------------
namespace :test do
  Rake::TestTask.new(:layout) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/page_layout/**/*_test.rb"
    t.warning = false
  end
end

# 既存の "Run tests for layout" を完全にクリアしてから上書き
Rake::Task["test:layout"].clear_comments
Rake::Task["test:layout"].comment = "判型テスト（vs build を実際に実行する統合テスト）"

# デフォルトタスク（rake -T には出さない）
task default: :test

# ------------------------------------------------------------------
# gem のアンインストール → ビルド → インストールを一括実行
# ------------------------------------------------------------------
desc "gem のアンインストール → ビルド → インストールを一括実行"
task :reinstall do
  gemspec = Dir['*.gemspec'].first
  raise 'gemspec が見つかりません' unless gemspec

  require_relative 'lib/vivlio_starter/version'
  version = VivlioStarter::VERSION
  gem_name = 'vivlio-starter'

  sh "gem uninstall #{gem_name} --version #{version} --executables --ignore-dependencies 2>/dev/null || true"
  sh "gem build #{gemspec}"

  gem_file = Dir["#{gem_name}-*.gem"].max_by { |f| File.mtime(f) }
  raise "ビルドされた gem ファイルが見つかりません" unless gem_file

  sh "gem install #{gem_file}"
end
