module Relaton
  class Db
    # @param global_cache [String] directory of global DB
    # @param local_cache [String] directory of local DB
    def initialize(global_cache, local_cache)
      @registry = Relaton::Registry.instance
      gpath = global_cache && File.expand_path(global_cache)
      @db = open_cache_biblio(gpath)
      lpath = local_cache && File.expand_path(local_cache)
      @local_db = open_cache_biblio(lpath)
      @queues = {}
      @semaphore = Mutex.new
    end

    # Move global or local caches to anothe dirs
    # @param new_dir [String, nil]
    # @param type: [Symbol]
    # @return [String, nil]
    def mv(new_dir, type: :global)
      case type
      when :global then @db&.mv new_dir
      when :local then @local_db&.mv new_dir
      end
    end

    # Clear global and local databases
    def clear
      @db&.clear
      @local_db&.clear
      @registry.processors.each_value do |p|
        p.remove_index_file if p.respond_to? :remove_index_file
      end
    end

    ##
    # The class of reference requested is determined by the prefix
    # of the reference:
    # GB Standard for gbbib, IETF for ietfbib, ISO for isobib, IEC or IEV for
    #   iecbib,
    #
    # @param text [String] the standard reference to look up (e.g. "ISO 9000")
    # @param year [String] the year the standard was published (optional)
    #
    # @param opts [Hash] options
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    # @option opts [Boolean] :no_cache If true then don't use cache
    # @option opts [String] :publication_date_before published before this date
    #  (exclusive, formats: "YYYY", "YYYY-MM", or "YYYY-MM-DD")
    # @option opts [String] :publication_date_after published on or
    #  after this date (inclusive, formats: "YYYY", "YYYY-MM",
    #  or "YYYY-MM-DD")
    #
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    ##
    def fetch(text, year = nil, opts = {})
      reference = text.strip
      stdclass = @registry.class_by_ref(reference) || return
      processor = @registry[stdclass]
      ref = if processor.respond_to?(:urn_to_code)
              processor.urn_to_code(reference)&.first
            else reference
            end
      ref ||= reference
      result = combine_doc ref, year, opts, stdclass
      result || check_bibliocache(ref, year, opts, stdclass)
    end

    # @see Relaton::Db#fetch
    def fetch_db(code, year = nil, opts = {})
      opts[:fetch_db] = true
      fetch code, year, opts
    end

    # fetch all standards from DB
    # @param test [String, nil]
    # @param edition [String], nil
    # @param year [Integer, nil]
    # @return [Array]
    def fetch_all(text = nil, edition: nil, year: nil)
      result = []
      db = @db || @local_db
      if db
        result += db.all do |file, xml|
          search_xml file, xml, text, edition, year
        end.compact
      end
      result
    end

    #
    # Fetch asynchronously
    #
    # @param [String] ref reference
    # @param [String] year document yer
    # @param [Hash] opts options
    #
    # @return [RelatonBib::BibliographicItem,
    #   RelatonBib::RequestError, nil] bibitem if document is
    #   found, request error if server doesn't answer,
    #   nil if document not found
    #
    def fetch_async(ref, year = nil, opts = {}, &block) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      stdclass = @registry.class_by_ref ref
      if stdclass
        unless @queues[stdclass]
          processor = @registry[stdclass]
          threads = ENV["RELATON_FETCH_PARALLEL"]&.to_i || processor.threads
          wp = WorkersPool.new(threads) do |args|
            args[3].call fetch(*args[0..2])
          rescue Relaton::RequestError => e
            args[3].call e
          rescue StandardError => e
            Util.error "`#{args[0]}` -- #{e.message}"
            args[3].call nil
          end
          @queues[stdclass] =
            { queue: SizedQueue.new(threads * 2), workers_pool: wp }
          Thread.new { process_queue @queues[stdclass] }
        end
        @queues[stdclass][:queue] << [ref, year, opts, block]
      else yield nil
      end
    end

    # @param code [String]
    # @param year [String, NilClass]
    # @param stdclass [Symbol, NilClass]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    def fetch_std(code, year = nil, stdclass = nil, opts = {})
      std = nil
      @registry.processors.each do |name, processor|
        std = name if processor.prefix == stdclass
      end
      std = @registry.class_by_ref(code) or return nil unless std

      check_bibliocache(code, year, opts, std)
    end

    # The document identifier class corresponding to the given code
    # @param code [String]
    # @return [Array]
    def docid_type(code)
      stdclass = @registry.class_by_ref(code) or return [nil, code]
      _, code = strip_id_wrapper(code, stdclass)
      [@registry[stdclass].idtype, code]
    end

    # @param key [String]
    # @return [Hash]
    def load_entry(key)
      (@local_db && @local_db[key]) || @db[key]
    end

    # @param key [String]
    # @param value [String] Bibitem xml serialisation.
    # @option value [String] Bibitem xml serialisation.
    def save_entry(key, value)
      @db.nil? || (@db[key] = value)
      @local_db.nil? || (@local_db[key] = value)
    end

    # list all entries as a serialization
    # @return [String]
    def to_xml
      db = @local_db || @db || return
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.documents { xml.parent.add_child db.all.join(" ") }
      end.to_xml
    end

    private

    # @param (see #fetch_api)
    # @return (see #fetch_api)
    def fetch_doc(code, year, opts, processor)
      if Relaton.configuration.use_api then fetch_api(code, year, opts,
                                                      processor)
      else processor.get(code, year, opts)
      end
    end

    #
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    #
    # @param processor [Relaton::Processor]
    # @return [RelatonBib::BibliographicItem, nil]
    def fetch_api(code, year, opts, processor)
      url = "#{Relaton.configuration.api_host}" \
            "/api/v1/document?#{params(code, year, opts)}"
      rsp = Net::HTTP.get_response URI(url)
      processor.from_xml rsp.body if rsp.code == "200"
    rescue Errno::ECONNREFUSED
      processor.get(code, year, opts)
    end

    #
    # Make string of parametrs
    #
    # @param [String] code
    # @param [String] year
    # @param [Hash] opts
    #
    # @return [String]
    #
    def params(code, year, opts)
      opts.merge(code: code, year: year).map { |k, v| "#{k}=#{v}" }.join "&"
    end

    # @param file [String] file path
    # @param xml [String] content in XML format
    # @param text [String, nil] text to serach
    # @param edition [String, nil] edition to filter
    # @param year [Integer, nil] year to filter
    # @return [BibliographicItem, nil]
    def search_xml(file, xml, text, edition, year)
      return unless text.nil? || match_xml_text?(xml, text)

      search_edition_year(file, xml, edition, year)
    end

    # @param file [String] file path
    # @param content [String] content in XML or YAML format
    # @param edition [String, nil] edition to filter
    # @param year [Integer, nil] year to filter
    # @return [BibliographicItem, nil]
    def search_edition_year(file, content, edition, year) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      processor = @registry.processor_by_ref(file.split("/")[-2])
      item = if file.match?(/xml$/) then processor.from_xml(content)
             else processor.from_yaml(content)
             end
      item if (edition.nil? || item.edition.content == edition) && (year.nil? ||
        item.date.detect do |d|
          d.type == "published" && d.at.to_date.year.to_s == year.to_s
        end)
    end

    #
    # Look up text in the XML elements attributes and content
    #
    # @param xml [String] content in XML format
    # @param text [String, nil] text to serach
    #
    # @return [Boolean]
    #
    def match_xml_text?(xml, text)
      esc = Regexp.escape(text)
      pat = "((?<attr>=((?<apstr>')|\"" \
            "))|>).*?#{esc}" \
            ".*?(?(<attr>)(?(<apstr>)'|\")|<)"
      Regexp.new(pat, Regexp::MULTILINE | Regexp::IGNORECASE)
        .match?(xml)
    end

    # @param code [String]
    # @param year [String, nil]
    # @param stdslass [String]
    #
    # @param opts [Hash] options
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @return [nil, Relaton::Bib::ItemData
    #
    def combine_doc(code, year, opts, stdclass) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      return if stdclass == :relaton_bipm

      if (refs = code.split " + ").size > 1
        reltype = "derivedFrom"
        reldesc = nil
      elsif (refs = code.split ", ").size > 1
        reltype = "complements"
        reldesc = Bib::LocalizedMarkedUpString.new content: "amendment"
      else return
      end

      yaml = { docidentifier: [{ content: code }] }.to_yaml
      doc = @registry[stdclass].from_yaml(yaml)
      ref = refs[0]
      updates = check_bibliocache(refs[0], year, opts, stdclass)
      if updates
        doc.relation << Bib::Relation.new(bibitem: updates, type: "updates")
      end
      divider = stdclass == :relaton_itu ? " " : "/"
      refs[1..].each_with_object(doc) do |c, d|
        bib = check_bibliocache(ref + divider + c, year, opts, stdclass)
        if bib
          d.relation << Bib::Relation.new(
            type: reltype, description: reldesc, bibitem: bib,
          )
        end
      end
    end

    # TODO: i18n
    # Fofmat ID
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @param stdClass [Symbol]
    # @return [Array<String>] docid and code
    def std_id(code, year, opts, stdclass)
      prefix, code = strip_id_wrapper(code, stdclass)
      ret = code
      ret += (stdclass == :relaton_gb ? "-" : ":") + year if year
      ret += " (all parts)" if opts[:all_parts]
      after = opts[:publication_date_after]
      ret += " after-#{after}" if after
      before = opts[:publication_date_before]
      ret += " before-#{before}" if before
      ["#{prefix}(#{ret.strip})", code]
    end

    # Find prefix and clean code
    # @param code [String]
    # @param stdClass [Symbol]
    # @return [Array]
    def strip_id_wrapper(code, stdclass)
      prefix = @registry[stdclass].prefix
      code =
        if code.is_a?(String)
          code.sub("\u2013", "-").sub(/^#{prefix}\((.+)\)$/, "\\1")
        else code.to_s
        end
      [prefix, code]
    end

    #
    # @param entry [String, nil] XML string
    # @param stdclass [Symbol]
    #
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    def bib_retval(entry, stdclass)
      if entry && !entry.match?(/^not_found/)
        @registry[stdclass].from_xml(entry)
      end
    end

    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    #
    # @param stdclass [Symbol]
    # @return [nil, RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    def check_bibliocache(code, year, opts, stdclass) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      # When date filters are present, check if the base
      # (non-date-filtered) cache entry satisfies the range
      if opts[:publication_date_before] || opts[:publication_date_after]
        base_opts = opts.except(
          :publication_date_before, :publication_date_after
        )
        base_id, = std_id(code, year, base_opts, stdclass)
        db = @local_db || @db
        if db&.valid_entry?(base_id, year)
          entry = db[base_id]
          if entry && !entry.match?(/^not_found/) &&
              pub_date_in_range?(entry, opts)
            return bib_retval(entry, stdclass)
          end
        end
      end

      id, searchcode = std_id(code, year, opts, stdclass)
      db = @local_db || @db
      altdb = @local_db && @db ? @db : nil
      if db.nil?
        return if opts[:fetch_db]

        bibentry = new_bib_entry(searchcode, year, opts, stdclass)
        return bib_retval(bibentry, stdclass)
      end

      @semaphore.synchronize do
        db.delete(id) unless db.valid_entry?(id, year)
      end
      if altdb
        return bib_retval(altdb[id], stdclass) if opts[:fetch_db]

        @semaphore.synchronize do
          db.clone_entry id, altdb if altdb.valid_entry? id, year
        end
        new_bib_entry(searchcode, year, opts, stdclass, db: db, id: id)
        @semaphore.synchronize do
          altdb.clone_entry(id, db) if !altdb.valid_entry?(id, year)
        end
      else
        return bib_retval(db[id], stdclass) if opts[:fetch_db]

        new_bib_entry(searchcode, year, opts, stdclass, db: db, id: id)
      end
      bib_retval(db[id], stdclass)
    end

    #
    # Create new bibliographic entry if it doesn't exist in database
    #
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean, nil] :all_parts If true then all-parts reference is
    #   requested
    # @option opts [Boolean, nil] :keep_year If true then undated reference
    #   should return actual reference with year
    # @option opts [Integer] :retries (1) Number of network retries
    # @option opts [Boolean] :no_cache If true then don't use cache
    #
    # @param stdclass [Symbol]
    # @param db [Relaton::DbCache,`nil]
    # @param id [String, nil] docid
    #
    # @return [String] bibliographic entry
    #   XML or "redirection ID" or "not_found YYYY-MM-DD" string
    #
    def new_bib_entry(code, year, opts, stdclass, **args)
      entry = @semaphore.synchronize { args[:db] && args[:db][args[:id]] }
      if !entry || opts[:no_cache]
        return fetch_entry(code, year, opts, stdclass, **args)
      end

      if entry&.match?(/^not_found/)
        Util.info "not found in cache, if you wish to " \
                  "ignore cache please use `no-cache` option.", key: code
        return
      end
      entry
    end

    def fetch_entry(code, year, opts, stdclass, **args)
      processor = @registry[stdclass]
      bib = net_retry(code, year, opts, processor, opts.fetch(:retries, 1))

      entry = check_entry(bib, stdclass, **args)
      return entry if args[:db].nil?

      @semaphore.synchronize { args[:db][args[:id]] ||= entry }
      args[:no_cache] ? bib_entry(bib) : entry
    end

    #
    # If the reference isn't equal to the document identifier
    # then store the document in the cache and create
    # for the reference a redirection to the document
    #
    # @param [<Type>] bib <description>
    # @param [<Type>] stdclass <description>
    # @param [<Type>] **args <description>
    #
    # @return [<Type>] <description>
    #
    def check_entry(bib, stdclass, **args) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      bib_id = bib && bib.docidentifier.first&.content

      # when ref isn't equal to bib's id then return a redirection to bib's id
      quoted = Regexp.quote("(#{bib_id})")
      if args[:db] && args[:id] && bib_id &&
          args[:id] !~ /#{quoted}/
        bid = std_id(bib.docidentifier.first.content, nil, {}, stdclass).first
        @semaphore.synchronize { args[:db][bid] ||= bib_entry bib }
        "redirection #{bid}"
      else bib_entry bib
      end
    end

    #
    # @param code [String]
    # @param year [String]
    #
    # @param opts [Hash]
    # @option opts [Boolean] :all_parts If all-parts reference is required
    # @option opts [Boolean] :keep_year If undated reference should return
    #   actual reference with year
    #
    # @param processor [Relaton::Processor]
    # @param retries [Integer] remain Number of network retries
    #
    # @raise [RelatonBib::RequestError]
    # @return [RelatonBib::BibliographicItem]
    #
    def net_retry(code, year, opts, processor, retries)
      fetch_doc code, year, opts, processor
    rescue Relaton::RequestError => e
      raise e unless retries > 1

      net_retry(code, year, opts, processor, retries - 1)
    end

    # @param bib [RelatonBib::BibliographicItem,
    #   RelatonIsoBib::IsoBibliographicItem, RelatonItu::ItuBibliographicItem,
    #   RelatonIetf::IetfBibliographicItem, RelatonIec::IecBibliographicItem,
    #   RelatonIeee::IeeeBibliographicItem, RelatonNist::NistBibliongraphicItem,
    #   RelatonGb::GbbibliographicItem, RelatonOgc::OgcBibliographicItem,
    #   RelatonCalconnect::CcBibliographicItem, RelatinUn::UnBibliographicItem,
    #   RelatonBipm::BipmBibliographicItem, RelatonIho::IhoBibliographicItem,
    #   RelatonOmg::OmgBibliographicItem, RelatonW3c::W3cBibliographicItem]
    # @return [String] XML or "not_found mm-dd-yyyy"
    def bib_entry(bib)
      if bib.respond_to?(:to_xml)
        bib.to_xml(bibdata: true)
      else
        "not_found #{Date.today}"
      end
    end

    # Check if an XML entry's published date falls within the requested range.
    # Range semantics: [after, before) — inclusive start, exclusive end.
    #
    # @param entry [String] XML string
    # @param opts [Hash]
    # @return [Boolean]
    def pub_date_in_range?(entry, opts) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      doc = Nokogiri::XML(entry)
      date_str = doc.at("//date[@type='published']/on")&.text
      return false unless date_str

      date = parse_pub_date(date_str)
      return false unless date

      after = opts[:publication_date_after]
      return false if after && date < Date.parse(after.to_s)

      before = opts[:publication_date_before]
      return false if before && date >= Date.parse(before.to_s)

      true
    end

    # @param str [String] date string in "YYYY", "YYYY-MM",
    #   or "YYYY-MM-DD" format
    # @return [Date, nil]
    def parse_pub_date(str)
      case str
      when /^\d{4}-\d{1,2}-\d{1,2}/ then Date.parse(str)
      when /^\d{4}-\d{1,2}/ then Date.strptime(str, "%Y-%m")
      when /^\d{4}/ then Date.strptime(str, "%Y")
      end
    rescue ArgumentError
      nil
    end

    # @param dir [String, nil] DB directory
    # @return [Relaton::DbCache, NilClass]
    def open_cache_biblio(dir) # rubocop:disable Metrics/MethodLength
      return nil if dir.nil?

      db = DbCache.new dir

      Dir["#{dir}/*/"].each do |fdir|
        next if db.check_version?(fdir)

        FileUtils.rm_rf(fdir, secure: true)
        Util.info "cache #{fdir}: version is obsolete and cache is cleared."
      end
      db
    end

    # @param qwp [Hash]
    # @option qwp [Queue] :queue The queue of references to fetch
    # @option qwp [Relaton::WorkersPool] :workers_pool The pool of workers
    def process_queue(qwp)
      while args = qwp[:queue].pop; qwp[:workers_pool] << args end
    end

    class << self
      #
      # Initialse and return relaton instance, with local and global cache names
      #
      # @param local_cache [String, nil] local cache name;
      #   "relaton" created if empty or nil
      # @param global_cache [Boolean, nil] create global_cache if true
      # @param flush_caches [Boolean, nil] flush caches if true
      #
      # @return [Relaton::Db] relaton DB instance
      #
      def init_bib_caches(**opts) # rubocop:disable Metrics/CyclomaticComplexity
        globalname = global_bibliocache_name if opts[:global_cache]
        localname = local_bibliocache_name(opts[:local_cache])
        flush_caches globalname, localname if opts[:flush_caches]
        Relaton::Db.new(globalname, localname)
      end

      def flush_caches(gcache, lcache)
        FileUtils.rm_rf gcache unless gcache.nil?
        FileUtils.rm_rf lcache unless lcache.nil?
      end

      def global_bibliocache_name
        "#{Dir.home}/.relaton/cache"
      end

      def local_bibliocache_name(cachename)
        return nil if cachename.nil?

        cachename = "relaton" if cachename.empty?
        "#{cachename}/cache"
      end
    end
  end
end
