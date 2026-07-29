# frozen_string_literal: true

require_relative "test_helper"

class AppTest < Minitest::Test
  class Item < RubstApi::Model
    field :name, String, min_length: 2
    field :price, Float, gt: 0
    field :available, :boolean, default: true
  end

  def setup
    @app = RubstApi::App.new(title: "Shop", version: "1.2.3")
    @client = RubstApi::TestClient.new(@app)
  end

  def test_path_query_header_cookie_and_body
    @app.put("/items/{id}", params: {
      id: RubstApi.Path(Integer),
      q: RubstApi.Query(String, default: "none"),
      agent: RubstApi.Header(String, alias: "x-agent"),
      session: RubstApi.Cookie(String),
      item: RubstApi.Body(Item)
    }, response_model: Item) do |id:, q:, agent:, session:, item:|
      raise "bad injection" unless [id, q, agent, session] == [7, "find", "test", "abc"]
      item
    end
    response = @client.put("/items/7", params: { q: "find" }, headers: { "X-Agent" => "test" },
                          cookies: { session: "abc" }, json: { name: "Book", price: 12.5 })
    assert_equal 200, response.status
    assert_equal({ "name" => "Book", "price" => 12.5, "available" => true }, response.json)
  end

  def test_validation_error_shape
    @app.post("/items", params: { item: RubstApi.Body(Item) }) { |item:| item }
    response = @client.post("/items", json: { name: "x", price: -1 })
    assert_equal 422, response.status
    assert response.json["detail"].all? { |error| error.key?("loc") && error.key?("type") }
  end

  def test_dependency_cache_and_override
    calls = 0
    dependency = -> { calls += 1 }
    descriptor = RubstApi.Depends(dependency)
    @app.get("/dep", params: { a: descriptor, b: descriptor }) { |a:, b:| { a:, b: } }
    assert_equal({ "a" => 1, "b" => 1 }, @client.get("/dep").json)
    @app.dependency_overrides[dependency] = -> { 9 }
    assert_equal({ "a" => 9, "b" => 9 }, @client.get("/dep").json)
  end

  def test_router_and_exception_handler
    router = RubstApi::APIRouter.new(prefix: "/v1", tags: ["v1"])
    router.get("/boom") { raise RubstApi::HTTPException.new(status_code: 409, detail: "duplicate") }
    @app.include_router(router)
    response = @client.get("/v1/boom")
    assert_equal 409, response.status
    assert_equal "duplicate", response.json["detail"]
  end

  def test_openapi_and_docs
    @app.post("/items", params: { item: RubstApi.Body(Item) }, response_model: Item, tags: ["items"]) { |item:| item }
    schema = @client.get("/openapi.json").json
    assert_equal "Shop", schema.dig("info", "title")
    assert schema.dig("paths", "/items", "post")
    assert schema.dig("components", "schemas", "Item")
    assert_includes @client.get("/docs").text, "SwaggerUIBundle"
    assert_includes @client.get("/redoc").text, "redoc"
  end

  def test_not_found_and_method_not_allowed
    @app.get("/only") { { ok: true } }
    assert_equal 404, @client.get("/missing").status
    assert_equal 405, @client.post("/only").status
  end

  def test_cors
    @app.get("/") { { ok: true } }
    @app.add_middleware(RubstApi::Middleware::CORSMiddleware, allow_origins: ["*"], allow_methods: ["GET"])
    response = @client.get("/", headers: { "Origin" => "https://example.com" })
    assert_equal "*", response.headers["access-control-allow-origin"]
  end

  def test_security_bearer
    bearer = RubstApi::Security::HTTPBearer.new
    @app.get("/me", params: { credentials: RubstApi.Depends(bearer) }) { |credentials:| { token: credentials.credentials } }
    assert_equal "secret", @client.get("/me", headers: { "Authorization" => "Bearer secret" }).json["token"]
    assert_equal 401, @client.get("/me").status
  end
end
