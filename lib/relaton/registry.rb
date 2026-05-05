require "singleton"

# class Error < StandardError
# end

module Relaton
  class Registry
    SUPPORTED_GEMS = %w[
      relaton/gb relaton/iec relaton/ietf relaton/iso
      relaton/itu relaton/nist relaton/ogc relaton/calconnect
      relaton/omg relaton/un relaton/w3c relaton/ieee
      relaton/iho relaton/bipm relaton/ecma relaton/cie
      relaton/bsi relaton/cen relaton/iana relaton/3gpp
      relaton/oasis relaton/doi relaton/jis relaton/xsf
      relaton/ccsds relaton/etsi relaton/isbn relaton/plateau
    ].freeze

    include Singleton

    attr_reader :processors

    def initialize
      @processors = {}
      register_gems
    end

    def register_gems
      # Util.info("Info: detecting backends:")

      SUPPORTED_GEMS.each do |b|
        require "#{b}/processor"
        register Kernel.const_get "#{gem_to_module_path(b)}::Processor"
      rescue LoadError => e
        Util.error "backend #{b} not present\n" \
                   "#{e.message}\n#{e.backtrace.join "\n"}"
      end
    end

    def register(processor)
      raise Error unless processor < Core::Processor

      p = processor.new
      return if processors[p.short]

      Util.debug("processor \"#{p.short}\" registered")
      processors[p.short] = p
    end

    def find_processor(short)
      processors[short.to_sym]
    end

    # @return [Array<Symbol>]
    def supported_processors
      processors.keys
    end

    #
    # Search a rpocessos by dataset name
    #
    # @param [String] dataset
    #
    # @return [Relaton::Core::Processor, nil]
    #
    def find_processor_by_dataset(dataset)
      processors.values.detect { |p| p.datasets&.include? dataset }
    end

    #
    # Find processor by type
    #
    # @param type [String]
    # @return [Relaton::Core::Processor]
    def by_type(type)
      processors.values.detect { |v| v.prefix == type&.upcase }
    end

    def [](stdclass)
      processors[stdclass]
    end

    #
    # Find processor by reference or prefix
    #
    # @param [String] ref reference or prefix
    #
    # @return [Relaton::Core::Processor] processor
    #
    def processor_by_ref(ref)
      processors[class_by_ref(ref)]
    end

    #
    # Find processor by refernce or prefix
    #
    # @param ref [String] reference or prefix
    #
    # @return [Symbol, nil] standard class name
    #
    def class_by_ref(ref)
      ref = Regexp.last_match(1) if ref =~ /^\w+\((.*)\)$/
      @processors.each do |class_name, processor|
        return class_name if /^(urn:)?#{processor.prefix}\b/i.match?(ref) ||
          processor.defaultprefix.match(ref)
      end
      Util.info "`#{ref}` does not have a recognised prefix", key: ref
      nil
    end

    private

    def gem_to_module_path(gem_name)
      gem_name.split("/").map do |part|
        part.capitalize.sub("3gpp", "ThreeGpp")
      end.join("::")
    end
  end
end
