# frozen_string_literal: true

module RubstApi
  module Middleware
    class CORSMiddleware
      def initialize(app, allow_origins: [], allow_methods: ["GET"], allow_headers: [], allow_credentials: false,
                     expose_headers: [], max_age: 600, allow_origin_regex: nil)
        @app, @origins, @methods, @headers = app, allow_origins, allow_methods, allow_headers
        @credentials, @expose, @max_age, @origin_regex = allow_credentials, expose_headers, max_age, allow_origin_regex
      end
      def call(env)
        origin = env["HTTP_ORIGIN"]
        return @app.call(env) unless origin
        allowed = @origins.include?("*") || @origins.include?(origin) || (@origin_regex && Regexp.new(@origin_regex).match?(origin))
        return @app.call(env) unless allowed
        cors = {
          "access-control-allow-origin" => @credentials ? origin : (@origins.include?("*") ? "*" : origin),
          "vary" => "Origin"
        }
        if env["REQUEST_METHOD"] == "OPTIONS" && env["HTTP_ACCESS_CONTROL_REQUEST_METHOD"]
          cors.merge!("access-control-allow-methods" => @methods.join(", "),
                      "access-control-allow-headers" => @headers.join(", "),
                      "access-control-max-age" => @max_age.to_s)
          cors["access-control-allow-credentials"] = "true" if @credentials
          [200, cors.merge("content-length" => "2"), ["OK"]]
        else
          status, headers, body = @app.call(env)
          headers.merge!(cors)
          headers["access-control-expose-headers"] = @expose.join(", ") unless @expose.empty?
          headers["access-control-allow-credentials"] = "true" if @credentials
          [status, headers, body]
        end
      end
    end

    class GZipMiddleware
      def initialize(app, minimum_size: 500, compresslevel: 9)
        @app, @minimum_size, @level = app, minimum_size, compresslevel
      end
      def call(env)
        status, headers, body = @app.call(env)
        content = body.respond_to?(:each) ? body.to_a.join : body.to_s
        return [status, headers, [content]] unless env["HTTP_ACCEPT_ENCODING"].to_s.include?("gzip") && content.bytesize >= @minimum_size
        require "zlib"
        require "stringio"
        io = StringIO.new
        writer = Zlib::GzipWriter.new(io, @level)
        writer.write(content)
        writer.close
        headers = headers.merge("content-encoding" => "gzip", "content-length" => io.string.bytesize.to_s, "vary" => "Accept-Encoding")
        [status, headers, [io.string]]
      end
    end

    class TrustedHostMiddleware
      def initialize(app, allowed_hosts: ["*"], www_redirect: true)
        @app, @hosts, @redirect = app, allowed_hosts, www_redirect
      end
      def call(env)
        host = env["HTTP_HOST"].to_s.split(":").first
        allowed = @hosts.include?("*") || @hosts.any? { |pattern| pattern.start_with?("*.") ? host.end_with?(pattern.delete_prefix("*")) : host == pattern }
        return PlainTextResponse.new("Invalid host header", status_code: 400).finish unless allowed
        @app.call(env)
      end
    end

    class HTTPSRedirectMiddleware
      def initialize(app) = @app = app
      def call(env)
        return @app.call(env) if env["rack.url_scheme"] == "https"
        host, path, query = env["HTTP_HOST"], env["PATH_INFO"], env["QUERY_STRING"]
        RedirectResponse.new("https://#{host}#{path}#{query.to_s.empty? ? "" : "?#{query}"}").finish
      end
    end
  end
end
