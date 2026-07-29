# frozen_string_literal: true

module RubstApi
  class WebSocket
    attr_reader :env, :path_params, :state
    def initialize(env, path_params: {})
      @env, @path_params, @state = env, path_params, {}
      @socket = env["rack.websocket"]
    end
    def accept(subprotocol: nil, headers: {}) = @socket&.accept(subprotocol:, headers:)
    def receive = @socket&.receive
    def receive_text = receive.to_s
    def receive_json = JSON.parse(receive_text)
    def send_text(data) = @socket&.send(data.to_s)
    def send_json(data) = send_text(JSON.generate(Serializer.dump(data)))
    def close(code: 1000, reason: nil) = @socket&.close(code, reason)
    def query_params = Request.new(env).query_params
    def headers = Request.new(env).headers
    def cookies = Request.new(env).cookies
  end
end
