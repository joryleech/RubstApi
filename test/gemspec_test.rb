# frozen_string_literal: true

require_relative "test_helper"

class GemspecTest < Minitest::Test
  def test_base64_is_a_runtime_dependency
    gemspec = Gem::Specification.load(
      File.expand_path("../rubst_api.gemspec", __dir__)
    )
    dependency = gemspec.runtime_dependencies.find { |item| item.name == "base64" }

    refute_nil dependency
    assert dependency.requirement.satisfied_by?(Gem::Version.new("0.3.0"))
  end
end
