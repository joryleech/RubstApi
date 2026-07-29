# frozen_string_literal: true

module RubstApi
  module OpenAPI
    module_function

    def generate(app)
      schemas = {}
      security_schemes = {}
      paths = {}
      app.routes.select(&:include_in_schema).each do |route|
        operation = {
          tags: route.tags.empty? ? nil : route.tags,
          summary: route.summary || humanize(route.name || route.unique_id),
          description: route.description,
          operationId: route.unique_id,
          deprecated: route.deprecated ? true : nil,
          parameters: parameters_for(route, schemas),
          responses: responses_for(route, schemas)
        }.compact
        security = security_for(route, security_schemes)
        operation[:security] = security unless security.empty?
        body = request_body_for(route, schemas)
        operation[:requestBody] = body if body
        route.methods.each do |method|
          (paths[route.path] ||= {})[method.downcase.to_sym] = operation
        end
      end
      {
        openapi: app.openapi_version,
        info: { title: app.title, version: app.version, description: app.description }.compact,
        servers: app.servers.empty? ? nil : app.servers,
        paths:,
        components: {
          schemas: schemas.empty? ? nil : schemas,
          securitySchemes: security_schemes.empty? ? nil : security_schemes
        }.compact,
        tags: app.openapi_tags.empty? ? nil : app.openapi_tags
      }.compact
    end

    def security_for(route, schemes)
      (route.dependencies + route.params.values.grep(Dependency)).filter_map do |dependency|
        callable = dependency.callable
        next unless callable.respond_to?(:openapi_scheme)
        name = callable.scheme_name
        schemes[name] ||= callable.openapi_scheme
        { name => dependency.is_a?(SecurityDependency) ? dependency.scopes : [] }
      end
    end

    def parameters_for(route, schemas)
      route.params.filter_map do |name, param|
        next if param.is_a?(Dependency)
        next if param.location == :body || param.location == :form || param.location == :file || !param.include_in_schema
        collect_schema(param.type, schemas)
        {
          name: param.name_for(name), in: param.location.to_s, required: param.required?,
          description: param.description, deprecated: param.deprecated,
          schema: Schema.for(param.type, param.constraints)
        }.compact
      end
    end

    def request_body_for(route, schemas)
      body_params = route.params.select { |_, param| param.is_a?(Param) && %i[body form file].include?(param.location) }
      return if body_params.empty?
      body_params.each_value { |param| collect_schema(param.type, schemas) }
      media_type = body_params.values.any? { |param| param.location == :file } ? "multipart/form-data" :
                   body_params.values.any? { |param| param.location == :form } ? "application/x-www-form-urlencoded" : "application/json"
      schema = if body_params.length == 1
                 Schema.for(body_params.values.first.type)
               else
                 { type: "object", properties: body_params.to_h { |name, param| [name, Schema.for(param.type)] },
                   required: body_params.select { |_, param| param.required? }.keys }
               end
      { required: body_params.values.any?(&:required?), content: { media_type => { schema: } } }
    end

    def responses_for(route, schemas)
      schema = route.response_model ? Schema.for(route.response_model) : {}
      collect_schema(route.response_model, schemas) if route.response_model
      output = { route.status_code.to_s => { description: status_description(route.status_code),
                                             content: { "application/json" => { schema: } } } }
      output["422"] = { description: "Validation Error", content: { "application/json" => {
        schema: { "$ref": "#/components/schemas/HTTPValidationError" }
      } } } unless route.params.empty?
      route.responses.each { |code, definition| output[code.to_s] = definition }
      output
    end

    def collect_schema(type, schemas)
      if type.is_a?(Class) && type <= Model
        schemas[type.name.split("::").last] ||= type.json_schema
        type.fields.each_value { |field| collect_schema(field.type, schemas) }
      elsif type.is_a?(Array)
        type.each { |item| collect_schema(item, schemas) }
      elsif type.is_a?(Hash) && type[:array]
        collect_schema(type[:array], schemas)
      end
      schemas["ValidationError"] ||= {
        type: "object", properties: {
          loc: { type: "array", items: { anyOf: [{ type: "string" }, { type: "integer" }] } },
          msg: { type: "string" }, type: { type: "string" }
        }, required: %w[loc msg type]
      }
      schemas["HTTPValidationError"] ||= {
        type: "object", properties: { detail: { type: "array", items: { "$ref": "#/components/schemas/ValidationError" } } }
      }
    end

    def status_description(code)
      { 200 => "Successful Response", 201 => "Successful Response", 202 => "Successful Response",
        204 => "Successful Response", 301 => "Redirect Response", 307 => "Redirect Response" }[code] || "Response"
    end
    def humanize(value) = value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end
end
