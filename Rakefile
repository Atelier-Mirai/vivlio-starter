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
    custom_order = ['test', 'test:layout', 'test:targets', 'test:kindle', 'test:manual', 'test:package', 'test:release', 'test:canary', 'reinstall']
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
    "test/**/page_layout/**/*_test.rb",
    "test/**/release/**/*_test.rb",
    "test/**/targets/**/*_test.rb",
    "test/**/kindle/**/*_test.rb"
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

# ------------------------------------------------------------------
# ターゲット整合性テスト（単体/複合 targets の実ビルド突き合わせ）
# 実ビルドを 7 通り回すため最も遅い。通常テストからは除外
# ------------------------------------------------------------------
namespace :test do
  Rake::TestTask.new(:targets) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/targets/**/*_test.rb"
    t.warning = false
  end
end

Rake::Task["test:targets"].clear_comments
Rake::Task["test:targets"].comment = "ターゲット整合性テスト（pdf/print_pdf/epub を単体・複合でビルドし突き合わせ）"

# ------------------------------------------------------------------
# Kindle 変換検証テスト（opt-in・Mac/Win ローカル専用）
# Kindle Previewer 3 CLI（kindlepreviewer）で EPUB を実変換し、
# conversionLog の画像系警告（W14015/W14012/W14010）ゼロを検証する。
# CLI 未導入環境では skip するため、Linux CI でも安全。実ビルドを伴い遅いので
# 通常 test からは除外する。
# ------------------------------------------------------------------
namespace :test do
  Rake::TestTask.new(:kindle) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/kindle/**/*_test.rb"
    t.warning = false
  end
end

Rake::Task["test:kindle"].clear_comments
Rake::Task["test:kindle"].comment = "Kindle 変換検証（kindlepreviewer で実変換し画像系警告ゼロを確認・要 Kindle Previewer 3）"

# ------------------------------------------------------------------
# RC 品質保証テスト群（docs/specs/test-suite-expansion-spec.md §3）
# 実ビルドを伴うため通常テストからは除外されている
# ------------------------------------------------------------------
namespace :test do
  # マニュアル実体の実ビルドと成果物検査（MB / FT / EP / ID）
  Rake::TestTask.new(:manual) do |t|
    t.libs << "test"
    t.test_files = FileList["test/vivlio_starter/release/**/*_test.rb"].exclude(
      "test/**/packaging_test.rb",
      "test/**/canary_test.rb"
    )
    t.warning = false
  end

  # gem ビルド → 隔離インストール → 動作確認（PK）
  Rake::TestTask.new(:package) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/release/packaging_test.rb"
    t.warning = false
  end

  # 上流（@vivliostyle/cli 最新版）での破壊検知（CN）。リリース判定には含めない
  Rake::TestTask.new(:canary) do |t|
    t.libs << "test"
    t.pattern = "test/vivlio_starter/release/canary_test.rb"
    t.warning = false
  end

  # RC 前総点検（canary は上流要因のため含めない）
  task release: ['test', 'test:layout', 'test:targets', 'test:manual', 'test:package']
end

Rake::Task["test:manual"].clear_comments
Rake::Task["test:manual"].comment = "マニュアル実ビルド + 成果物検査（警告ゼロ / フォント / EPUB / 冪等性）"
Rake::Task["test:package"].clear_comments
Rake::Task["test:package"].comment = "パッケージング E2E（gem build → 隔離インストール → ビルド確認）"
Rake::Task["test:canary"].clear_comments
Rake::Task["test:canary"].comment = "依存カナリア（@vivliostyle/cli 最新版での破壊検知）"
Rake::Task["test:release"].comment = "RC 前総点検（test → layout → targets → manual → package を一括実行）"

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
