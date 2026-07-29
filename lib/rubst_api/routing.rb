# frozen_string_literal: true

module RubstApi
  class Route
    attr_reader :path, :methods, :endpoint, :params, :response_model, :status_code,
                :tags, :summary, :description, :operation_id, :deprecated,
                :include_in_schema, :responses, :dependencies, :name

    def initialize(path, endpoint:, methods:, params: {}, response_model: nil, status_code: 200,
                   tags: [], summary: nil, description: nil, operation_id: nil, deprecated: false,
                   include_in_schema: true, responses: {}, dependencies: [], name: nil, **)
      @path, @endpoint, @methods, @params = normalize_path(path), endpoint, Array(methods).map { |m| m.to_s.upcase }, params
      @response_model, @status_code, @tags = response_model, status_code, tags
      @summary, @description, @operation_id = summary, description, operation_id
      @deprecated, @include_in_schema, @responses = deprecated, include_in_schema, responses
      @dependencies, @name = dependencies, name
      @regexp, @path_names = compile(@path)
    end

    def match(request_path)
      match = @regexp.match(request_path)
      match&.named_captures || nil
    end

    def allowed?(method) = methods.include?(method) || (method == "HEAD" && methods.include?("GET"))

    def unique_id
      operation_id || "#{name || endpoint_name}_#{path.gsub(/\W+/, "_")}_#{methods.first.downcase}".gsub(/\A_|_\z/, "")
    end

    private

    def normalize_path(path) = path.start_with?("/") ? path : "/#{path}"
    def endpoint_name = endpoint.respond_to?(:name) && endpoint.name ? endpoint.name : "operation"
    def compile(path)
      names = path.scan(/\{([a-zA-Z_]\w*)\}/).flatten
      source = Regexp.escape(path).gsub(/\\\{([a-zA-Z_]\w*)\\\}/, '(?<\1>[^/]+)')
      [Regexp.new("\\A#{source}/?\\z"), names]
    end
  end

  class APIRouter
    HTTP_METHODS = %i[get post put patch delete options head trace].freeze
    attr_reader :routes, :prefix, :tags, :dependencies

    def initialize(prefix: "", tags: [], dependencies: [], **defaults)
      @prefix, @tags, @dependencies, @defaults = prefix, tags, dependencies, defaults
      @routes = []
    end

    HTTP_METHODS.each do |method|
      define_method(method) do |path, endpoint = nil, **options, &block|
        add_api_route(path, endpoint || block, methods: [method], **options)
      end
    end

    def api_route(path, methods: ["GET"], **options, &block)
      add_api_route(path, block, methods:, **options)
    end

    def add_api_route(path, endpoint = nil, methods: ["GET"], **options, &block)
      callable = endpoint || block
      raise ArgumentError, "an endpoint block or callable is required" unless callable.respond_to?(:call)
      route = Route.new("#{prefix}#{path}", endpoint: callable, methods:,
                        tags: tags + Array(options.delete(:tags)),
                        dependencies: dependencies + Array(options.delete(:dependencies)),
                        **@defaults, **options)
      routes << route
      route
    end

    def include_router(router, prefix: "", tags: [], dependencies: [])
      router.routes.each do |route|
        routes << Route.new("#{prefix}#{route.path}", endpoint: route.endpoint, methods: route.methods,
                            params: route.params, response_model: route.response_model,
                            status_code: route.status_code, tags: tags + route.tags,
                            summary: route.summary, description: route.description,
                            operation_id: route.operation_id, deprecated: route.deprecated,
                            include_in_schema: route.include_in_schema, responses: route.responses,
                            dependencies: dependencies + route.dependencies, name: route.name)
      end
      self
    end

    def websocket(path, endpoint = nil, **options, &block)
      add_api_route(path, endpoint || block, methods: ["WEBSOCKET"], include_in_schema: false, **options)
    end
  end
end
