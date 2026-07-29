# frozen_string_literal: true

module RubstApi
  class TestResponse
    attr_reader :status, :headers, :body
    def initialize(status, headers, body)
      @status, @headers = status, Headers.new(headers)
      @body = body.respond_to?(:each) ? body.to_a.join : body.to_s
      body.close if body.respond_to?(:close)
    end
    alias status_code status
    def json = JSON.parse(body)
    def text = body
    def success? = status.between?(200, 299)
  end

  class TestClient
    def initialize(app, base_url: "http://testserver")
      @app, @base_url = app, base_url
    end

    %i[get post put patch delete options head].each do |method|
      define_method(method) { |path, **options| request(method, path, **options) }
    end

    def request(method, path, params: nil, json: UNDEFINED, data: nil, headers: {}, cookies: {})
      uri = URI.join(@base_url, path)
      query = URI.decode_www_form(uri.query.to_s)
      query.concat(params.flat_map { |key, value| Array(value).map { |item| [key.to_s, item.to_s] } }) if params
      body = if !json.equal?(UNDEFINED)
               headers = { "Content-Type" => "application/json" }.merge(headers)
               JSON.generate(json)
             elsif data
               headers = { "Content-Type" => "application/x-www-form-urlencoded" }.merge(headers)
               URI.encode_www_form(data)
             else ""
             end
      headers["Cookie"] = cookies.map { |key, value| "#{key}=#{value}" }.join("; ") unless cookies.empty?
      env = {
        "REQUEST_METHOD" => method.to_s.upcase, "PATH_INFO" => uri.path,
        "QUERY_STRING" => URI.encode_www_form(query), "rack.input" => StringIO.new(body),
        "rack.url_scheme" => uri.scheme, "HTTP_HOST" => uri.host,
        "CONTENT_LENGTH" => body.bytesize.to_s
      }
      headers.each do |key, value|
        env[key.to_s.downcase == "content-type" ? "CONTENT_TYPE" : "HTTP_#{key.to_s.upcase.tr("-", "_")}"] = value
      end
      TestResponse.new(*@app.call(env))
    end
  end
end
