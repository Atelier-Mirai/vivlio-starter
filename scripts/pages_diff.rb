# frozen_string_literal: true

# ================================================================
# scripts/pages_diff.rb — scripts/pages_snapshot.rb で写し取った HTML を前後で比べる
# ================================================================
# 使い方:
#   ruby scripts/pages_diff.rb <前の写し> <後の写し>
#
# 合成画像の名前（`pictures-<ハッシュ>.jpg`。作り直すたびに変わる）をそろえてから、ファイルごとに
#   same            … バイト単位で同じ
#   attribute_order … 属性の順と空白だけが違う
#   different       … それ以外
# に分ける。増えたファイルも示す。
# ================================================================

require 'nokogiri'

def canonical(html)
  doc = Nokogiri::HTML5.parse(html)
  doc.traverse do |node|
    next unless node.element?

    attrs = node.attribute_nodes.map { [it.name, it.value] }.sort
    node.attribute_nodes.each(&:remove)
    attrs.each { |name, value| node[name] = value }
  end
  doc.to_html.gsub(/\s+/, ' ')
end

before, after = ARGV
abort 'usage: ruby scripts/pages_diff.rb <前の写し> <後の写し>' unless before && after

counts = Hash.new(0)
Dir.glob('**/*', base: before).sort.each do |rel|
  next unless File.file?(File.join(before, rel))

  a, b = [before, after].map do |dir|
    path = File.join(dir, rel)
    File.exist?(path) ? File.read(path).gsub(/pictures-[0-9a-f]{16,64}\.jpg/, 'pictures-X.jpg') : nil
  end
  kind = if b.nil? then :missing
         elsif a == b then :same
         elsif rel.end_with?('.html', '.xhtml') && canonical(a) == canonical(b) then :attribute_order
         else :different
         end
  counts[kind] += 1
  puts "#{kind}: #{rel}" unless kind == :same
end
added = Dir.glob('**/*', base: after) - Dir.glob('**/*', base: before)
puts "増えた: #{added.join(' ')}" unless added.empty?
puts counts.inspect
exit(counts.keys.all?(:same) && added.empty? ? 0 : 1)
