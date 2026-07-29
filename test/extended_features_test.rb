# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "zlib"

class ExtendedFeaturesTest < Minitest::Test
  class Coordinate < RubstApi::Model
    field :value, Integer
  end

  def test_nested_dependencies_are_resolved_and_cached
    calls = 0
    database = RubstApi.Depends(-> { calls += 1; "db" })
    current_user = RubstApi.Depends(->(db:) { "#{db}:user" }, dependencies: { db: database })
    app = RubstApi::App.new
    app.get("/", params: { user: current_user, same_db: database }) { |user:, same_db:| { user:, same_db: } }

    assert_equal({ "user" => "db:user", "same_db" => "db" }, RubstApi::TestClient.new(app).get("/").json)
    assert_equal 1, calls
  end

  def test_security_scheme_is_in_openapi
    bearer = RubstApi::Security::OAuth2PasswordBearer.new(
      token_url: "/token", scopes: { "items:read" => "Read items" }
    )
    app = RubstApi::App.new
    app.get("/items", params: {
      token: RubstApi.Security(bearer, scopes: ["items:read"])
    }) { |token:| { token: } }

    schema = RubstApi::TestClient.new(app).get("/openapi.json").json
    assert_equal "oauth2", schema.dig("components", "securitySchemes", "OAuth2PasswordBearer", "type")
    assert_equal ["items:read"], schema.dig("paths", "/items", "get", "security", 0, "OAuth2PasswordBearer")
  end

  def test_multiple_body_parameters_and_array_query
    app = RubstApi::App.new
    app.post("/sum", params: {
      left: RubstApi.Body(Integer),
      right: RubstApi.Body(Integer),
      tags: RubstApi.Query({ array: String })
    }) { |left:, right:, tags:| { total: left + right, tags: } }

    response = RubstApi::TestClient.new(app).post("/sum?tags=a&tags=b", json: { left: 2, right: 3 })
    assert_equal({ "total" => 5, "tags" => %w[a b] }, response.json)
  end

  def test_multiple_model_body_parameters_are_embedded_by_name
    app = RubstApi::App.new
    app.post("/coordinates", params: {
      x: RubstApi.Body(Coordinate),
      y: RubstApi.Body(Coordinate)
    }) { |x:, y:| { total: x.value + y.value } }

    response = RubstApi::TestClient.new(app).post(
      "/coordinates", json: { x: { value: 4 }, y: { value: 6 } }
    )
    assert_equal({ "total" => 10 }, response.json)
  end

  def test_injected_response_and_background_tasks
    completed = []
    app = RubstApi::App.new
    app.post("/") do |response:, background_tasks:|
      response.status_code = 202
      response.headers["x-job"] = "queued"
      background_tasks.add_task(->(value) { completed << value }, "done")
      { accepted: true }
    end
    response = RubstApi::TestClient.new(app).post("/")

    assert_equal 202, response.status
    assert_equal "queued", response.headers["x-job"]
    assert_equal ["done"], completed
  end

  def test_mount_static_files_and_block_path_traversal
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "index.html"), "hello")
      app = RubstApi::App.new
      app.mount("/assets", RubstApi::StaticFiles.new(directory:, html: true))
      client = RubstApi::TestClient.new(app)

      assert_equal "hello", client.get("/assets/").text
      assert_equal 404, client.get("/assets/../secret.txt").status
    end
  end

  def test_gzip_and_server_sent_events
    app = RubstApi::App.new
    app.get("/large") { { value: "x" * 100 } }
    app.get("/events") { RubstApi::EventSourceResponse.new([{ ready: true }]) }
    app.add_middleware(RubstApi::Middleware::GZipMiddleware, minimum_size: 10)
    client = RubstApi::TestClient.new(app)

    zipped = client.get("/large", headers: { "Accept-Encoding" => "gzip" })
    assert_equal "gzip", zipped.headers["content-encoding"]
    assert_includes Zlib::GzipReader.new(StringIO.new(zipped.body)).read, "\"value\""

    events = client.get("/events")
    assert_equal "text/event-stream", events.headers["content-type"]
    assert_equal "data: {\"ready\":true}\n\n", events.text
  end
end
