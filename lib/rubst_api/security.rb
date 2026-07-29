# frozen_string_literal: true

require "base64"

module RubstApi
  module Security
    HTTPAuthorizationCredentials = Data.define(:scheme, :credentials)
    HTTPBasicCredentials = Data.define(:username, :password)
    SecurityScopes = Data.define(:scopes) do
      def scope_str = scopes.join(" ")
    end

    class Base
      attr_reader :scheme_name, :description, :auto_error
      def initialize(scheme_name: nil, description: nil, auto_error: true)
        @scheme_name = scheme_name || self.class.name.split("::").last
        @description, @auto_error = description, auto_error
      end
      def fail_auth(detail = "Not authenticated")
        raise HTTPException.new(status_code: 401, detail:, headers: { "WWW-Authenticate" => scheme_name })
      end
    end

    class HTTPBearer < Base
      def call(request:)
        scheme, credentials = request.headers["authorization"]&.split(" ", 2)
        return fail_auth unless scheme&.casecmp?("Bearer") && credentials
        HTTPAuthorizationCredentials.new(scheme, credentials)
      rescue HTTPException
        raise if auto_error
        nil
      end
      def openapi_scheme = { type: "http", scheme: "bearer", description: description }.compact
    end

    class HTTPBasic < Base
      def call(request:)
        scheme, credentials = request.headers["authorization"]&.split(" ", 2)
        return fail_auth unless scheme&.casecmp?("Basic") && credentials
        username, password = Base64.strict_decode64(credentials).split(":", 2)
        HTTPBasicCredentials.new(username, password)
      rescue StandardError
        raise if auto_error
        nil
      end
      def openapi_scheme = { type: "http", scheme: "basic", description: description }.compact
    end

    class APIKeyHeader < Base
      def initialize(name:, **options) = (@name = name; super(**options))
      def call(request:)
        request.headers[@name] || (auto_error ? fail_auth("Not authenticated") : nil)
      end
      def openapi_scheme = { type: "apiKey", in: "header", name: @name, description: description }.compact
    end

    class APIKeyQuery < Base
      def initialize(name:, **options) = (@name = name; super(**options))
      def call(request:)
        request.query_params[@name] || (auto_error ? fail_auth("Not authenticated") : nil)
      end
      def openapi_scheme = { type: "apiKey", in: "query", name: @name, description: description }.compact
    end

    class APIKeyCookie < Base
      def initialize(name:, **options) = (@name = name; super(**options))
      def call(request:)
        request.cookies[@name] || (auto_error ? fail_auth("Not authenticated") : nil)
      end
      def openapi_scheme = { type: "apiKey", in: "cookie", name: @name, description: description }.compact
    end

    class OAuth2PasswordBearer < HTTPBearer
      attr_reader :token_url, :scopes
      def initialize(token_url:, scopes: {}, **options)
        @token_url, @scopes = token_url, scopes
        super(**options)
      end
      def call(request:) = super.credentials
      def openapi_scheme
        { type: "oauth2", flows: { password: { tokenUrl: token_url, scopes: scopes } }, description: description }.compact
      end
    end
  end
end
