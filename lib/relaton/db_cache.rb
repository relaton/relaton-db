require "fileutils"
require "timeout"

module Relaton
  class DbCache
    # @return [String]
    attr_reader :dir

    # @param dir [String] DB directory
    def initialize(dir, ext = "xml")
      @dir = dir
      @ext = ext
      FileUtils::mkdir_p dir
    end

    # Move caches to anothe dir
    # @param new_dir [String, nil]
    # @return [String, nil]
    def mv(new_dir)
      return unless new_dir && @ext == "xml"

      if File.exist? new_dir
        Util.info "target directory exists `#{new_dir}`"
        return
      end

      FileUtils.mv dir, new_dir
      @dir = new_dir
    end

    # Clear database
    def clear
      FileUtils.rm_rf Dir.glob "#{dir}/*"
    end

    # Save item
    # @param key [String]
    # @param value [String] Bibitem xml serialization
    def []=(key, value)
      if value.nil?
        delete key
        return
      end

      prefix_dir = "#{@dir}/#{prefix(key)}"
      FileUtils::mkdir_p prefix_dir
      set_version prefix_dir
      file_safe_write "#{filename(key)}.#{ext(value)}", value
    end

    # @param value [String]
    # @return [String]
    def ext(value)
      case value
      when /^not_found/ then "notfound"
      when /^redirection/ then "redirect"
      else @ext
      end
    end

    # Read item
    # @param key [String]
    # @return [String]
    def [](key)
      value = get(key)
      if (code = redirect_code value)
        self[code]
      else
        value
      end
    end

    #
    # Save entry from cache of `db` to this cache.
    #
    # @param [String] key key of the entry
    # @param [Relaton::Db] db database
    #
    def clone_entry(key, db)
      self[key] ||= db.get(key)
      if (code = redirect_code get(key))
        clone_entry code, db
      end
    end

    # Return fetched date
    # @param key [String]
    # @return [String]
    def fetched(key)
      value = self[key]
      return unless value

      if value.match?(/^not_found/)
        value.match(/\d{4}-\d{2}-\d{2}/).to_s
      else
        doc = Nokogiri::XML value
        doc.at("/bibitem/fetched|bibdata/fetched")&.text
      end
    end

    # Returns all items
    # @return [Array<String>]
    def all(&block)
      Dir.glob("#{@dir}/**/*.{xml,yml,yaml}").map do |f|
        content = File.read(f, encoding: "utf-8")
        block ? yield(f, content) : content
      end
    end

    # Delete item
    # @param key [String]
    def delete(key)
      file = filename key
      f = search_ext file
      return unless f

      if File.extname(f) == ".redirect"
        code = redirect_code get(key)
        delete code if code
      end
      File.delete f
    end

    # Check if version of the DB match to the gem grammar hash.
    # @param fdir [String] dir pathe to flover cache
    # @return [Boolean]
    def check_version?(fdir)
      version_dir = "#{fdir}/version"
      return false unless File.exist? version_dir

      v = File.read version_dir, encoding: "utf-8"
      v.strip == self.class.grammar_hash(fdir)
    end

    # if cached reference is undated, expire it after 60 days
    # @param key [String]
    # @param year [String]
    def valid_entry?(key, year)
      datestr = fetched key
      return false unless datestr

      date = Date.parse datestr
      year || Date.today - date < 60
    end

    # Reads file by a key
    #
    # @param key [String]
    # @return [String, NilClass]
    def get(key)
      file = filename key
      return unless (f = search_ext(file))

      File.read(f, encoding: "utf-8")
    end

    # @param fdir [String] dir pathe to flover cache
    # @return [String]
    def self.grammar_hash(fdir)
      type = fdir.split("/").last
      Relaton::Registry.instance.by_type(type)&.grammar_hash
    end

    private

    # @param value [String]
    # @return [String]
    def filename(key)
      prefcode = key.downcase.match(/^(?<prefix>[^(]+)\((?<code>[^)]+)/)
      fn = if prefcode
             "#{prefcode[:prefix]}/#{prefcode[:code].gsub(/[:\s\/()]/,
                                                          '_').squeeze('_')}"
           else
             key.gsub(/[-:\s]/, "_")
           end
      "#{@dir}/#{fn.sub(/(,|_$)/, '')}"
    end

    #
    # Checks if there is file with xml or txt extension and return filename with
    # the extension.
    #
    # @param file [String]
    # @return [String, NilClass]
    def search_ext(file)
      if File.exist?("#{file}.#{@ext}")
        "#{file}.#{@ext}"
      elsif File.exist? "#{file}.notfound"
        "#{file}.notfound"
      elsif File.exist? "#{file}.redirect"
        "#{file}.redirect"
      end
    end

    # Set version of the DB to the gem grammar hash.
    # @param fdir [String] dir pathe to flover cache
    def set_version(fdir)
      file_version = "#{fdir}/version"
      unless File.exist? file_version
        file_safe_write file_version, self.class.grammar_hash(fdir)
      end
    end

    # Return item's file name
    # @param key [String]
    # @return [String]
    def prefix(key)
      key.downcase.match(/^[^(]+(?=\()/).to_s
    end

    # Check if a file content is redirection
    #
    # @prarm value [String] file content
    # @return [String, NilClass] redirection code or nil
    def redirect_code(value)
      %r{redirection\s(?<code>.*)} =~ value
      code
    end

    # @param file [String]
    # @content [String]
    def file_safe_write(file, content)
      File.open file, File::RDWR | File::CREAT, encoding: "UTF-8" do |f|
        Timeout.timeout(10) { f.flock File::LOCK_EX }
        f.write content
        f.flock File::LOCK_UN
      end
    end
  end
end
