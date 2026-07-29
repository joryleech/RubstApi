# frozen_string_literal: true

module RubstApi
  class HTTPException < StandardError
    attr_reader :status_code, :detail, :headers

    def initialize(status_code:, detail: nil, headers: {})
      @status_code = status_code
      @detail = detail || default_detail(status_code)
      @headers = headers
      super(@detail.to_s)
    end

    private

    def default_detail(code)
      { 400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden",
        404 => "Not Found", 405 => "Method Not Allowed", 409 => "Conflict",
        422 => "Unprocessable Entity", 500 => "Internal Server Error" }[code] || "HTTP Error"
    end
  end

  class WebSocketException < StandardError
    attr_reader :code, :reason
    def initialize(code:, reason: nil)
      @code, @reason = code, reason
      super(reason)
    end
  end

  class RequestValidationError < StandardError
    attr_reader :errors, :body
    def initialize(errors, body: nil)
      @errors, @body = errors, body
      super("Request validation failed")
    end
  end

  class ResponseValidationError < StandardError
    attr_reader :errors
    def initialize(errors)
      @errors = errors
      super("Response validation failed")
    end
  end
end
