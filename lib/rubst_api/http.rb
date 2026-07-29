# frozen_string_literal: true

require "json"
require "stringio"
require "uri"

module RubstApi
  class Headers
    include Enumerable
    def initialize(values = {})
      @values = values.to_h { |key, value| [key.to_s.downcase.tr("_", "-"), value.to_s] }
    end
    def [](name) = @values[name.to_s.downcase.tr("_", "-")]
    def []=(name, value)
      @values[name.to_s.downcase.tr("_", "-")] = value.to_s
    end
    def each(&) = @values.each(&)
    def to_h = @values.dup
  end

  class Request
    attr_reader :env, :path_params, :state
    def initialize(env, path_params: {})
      @env, @path_params, @state = env, path_params, {}
    end
    def method = env.fetch("REQUEST_METHOD", "GET").upcase
    def path = env.fetch("PATH_INFO", "/")
    def query_string = env.fetch("QUERY_STRING", "")
    def query_params = @query_params ||= URI.decode_www_form(query_string).each_with_object({}) { |(k, v), h| h[k] = h.key?(k) ? Array(h[k]) << v : v }
    def headers
      @headers ||= Headers.new(env.filter_map do |key, value|
        next unless key.start_with?("HTTP_") || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
        [key.sub(/\AHTTP_/, "").downcase, value]
      end.to_h)
    end
    def cookies
      @cookies ||= (headers["cookie"] || "").split(/;\s*/).filter_map { |pair| pair.split("=", 2) if pair.include?("=") }.to_h
    end
    def body
      @body ||= begin
        io = env["rack.input"] || StringIO.new
        value = io.read
        io.rewind if io.respond_to?(:rewind)
        value
      end
    end
    def json = body.empty? ? nil : JSON.parse(body)
    def content_type = headers["content-type"]&.split(";")&.first
    def client = [env["REMOTE_ADDR"], env["REMOTE_PORT"]]
    def url = "#{env["rack.url_scheme"] || "http"}://#{env["HTTP_HOST"] || "localhost"}#{path}#{query_string.empty? ? "" : "?#{query_string}"}"
  end
end
