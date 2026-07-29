# RubstAPI

### A FastAPI-inspired framework for building typed Ruby APIs

RubstAPI is a Ruby REST API framework that brings the developer experience of
[Python FastAPI](https://fastapi.tiangolo.com/) to Rack applications. Define
typed request parameters and data models once, then receive validation,
serialization, OpenAPI 3.1 documentation, Swagger UI, ReDoc, dependency
injection, and security integration automatically.

```ruby
require "rubst_api"

class Item < RubstApi::Model
  field :name, String, min_length: 2
  field :price, Float, gt: 0
  field :in_stock, :boolean, default: true
end

APP = RubstApi::App.new(title: "Store API", version: "1.0.0")

APP.post("/items", params: {
  item: RubstApi.Body(Item)
}, response_model: Item, status_code: 201) do |item:|
  item
end
```

Start the application and visit `/docs` for an interactive Swagger UI:

```console
rubst_api run app.rb
```

> [!IMPORTANT]
> RubstAPI is an independent Ruby project inspired by FastAPI. It is not
> affiliated with, endorsed by, or maintained by the Python FastAPI project.
> It is an idiomatic Ruby implementation—not a Python source-compatibility
> layer.

## Why RubstAPI?

Ruby has excellent web frameworks, but API projects often assemble request
validation, serialization, dependency injection, OpenAPI generation, security,
and documentation from separate libraries. RubstAPI provides those concerns
through one cohesive, Rack-compatible API.

- **Typed inputs:** Coerce and validate path, query, header, cookie, form, file,
  and JSON body parameters.
- **Ruby data models:** Define nested request and response schemas with
  `RubstApi::Model`.
- **Standards first:** Generate OpenAPI 3.1 and JSON Schema from application
  declarations.
- **Documentation included:** Serve Swagger UI at `/docs`, ReDoc at `/redoc`,
  and the raw schema at `/openapi.json`.
- **Dependency injection:** Compose cached dependencies and sub-dependencies,
  with per-application overrides for testing.
- **Integrated security:** Describe HTTP Basic, Bearer, OAuth2 password bearer,
  and API keys in headers, queries, or cookies.
- **Rack compatible:** Mount RubstAPI beside existing Ruby and Rack
  applications.
- **Focused operational footprint:** Runtime dependencies are limited to Rack,
  Rackup, and WEBrick for the framework's HTTP interface and bundled CLI.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Parameters and validation](#parameters-and-validation)
- [Models](#models)
- [Dependency injection](#dependency-injection)
- [Security](#security)
- [Routers](#routers)
- [Responses and background tasks](#responses-and-background-tasks)
- [Middleware](#middleware)
- [OpenAPI and API documentation](#openapi-and-api-documentation)
- [Testing](#testing)
- [Running with Docker](#running-with-docker)
- [FastAPI and RubstAPI](#fastapi-and-rubstapi)
- [Project status](#project-status)
- [Development](#development)
- [Contributing](#contributing)
- [Security](#security-policy)
- [License](#license)

## Requirements

- Ruby 3.2 or newer
- A Rack-compatible server for serving HTTP

The built-in `rubst_api run` and `rubst_api dev` commands use Rackup and
WEBrick. Add these server dependencies to your application:

```ruby
gem "rubst_api"
gem "rack", ">= 3.0"
gem "rackup", ">= 2.0"
gem "webrick", ">= 1.8"
```

## Installation

Add RubstAPI to your bundle:

```console
bundle add rubst_api
```

Or add it manually to your `Gemfile`:

```ruby
gem "rubst_api"
```

Then run:

```console
bundle install
```

For local development before a RubyGems release, reference the checkout:

```ruby
gem "rubst_api", path: "../RubstApi"
```

## Quick start

Create `app.rb`:

```ruby
require "rubst_api"

class Product < RubstApi::Model
  field :name, String, min_length: 2, max_length: 100
  field :price, Float, gt: 0
  field :tags, { array: String }, default: []
end

APP = RubstApi::App.new(
  title: "Products API",
  description: "A typed REST API built with Ruby and RubstAPI.",
  version: "1.0.0"
)

APP.get("/") do
  { name: "Products API", docs: "/docs" }
end

APP.get("/products/{product_id}", params: {
  product_id: RubstApi.Path(Integer, ge: 1),
  search: RubstApi.Query(String, required: false, max_length: 50)
}) do |product_id:, search:|
  { product_id:, search: }
end

APP.post("/products", params: {
  product: RubstApi.Body(Product)
}, response_model: Product, status_code: 201) do |product:|
  product
end
```

Run it:

```console
bundle exec rubst_api run app.rb --host 0.0.0.0 --port 8000
```

Open:

| URL | Purpose |
| --- | --- |
| `http://localhost:8000/docs` | Interactive Swagger UI |
| `http://localhost:8000/redoc` | ReDoc API reference |
| `http://localhost:8000/openapi.json` | OpenAPI 3.1 document |

Test the endpoint:

```console
curl -X POST http://localhost:8000/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Mechanical Keyboard","price":129.0,"tags":["hardware"]}'
```

Invalid input receives a structured `422 Unprocessable Entity` response:

```json
{
  "detail": [
    {
      "type": "greater_than",
      "loc": ["body", "product", "price"],
      "msg": "Value must be greater than 0",
      "input": -1
    }
  ]
}
```

## Parameters and validation

Declare where every input comes from:

```ruby
APP.put("/accounts/{account_id}", params: {
  account_id: RubstApi.Path(Integer, ge: 1),
  verbose: RubstApi.Query(:boolean, default: false),
  request_id: RubstApi.Header(String, alias: "x-request-id"),
  session: RubstApi.Cookie(String, required: false),
  account: RubstApi.Body(Account)
}) do |account_id:, verbose:, request_id:, session:, account:|
  # All values are extracted, coerced, and validated before this block runs.
end
```

| Declaration | Request source |
| --- | --- |
| `RubstApi.Path` | URL path segment |
| `RubstApi.Query` | Query string |
| `RubstApi.Header` | HTTP header |
| `RubstApi.Cookie` | Cookie |
| `RubstApi.Body` | JSON request body |
| `RubstApi.Form` | URL-encoded form |
| `RubstApi.File` | Multipart upload |

Supported constraints include:

- `min_length` and `max_length`
- `gt`, `ge`, `lt`, and `le`
- `pattern` or `regex`
- `enum`
- `nullable`
- `required`
- `default`
- `alias`

Common Ruby types such as `String`, `Integer`, `Float`, `Numeric`, `Hash`,
`Array`, `Date`, `Time`, and boolean values are coerced automatically.

## Models

Models validate nested input and generate JSON Schema:

```ruby
class Address < RubstApi::Model
  field :city, String, min_length: 1
  field :postal_code, String, pattern: /\A[0-9A-Z -]+\z/i
end

class Customer < RubstApi::Model
  field :name, String
  field :address, Address
  field :email, [String, NilClass], default: nil
end
```

Type notation:

| Shape | Declaration |
| --- | --- |
| Array of strings | `{ array: String }` |
| Array of models | `{ array: Customer }` |
| Union | `[String, Integer]` |
| Nullable string | `[String, NilClass]` |

Serialize a model with `model_dump`:

```ruby
customer.model_dump(exclude_none: true)
customer.model_dump(by_alias: true)
customer.to_json
```

## Dependency injection

Dependencies are ordinary Ruby callables:

```ruby
def database
  Database.connect
end

database_dependency = RubstApi.Depends(method(:database))

APP.get("/reports", params: {
  db: database_dependency
}) do |db:|
  db.reports
end
```

Dependencies are cached once per request by default. They can also depend on
other dependencies:

```ruby
database_dependency = RubstApi.Depends(method(:database))

current_user_dependency = RubstApi.Depends(
  method(:current_user),
  dependencies: { db: database_dependency }
)
```

Override dependencies during tests:

```ruby
APP.dependency_overrides[method(:database)] = -> { FakeDatabase.new }
```

Enumerator-based dependencies can yield a value and perform cleanup after the
request, which is useful for database sessions and other scoped resources.

## Security

Security helpers both authenticate requests and populate the OpenAPI security
schema.

### Bearer authentication

```ruby
bearer = RubstApi::Security::HTTPBearer.new

APP.get("/me", params: {
  credentials: RubstApi.Security(bearer)
}) do |credentials:|
  { token: credentials.credentials }
end
```

### OAuth2 password bearer

```ruby
oauth2 = RubstApi::Security::OAuth2PasswordBearer.new(
  token_url: "/token",
  scopes: { "items:read" => "Read items" }
)

APP.get("/items", params: {
  token: RubstApi.Security(oauth2, scopes: ["items:read"])
}) do |token:|
  { token: token }
end
```

Available helpers:

- `HTTPBasic`
- `HTTPBearer`
- `OAuth2PasswordBearer`
- `APIKeyHeader`
- `APIKeyQuery`
- `APIKeyCookie`

Authentication policy, token issuance, password hashing, and database access
remain application concerns.

## Routers

Split larger APIs into focused routers:

```ruby
users = RubstApi::APIRouter.new(prefix: "/users", tags: ["users"])

users.get("/{user_id}", params: {
  user_id: RubstApi.Path(Integer)
}) do |user_id:|
  { user_id: user_id }
end

APP.include_router(users, prefix: "/v1")
```

RubstAPI supports `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `HEAD`,
and `TRACE` routes.

## Responses and background tasks

Return ordinary Ruby objects for automatic JSON serialization, or return an
explicit response:

```ruby
APP.get("/redirect") do
  RubstApi::RedirectResponse.new("/docs")
end

APP.get("/download") do
  RubstApi::FileResponse.new("report.csv", filename: "report.csv")
end
```

Available response classes:

- `JSONResponse`
- `HTMLResponse`
- `PlainTextResponse`
- `RedirectResponse`
- `StreamingResponse`
- `FileResponse`
- `EventSourceResponse` for server-sent events

Schedule in-process work after a response:

```ruby
APP.post("/notifications") do |background_tasks:|
  background_tasks.add_task(method(:deliver_notification), "user-123")
  { queued: true }
end
```

For durable, retryable, or distributed jobs, use a dedicated Ruby job system.

## Middleware

Add middleware with explicit options:

```ruby
APP.add_middleware(
  RubstApi::Middleware::CORSMiddleware,
  allow_origins: ["https://example.com"],
  allow_methods: %w[GET POST],
  allow_headers: ["authorization", "content-type"]
)

APP.add_middleware(
  RubstApi::Middleware::GZipMiddleware,
  minimum_size: 500
)
```

Included middleware:

- CORS
- GZip
- Trusted Host
- HTTPS Redirect

Any compatible Rack middleware can wrap a RubstAPI application.

## OpenAPI and API documentation

RubstAPI follows the same standards-first philosophy popularized by Python
FastAPI: route declarations, request parameters, bodies, response models, and
security requirements produce an OpenAPI document automatically.

Configure documentation endpoints when creating the app:

```ruby
APP = RubstApi::App.new(
  title: "Billing API",
  version: "2.1.0",
  openapi_url: "/openapi.json",
  docs_url: "/docs",
  redoc_url: "/redoc",
  openapi_tags: [
    { name: "invoices", description: "Invoice operations" }
  ]
)
```

Set any documentation URL to `nil` to disable that endpoint.

## Testing

The in-process test client does not require a running web server:

```ruby
require "minitest/autorun"
require "rubst_api"

class ProductsApiTest < Minitest::Test
  def test_get_product
    client = RubstApi::TestClient.new(APP)
    response = client.get("/products/42")

    assert_equal 200, response.status
    assert_equal 42, response.json.fetch("product_id")
  end

  def test_invalid_product
    client = RubstApi::TestClient.new(APP)
    response = client.post(
      "/products",
      json: { name: "x", price: -10 }
    )

    assert_equal 422, response.status
  end
end
```

Supported test requests include `GET`, `POST`, `PUT`, `PATCH`, `DELETE`,
`OPTIONS`, and `HEAD`, with query parameters, JSON, form data, headers, and
cookies.

## Running with Docker

```dockerfile
FROM ruby:4.0-slim

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 8000
CMD ["bundle", "exec", "rubst_api", "run", "app.rb", "--host", "0.0.0.0", "--port", "8000"]
```

Example Compose service:

```yaml
services:
  api:
    build: .
    ports:
      - "8000:8000"
    healthcheck:
      test:
        - CMD
        - ruby
        - -rnet/http
        - -e
        - 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:8000/health")).is_a?(Net::HTTPSuccess) ? 0 : 1)'
      interval: 10s
      timeout: 3s
      retries: 5
```

## FastAPI and RubstAPI

[FastAPI](https://fastapi.tiangolo.com/) is a high-performance Python API
framework built on Starlette and Pydantic. RubstAPI adapts several of its core
ideas to Ruby:

| Python FastAPI concept | RubstAPI equivalent |
| --- | --- |
| ASGI application | Rack-compatible callable |
| Python type annotations | Explicit `params:` declarations |
| Pydantic `BaseModel` | `RubstApi::Model` |
| `Depends()` | `RubstApi.Depends` |
| `Security()` | `RubstApi.Security` |
| `APIRouter` | `RubstApi::APIRouter` |
| Starlette responses | `RubstApi::*Response` |
| HTTPX test client | `RubstApi::TestClient` |
| Uvicorn command | `rubst_api run` |

RubstAPI does not include or emulate Python, ASGI, Starlette, Pydantic, Uvicorn,
or FastAPI Cloud. Existing FastAPI Python applications must be translated to
Ruby declarations and Rack integrations.

The FastAPI name and trademark belong to their respective owner. See the
[official FastAPI documentation](https://fastapi.tiangolo.com/) and
[FastAPI source repository](https://github.com/fastapi/fastapi) for the Python
project.

## Project status

RubstAPI is an early-stage framework. Its public API covers the central request,
validation, routing, dependency, security, response, middleware, documentation,
and testing workflows described above. Before adopting it for critical
production systems, evaluate the current release against your performance,
security, concurrency, observability, and deployment requirements.

RubstAPI uses the `RubstApi` namespace and the `require "rubst_api"` entry
point exclusively. It does not define a `FastAPI` Ruby constant or provide a
`require "fast_api"` compatibility loader.

## Development

Install dependencies and run the complete test suite:

```console
bundle install
bundle exec rake test
```

Build the gem:

```console
gem build rubst_api.gemspec
```

The project uses Minitest. New functionality should include success, validation,
error, and OpenAPI coverage where applicable.

## Contributing

Bug reports, documentation improvements, tests, and focused pull requests are
welcome.

1. Fork the repository.
2. Create a descriptive branch.
3. Add tests for behavioral changes.
4. Run `bundle exec rake test`.
5. Update user-facing documentation.
6. Open a pull request explaining the problem and solution.

Please keep changes focused, preserve backward compatibility when practical,
and avoid claiming compatibility that is not covered by tests.

## Security policy

Do not disclose suspected vulnerabilities in a public issue. Follow the private
reporting instructions in [SECURITY.md](SECURITY.md).

## License

RubstAPI is available under the [MIT License](LICENSE).

RubstAPI is inspired by the Python FastAPI project. FastAPI's original MIT
license and copyright notice are preserved verbatim in
[LICENSES/FASTAPI-MIT.txt](LICENSES/FASTAPI-MIT.txt) and summarized in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). These files are included in
the published gem.
