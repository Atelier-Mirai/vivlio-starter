class Options
  # 引数配列を解析し、オプションとファイルリストを返す
  # 戻り値: { files: Array<String>, options: Hash<Symbol, Object> }
  def self.parse(argv)
    opts = {}
    files = []

    argv.each do |arg|
      case arg
      when /^--([^=]+)=(.*)/
        key = Regexp.last_match(1).tr('-', '_').to_sym
        val = Regexp.last_match(2)
        opts[key] = val
      when /^--no-(.+)/
        key = Regexp.last_match(1).tr('-', '_').to_sym
        opts[key] = false
      when /^--(.+)/
        key = Regexp.last_match(1).tr('-', '_').to_sym
        opts[key] = true
      when /^-([a-zA-Z]+)/
        Regexp.last_match(1).each_char { |c| opts[c.to_sym] = true }
      else
        files << arg
      end
    end

    { files: files, options: opts }
  end
end

