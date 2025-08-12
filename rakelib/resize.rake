# frozen_string_literal: true
# resize.rake — 画像を WebP に一括リサイズ/変換する Rake タスク
#
# 使い方:
#   # 新しい推奨インターフェース（フラグ風）
#   rake resize --high           # 高精細（高品質）
#   rake resize --medium         # 標準（推奨）
#   rake resize --low            # 軽量（サイズ優先）
#   DIR=assets/images rake resize --medium   # 変換対象ディレクトリを指定
#   FORCE=1 rake resize --medium             # 既存 .webp があっても強制再生成
#
#   # 既存タスク（引数指定型、後方互換）
#   rake images:webp                            # 既定: 標準 preset、DIR=stylesheets/images
#   rake "images:webp[綺麗]"                     # preset を指定（綺麗/標準/粗い）
#   rake "images:webp[標準,stylesheets/images]"   # ディレクトリを指定
#   FORCE=1 rake images:webp                    # 既存 .webp があっても強制再生成
#
# 対象拡張子: .png, .jpg, .jpeg
# 生成先: 同ディレクトリに .webp を出力（元ファイルは残す）
# 依存ツール: ImageMagick (magick)

require 'rake'
require 'fileutils'

# プリセット定義（日本語名に対応）
PRESETS = {
  '高精細' => {
    quality: 90,            # 画質優先
    method:  6,             # WebP 圧縮メソッド（高品質・やや重い）
    max_px:  2000           # 長辺ピクセル上限
  },
  '標準' => {
    quality: 85,
    method:  6,
    max_px:  1600
  },
  '軽量' => {
    quality: 75,            # サイズ優先
    method:  6,
    max_px:  1200
  }
}.freeze

# 既定値
DEFAULT_DIR = 'images'
DEFAULT_PRESET = '標準'

# 実行に必要なコマンド確認
def which(cmd)
  exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
  ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
    exts.each do |ext|
      exe = File.join(path, "#{cmd}#{ext}")
      return exe if File.executable?(exe) && !File.directory?(exe)
    end
  end
  nil
end

def ensure_magick!
  abort 'Error: ImageMagick (magick) が見つかりません。brew install imagemagick 等で導入してください。' unless which('magick')
end

# 1ファイル変換
def convert_to_webp(src, dst, quality:, method:, max_px:)
  # すでに新しい .webp がある場合はスキップ（FORCE=1 で強制）
  unless ENV['FORCE']
    if File.exist?(dst) && File.mtime(dst) >= File.mtime(src)
      puts "skip: up-to-date #{dst}"
      return
    end
  end

  FileUtils.mkdir_p(File.dirname(dst))

  # -resize 'NxN>' は長辺を Npx に収める（大きいときのみ縮小）
  # -strip メタデータ削除、-quality 画質、-define webp:method 圧縮メソッド
  cmd = [
    'magick', src,
    '-resize', "#{max_px}x#{max_px}>",
    '-strip',
    '-quality', quality.to_s,
    '-define', "webp:method=#{method}",
    dst
  ]
  puts cmd.join(' ')
  system(*cmd) || abort("変換に失敗しました: #{src}")
end

# ディレクトリ一括処理
def run_resize(preset_name, dir)
  ensure_magick!

  preset = PRESETS[preset_name]
  abort "未知のプリセットです: #{preset_name}（利用可能: #{PRESETS.keys.join(' / ')}）" unless preset

  abort "ディレクトリが存在しません: #{dir}" unless Dir.exist?(dir)

  patterns = %w[png jpg jpeg JPG JPEG PNG]
  files = patterns.flat_map { |ext| Dir.glob(File.join(dir, "**/*.#{ext}")) }.uniq.sort

  if files.empty?
    puts "対象画像が見つかりませんでした: #{dir}"
    return
  end

  puts "Preset: #{preset_name} / Dir: #{dir} / Files: #{files.size}"
  files.each do |src|
    dst = src.sub(/\.[^.]+\z/, '.webp')
    convert_to_webp(src, dst, **preset)
  end
  puts '完了しました。'
end

# ------------------------------------------------------------
# レベル別ショートカットタスク（--high/--medium/--low 風の操作感）
# Rake は --high のような任意オプションを標準サポートしないため、
# 代替として namespaced タスクを用意する。
# ------------------------------------------------------------
namespace :resize do
  desc '高精細（高品質）: quality=90, max_px=2000'
  task :high, [:dir] do |_t, args|
    dir = (args[:dir] || DEFAULT_DIR)
    run_resize('高精細', dir)
  end

  desc '標準（推奨）: quality=85, max_px=1600'
  task :medium, [:dir] do |_t, args|
    dir = (args[:dir] || DEFAULT_DIR)
    run_resize('標準', dir)
  end

  desc '軽量（サイズ優先）: quality=75, max_px=1200'
  task :low, [:dir] do |_t, args|
    dir = (args[:dir] || DEFAULT_DIR)
    run_resize('軽量', dir)
  end
end

# フラグ風トークンをダミータスクとして定義しておくと、
# `rake resize --high` のような呼び方でも Rake がエラーにしない。
task :'--high'   do; end
task :'--medium' do; end
task :'--low'    do; end

# メインエントリ: `rake resize --high/--medium/--low`
desc '画像を WebP に一括リサイズ/変換（--high/--medium/--low, 環境変数: DIR, FORCE)'
task :resize do
  # 呼び出しタスク列からフラグ有無を判定
  top = Rake.application.top_level_tasks
  preset_name = if top.include?('--high')
                  '高精細'
                elsif top.include?('--medium')
                  '標準'
                elsif top.include?('--low')
                  '軽量'
                else
                  (defined?(DEFAULT_PRESET) ? DEFAULT_PRESET : '標準')
                end

  dir = ENV['DIR'] || DEFAULT_DIR

  puts "実行: preset=#{preset_name} DIR=#{dir} FORCE=#{ENV['FORCE'] ? '1' : '0'}"
  run_resize(preset_name, dir)
end
