# coding: utf-8

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "relaton/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton"
  spec.version       = Relaton::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "The Relaton core for importing, managing and caching "\
                       "bibliographic references to technical standards."
  spec.description   = <<~DESCRIPTION
      The Relaton core for importing, managing and caching bibliographic
    references to technical standards in the Relaton/XML bibliographic
    model.

    This gem is in active development.
  DESCRIPTION

  spec.homepage      = "https://github.com/relaton/relaton"
  spec.license       = "BSD-2-Clause"

  spec.bindir        = "bin"
  spec.require_paths = ["lib"]
  spec.files         = `git ls-files`.split("\n")
  # spec.test_files    = `git ls-files -- {spec}/*`.split("\n")
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0")

  spec.add_dependency "relaton-3gpp", "~> 1.20.0"
  spec.add_dependency "relaton-bipm", "~> 1.20.0"
  spec.add_dependency "relaton-bsi", "~> 1.20.0"
  spec.add_dependency "relaton-calconnect", "~> 1.20.0"
  spec.add_dependency "relaton-ccsds", "~> 1.20.2"
  spec.add_dependency "relaton-cen", "~> 1.20.0"
  spec.add_dependency "relaton-cie", "~> 1.20.0"
  spec.add_dependency "relaton-doi", "~> 1.20.0"
  spec.add_dependency "relaton-ecma", "~> 1.20.0"
  spec.add_dependency "relaton-etsi", "~> 1.20.0"
  spec.add_dependency "relaton-gb", "~> 1.20.4"
  spec.add_dependency "relaton-iana", "~> 1.20.0"
  spec.add_dependency "relaton-iec", "~> 1.20.3"
  spec.add_dependency "relaton-ieee", "~> 1.20.4"
  spec.add_dependency "relaton-ietf", "~> 1.20.0"
  spec.add_dependency "relaton-iho", "~> 1.20.0"
  spec.add_dependency "relaton-isbn", "~> 1.20.0"
  spec.add_dependency "relaton-iso", "~> 1.20.0"
  spec.add_dependency "relaton-itu", "~> 1.20.0"
  spec.add_dependency "relaton-jis", "~> 1.20.0"
  spec.add_dependency "relaton-nist", "~> 1.20.5"
  spec.add_dependency "relaton-oasis", "~> 1.20.0"
  spec.add_dependency "relaton-ogc", "~> 1.20.0"
  spec.add_dependency "relaton-omg", "~> 1.20.0"
  spec.add_dependency "relaton-plateau", "~> 1.20.0"
  spec.add_dependency "relaton-un", "~> 1.20.0"
  spec.add_dependency "relaton-w3c", "~> 1.20.0"
  spec.add_dependency "relaton-xsf", "~> 1.20.0"
end
