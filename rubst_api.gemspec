# frozen_string_literal: true

require_relative "lib/rubst_api/version"

Gem::Specification.new do |spec|
  spec.name = "rubst_api"
  spec.version = RubstApi::VERSION
  spec.authors = ["Jory Leech"]
  spec.email = ["joryleech@gmail.com"]
  spec.summary = "Build typed Ruby APIs with validation and automatic OpenAPI docs"
  spec.description = <<~DESCRIPTION.strip
    RubstAPI is a FastAPI-inspired, Rack-compatible framework for building
    typed Ruby REST APIs. It provides request and response validation,
    dependency injection, OpenAPI 3.1 schemas, Swagger UI, ReDoc, security
    helpers, middleware, routing, background tasks, and testing utilities.
  DESCRIPTION
  spec.homepage = "https://github.com/joryleech/RubstApi"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.required_rubygems_version = ">= 3.3.0"

  spec.files = Dir[
    "lib/**/*",
    "exe/*",
    "README.md",
    "CHANGELOG.md",
    "SECURITY.md",
    "LICENSE",
    "LICENSES/**/*",
    "THIRD_PARTY_NOTICES.md"
  ]

  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = ["rubst_api"]
  spec.extra_rdoc_files = [
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md"
  ]

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "bug_tracker_uri" => "https://github.com/joryleech/RubstApi/issues",
    "changelog_uri" => "https://github.com/joryleech/RubstApi/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/joryleech/RubstApi#readme",
    "homepage_uri" => "https://github.com/joryleech/RubstApi",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/joryleech/RubstApi/tree/main"
  }

  spec.add_dependency "rack", ">= 3.0", "< 4.0"
  spec.add_dependency "rackup", ">= 2.0", "< 3.0"
  spec.add_dependency "webrick", ">= 1.8", "< 2.0"

  spec.add_development_dependency "minitest", ">= 5.0", "< 7.0"
  spec.add_development_dependency "rake", ">= 13.0", "< 14.0"
end
