# frozen_string_literal: true

require_relative "lib/rubst_api/version"

Gem::Specification.new do |spec|
  spec.name = "rubst_api"
  spec.version = RubstApi::VERSION
  spec.authors = ["RubstAPI contributors"]
  spec.summary = "RubstApi: a Ruby-native port of FastAPI's developer experience"
  spec.description = "Rack-compatible API framework with validation, dependency injection, OpenAPI, security, and automatic docs."
  spec.homepage = "https://github.com/fastapi/fastapi"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir[
    "lib/**/*",
    "exe/*",
    "README.md",
    "LICENSE",
    "LICENSES/**/*",
    "THIRD_PARTY_NOTICES.md"
  ]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = ["rubst_api"]
end
