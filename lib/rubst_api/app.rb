# frozen_string_literal: true

module RubstApi
  class App < APIRouter
    attr_reader :title, :description, :version, :openapi_url, :docs_url, :redoc_url,
                :openapi_version, :servers, :openapi_tags, :dependency_overrides

    def initialize(title: "RubstAPI", description: nil, version: "0.1.0", openapi_url: "/openapi.json",
                   docs_url: "/docs", redoc_url: "/redoc", openapi_version: "3.1.0",
                   servers: [], openapi_tags: [], dependencies: [], **router_options)
      super(dependencies:, **router_options)
      @title, @description, @version = title, description, version
      @openapi_url, @docs_url, @redoc_url, @openapi_version = openapi_url, docs_url, redoc_url, openapi_version
      @servers, @openapi_tags, @dependency_overrides = servers, openapi_tags, {}
      @exception_handlers, @user_middleware, @startup_handlers, @shutdown_handlers = {}, [], [], []
      @mounts = []
      @openapi_schema = nil
      install_default_handlers
    end

    def call(env)
      build_stack.call(env)
    rescue StandardError => error
      handle_exception(error)
    end

    def route_request(env)
      request_path, request_method = env.fetch("PATH_INFO", "/"), env.fetch("REQUEST_METHOD", "GET").upcase
      if (mounted = @mounts.find { |prefix, _| request_path == prefix || request_path.start_with?("#{prefix}/") })
        prefix, application = mounted
        child_path = request_path.delete_prefix(prefix)
        child_env = env.merge("SCRIPT_NAME" => "#{env["SCRIPT_NAME"]}#{prefix}",
                              "PATH_INFO" => child_path.empty? ? "/" : child_path)
        return application.call(child_env)
      end
      return JSONResponse.new(openapi).finish if openapi_url && request_path == openapi_url
      return HTMLResponse.new(swagger_html).finish if docs_url && request_path == docs_url
      return HTMLResponse.new(redoc_html).finish if redoc_url && request_path == redoc_url

      path_matches = routes.filter_map { |route| [route, route.match(request_path)] if route.match(request_path) }
      raise HTTPException.new(status_code: 404) if path_matches.empty?
      route, captures = path_matches.find { |candidate, _| candidate.allowed?(request_method) }
      unless route
        allowed = path_matches.flat_map { |candidate, _| candidate.methods }.uniq.join(", ")
        raise HTTPException.new(status_code: 405, headers: { "Allow" => allowed })
      end
      request = Request.new(env, path_params: captures)
      execute_route(route, request)
    end

    def execute_route(route, request)
      resolver = DependencyResolver.new(request, dependency_overrides)
      values = {}
      errors = []
      body_parameter_count = route.params.values.count { |value| value.is_a?(Param) && value.location == :body }
      route.dependencies.each { |dependency| resolver.resolve(dependency) }
      route.params.each do |name, declaration|
        if declaration.is_a?(Dependency)
          values[name] = resolver.resolve(declaration)
          next
        end
        raw = extract_parameter(name, declaration, request, body_parameter_count:)
        if raw.equal?(UNDEFINED)
          if declaration.required?
            errors << { type: "missing", loc: [declaration.location, declaration.name_for(name)], msg: "Field required", input: nil }
          else
            values[name] = declaration.default.equal?(UNDEFINED) ? nil : declaration.default
          end
          next
        end
        begin
          values[name] = Validator.coerce(raw, declaration.type, declaration.constraints)
        rescue ValidationError => error
          errors.concat(error.errors.map { |item| item.merge(loc: [declaration.location, declaration.name_for(name)] + Array(item[:loc])) })
        end
      end
      raise RequestValidationError.new(errors, body: request.body) unless errors.empty?
      inject_special_arguments(route.endpoint, values, request)
      result = invoke(route.endpoint, values)
      response = prepare_response(result, route)
      if (injected = values[:response])
        response.status_code = injected.status_code if injected.status_code != 200
        injected.headers.each { |key, value| response.headers[key] = value }
      end
      resolver.close
      finished = response.finish
      values[:background_tasks]&.call
      finished
    ensure
      resolver&.close
    end

    def openapi
      @openapi_schema ||= OpenAPI.generate(self)
    end

    def add_api_route(...)
      @openapi_schema = nil
      super
    end

    def include_router(...)
      @openapi_schema = nil
      super
    end

    def add_middleware(middleware_class, **options)
      @user_middleware << [middleware_class, options]
      @middleware_stack = nil
      self
    end

    def exception_handler(exception_class, callable = nil, &block)
      @exception_handlers[exception_class] = callable || block
    end

    def on_event(event, callable = nil, &block)
      handlers = event.to_sym == :startup ? @startup_handlers : @shutdown_handlers
      handlers << (callable || block)
    end

    def startup = @startup_handlers.each(&:call)
    def shutdown = @shutdown_handlers.reverse_each(&:call)

    def mount(path, application, name: nil)
      prefix = path.end_with?("/") ? path.chomp("/") : path
      @mounts << [prefix, application]
      application
    end

    private

    def build_stack
      @middleware_stack ||= @user_middleware.reverse.inject(method(:route_request)) do |inner, (klass, options)|
        klass.new(inner, **options)
      end
    end

    def install_default_handlers
      exception_handler(HTTPException) do |error|
        JSONResponse.new({ detail: error.detail }, status_code: error.status_code, headers: error.headers)
      end
      exception_handler(RequestValidationError) do |error|
        JSONResponse.new({ detail: error.errors }, status_code: 422)
      end
      exception_handler(ResponseValidationError) do |error|
        JSONResponse.new({ detail: error.errors }, status_code: 500)
      end
    end

    def handle_exception(error)
      pair = @exception_handlers.find { |klass, _| error.is_a?(klass) }
      raise error unless pair
      response = pair.last.call(error)
      response = JSONResponse.new(response) unless response.is_a?(Response)
      response.finish
    end

    def extract_parameter(name, param, request, body_parameter_count: 0)
      key = param.name_for(name)
      value = case param.location
              when :path then request.path_params[key]
              when :query then request.query_params[key]
              when :header then request.headers[key.tr("_", "-")]
              when :cookie then request.cookies[key]
              when :body then extract_body(name, param, request, embedded: body_parameter_count > 1)
              when :form then form_data(request)[key]
              when :file then multipart_data(request)[key]
              end
      value.nil? ? UNDEFINED : value
    end

    def extract_body(name, param, request, embedded: false)
      parsed = request.json
      return parsed unless embedded && parsed.is_a?(Hash)
      parsed.fetch(param.name_for(name)) { parsed.fetch(param.name_for(name).to_sym, UNDEFINED) }
    rescue JSON::ParserError
      raise RequestValidationError.new([{ type: "json_invalid", loc: [:body], msg: "JSON decode error", input: request.body }])
    end

    def route_like_model?(type) = type.is_a?(Class) && type <= Model

    def form_data(request)
      @form_cache ||= {}
      @form_cache[request.object_id] ||= URI.decode_www_form(request.body).to_h
    end

    def multipart_data(request)
      boundary = request.headers["content-type"].to_s[/boundary=(?:"([^"]+)"|([^;]+))/, 1] ||
                 request.headers["content-type"].to_s[/boundary=(?:"([^"]+)"|([^;]+))/, 2]
      return {} unless boundary
      request.body.split("--#{boundary}").each_with_object({}) do |part, output|
        head, content = part.split("\r\n\r\n", 2)
        next unless head && content
        name = head[/name="([^"]+)"/, 1]
        next unless name
        content = content.sub(/\r\n\z/, "")
        filename = head[/filename="([^"]*)"/, 1]
        output[name] = filename ? UploadFile.new(filename:, io: StringIO.new(content),
                                                 content_type: head[/Content-Type:\s*([^\r\n]+)/i, 1] || "application/octet-stream") : content
      end
    end

    def inject_special_arguments(callable, values, request)
      names = callable.parameters.map(&:last)
      values[:request] = request if names.include?(:request) && !values.key?(:request)
      values[:response] = Response.new if names.include?(:response) && !values.key?(:response)
      values[:background_tasks] = BackgroundTasks.new if names.include?(:background_tasks) && !values.key?(:background_tasks)
      values[:websocket] = WebSocket.new(request.env, path_params: request.path_params) if names.include?(:websocket) && !values.key?(:websocket)
    end

    def invoke(callable, values)
      parameters = callable.parameters
      if parameters.any? { |kind, _| %i[key keyreq keyrest].include?(kind) }
        callable.call(**values)
      elsif parameters.empty?
        callable.call
      else
        callable.call(*parameters.map { |_, name| values[name] })
      end
    end

    def prepare_response(result, route)
      return result if result.is_a?(Response)
      if route.response_model
        begin
          result = Validator.coerce(result, route.response_model, {})
        rescue ValidationError => error
          raise ResponseValidationError, error.errors
        end
      end
      JSONResponse.new(result, status_code: route.status_code)
    end

    def swagger_html
      <<~HTML
        <!doctype html><html><head><title>#{title} - Swagger UI</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css"></head>
        <body><div id="swagger-ui"></div><script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
        <script>SwaggerUIBundle({url: #{openapi_url.to_json}, dom_id: '#swagger-ui', deepLinking: true})</script></body></html>
      HTML
    end

    def redoc_html
      <<~HTML
        <!doctype html><html><head><title>#{title} - ReDoc</title></head>
        <body><redoc spec-url="#{openapi_url}"></redoc>
        <script src="https://cdn.jsdelivr.net/npm/redoc@2/bundles/redoc.standalone.js"></script></body></html>
      HTML
    end
  end

end
