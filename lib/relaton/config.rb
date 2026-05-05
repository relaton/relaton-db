module Relaton
  module Config
    def configure
      yield configuration if block_given?
    end

    def configuration
      @configuration ||= self::Configuration.new
    end
  end

  # < RelatonBib::Configuration
  class Configuration
    attr_accessor :use_api, :api_host

    def initialize
      # super
      @use_api = false
      @api_host = "https://api.relaton.org"
    end
  end

  extend Config
end
