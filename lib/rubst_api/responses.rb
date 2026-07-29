# frozen_string_literal: true

require "json"

module RubstApi
  class Response
    attr_accessor :status_code, :body
    attr_reader :headers, :media_type
    def initialize(content = nil, status_code: 200, headers: {}, media_type: "text/plain; charset=utf-8")
      @body, @status_code, @headers, @media_type = render(content), status_code, Headers.new(headers), media_type
      @headers["content-type"] ||= media_type
    end
    def render(content) = content.nil? ? "" : content.to_s
    def set_cookie(key, value, max_age: nil, expires: nil, path: "/", domain: nil, secure: false, httponly: false, samesite: "lax")
      parts = ["#{key}=#{value}", ("Max-Age=#{max_age}" if max_age), ("Expires=#{expires.httpdate}" if expires),
               ("Path=#{path}" if path), ("Domain=#{domain}" if domain), ("Secure" if secure),
               ("HttpOnly" if httponly), ("SameSite=#{samesite.to_s.capitalize}" if samesite)].compact
      headers["set-cookie"] = parts.join("; ")
    end
    def delete_cookie(key, **options) = set_cookie(key, "", max_age: 0, expires: Time.at(0), **options)
    def finish
      payload = Array(body)
      headers["content-length"] ||= payload.sum(&:bytesize).to_s
      [status_code, headers.to_h, payload]
    end
  end

  class JSONResponse < Response
    def initialize(content = nil, **options)
      super(content, media_type: "application/json", **options)
    end
    def render(content) = JSON.generate(Serializer.dump(content))
  end

  class HTMLResponse < Response
    def initialize(content = nil, **options) = super(content, media_type: "text/html; charset=utf-8", **options)
  end
  class PlainTextResponse < Response; end
  class RedirectResponse < Response
    def initialize(url, status_code: 307, headers: {}, **)
      super("", status_code:, headers: headers.merge("location" => url))
    end
  end
  class StreamingResponse < Response
    def initialize(content, **options)
      super("", **options)
      @body = content.respond_to?(:each) ? content : [content]
    end
    def finish = [status_code, headers.to_h, body]
  end
  class FileResponse < StreamingResponse
    def initialize(path, filename: nil, media_type: "application/octet-stream", **options)
      headers = options.delete(:headers) || {}
      headers["content-disposition"] = %(attachment; filename="#{filename}") if filename
      super(File.open(path, "rb"), media_type:, headers:, **options)
    end
  end
  ORJSONResponse = JSONResponse
  UJSONResponse = JSONResponse
end
