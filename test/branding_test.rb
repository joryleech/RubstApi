# frozen_string_literal: true

require_relative "test_helper"

class BrandingTest < Minitest::Test
  def test_rubst_api_is_the_only_public_namespace
    app = RubstApi::App.new(title: "RubstApi")
    app.get("/") { { framework: "RubstApi" } }

    response = RubstApi::TestClient.new(app).get("/")
    assert_equal({ "framework" => "RubstApi" }, response.json)
    refute Object.const_defined?(:FastAPI)
    assert_raises(LoadError) { require "fast_api" }
  end
end
