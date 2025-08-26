# 01-legalpage.md 生成タスク
require_relative 'common'

# 利用方法:
#   rake legalpage          # config/book.yml の legal.* を用いて生成
#   vs legalpage            # CLI 経由（Rake統合）
# 既にファイルがある場合は上書きしない（--force で強制上書き）

desc 'リーガルページ(01-legalpage.md)を生成します'
task :legalpage do
  args = BookBuild.process_args('legalpage')
  options = args[:options] || {}

  contents_dir = BookBuild::CONTENTS_DIR
  FileUtils.mkdir_p(contents_dir)

  target = File.join(contents_dir, '01-legalpage.md')
  if File.exist?(target) && !options['force'] && !options[:force]
    BookBuild.log_warn("既に存在するためスキップします: #{target} (--force で上書き)")
    next
  end

  cfg = BookBuild::CONFIG || {}
  legal = (cfg['legal'] || {})
  disclaimer = (legal['disclaimer'] || '').strip
  trademark  = (legal['trademark']  || '').strip

  if disclaimer.empty? && trademark.empty?
    BookBuild.log_warn('config/book.yml の legal.disclaimer / legal.trademark が未設定です。テンプレート文面で生成します。')
    disclaimer = <<~TXT.strip
      本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
      本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
    TXT
    trademark = <<~TXT.strip
      本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
      本書では ™、®、© などのマークは省略しています。
    TXT
  end

  # Markdown 本文（見出しは本文側で与える。フロントマターは pre_process で自動付与）
  body = <<~MD
    <div class="disclaimer">
      <h2>■免責</h2>
      #{disclaimer.split(/\r?\n/).map { |l| "  <p>#{l}</p>" }.join("\n")}
    </div>

    <div class="trademark">
      <h2>■商標</h2>
      #{trademark.split(/\r?\n/).map { |l| "  <p>#{l}</p>" }.join("\n")}
    </div>
  MD

  File.write(target, body, encoding: 'utf-8')
  BookBuild.log_success("生成しました: #{target}")
end
