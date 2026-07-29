# frozen_string_literal: true

module RubstApi
  ServerSentEvent = Data.define(:data, :event, :id, :retry, :comment) do
    def encode
      lines = []
      lines << ": #{comment}" if comment
      lines << "id: #{id}" if id
      lines << "event: #{event}" if event
      lines << "retry: #{self.retry}" if self.retry
      payload = data.is_a?(String) ? data : JSON.generate(Serializer.dump(data))
      payload.each_line { |line| lines << "data: #{line.chomp}" }
      "#{lines.join("\n")}\n\n"
    end
  end

  class EventSourceResponse < StreamingResponse
    def initialize(content, ping: 15, **options)
      stream = Enumerator.new do |output|
        content.each do |event|
          event = ServerSentEvent.new(event, nil, nil, nil, nil) unless event.is_a?(ServerSentEvent)
          output << event.encode
        end
      end
      super(stream, media_type: "text/event-stream", headers: { "cache-control" => "no-cache" }, **options)
    end
  end
end
