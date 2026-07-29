# frozen_string_literal: true

module RubstApi
  UNDEFINED = Object.new.freeze

  class Param
    attr_reader :location, :type, :default, :alias_name, :title, :description,
                :examples, :deprecated, :include_in_schema, :constraints

    def initialize(location, type: String, default: UNDEFINED, required: nil,
                   alias_name: nil, alias: nil, title: nil, description: nil,
                   examples: nil, deprecated: false, include_in_schema: true, **constraints)
      @location, @type, @default = location, type, default
      @required = required.nil? ? default.equal?(UNDEFINED) : required
      @alias_name = alias_name || binding.local_variable_get(:alias)
      @title, @description, @examples = title, description, examples
      @deprecated, @include_in_schema = deprecated, include_in_schema
      @constraints = constraints
    end

    def required? = @required
    def name_for(name) = (alias_name || name).to_s
  end

  def self.Query(...) = RubstApi.Query(...)
  def self.Path(...) = RubstApi.Path(...)
  def self.Header(...) = RubstApi.Header(...)
  def self.Cookie(...) = RubstApi.Cookie(...)
  def self.Body(...) = RubstApi.Body(...)
  def self.Form(...) = RubstApi.Form(...)
  def self.File(...) = RubstApi.File(...)

  class UploadFile
    attr_reader :filename, :content_type, :headers, :io
    def initialize(filename:, io:, content_type: "application/octet-stream", headers: {})
      @filename, @io, @content_type, @headers = filename, io, content_type, headers
    end
    def read(...) = io.read(...)
    def rewind = io.rewind
    def close = io.close
    def size = io.size
  end
end
