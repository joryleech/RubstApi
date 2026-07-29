# frozen_string_literal: true

require "date"
require "time"
require "uri"

module RubstApi
  class ValidationError < StandardError
    attr_reader :errors
    def initialize(errors)
      @errors = errors
      super(errors.map { |e| e[:msg] }.join(", "))
    end
  end

  class Model
    Field = Data.define(:name, :type, :default, :required, :options)

    class << self
      def inherited(child)
        child.instance_variable_set(:@fields, fields.dup)
      end

      def fields = @fields ||= {}

      def field(name, type = String, default: UNDEFINED, required: nil, **options)
        required = default.equal?(UNDEFINED) if required.nil?
        fields[name.to_sym] = Field.new(name.to_sym, type, default, required, options.freeze)
        attr_reader name
      end

      def validate(value, location: [:body])
        return value if value.is_a?(self)
        unless value.is_a?(Hash)
          raise ValidationError, [{ type: "model_type", loc: location, msg: "Input should be an object", input: value }]
        end
        new(**value.transform_keys(&:to_sym))
      rescue ValidationError => e
        raise ValidationError, e.errors.map { |error| error.merge(loc: location + Array(error[:loc])) }
      end

      def json_schema(ref_template: "#/components/schemas/%s")
        required = fields.values.select(&:required).map { |field| field.name.to_s }
        {
          type: "object",
          title: name&.split("::")&.last,
          properties: fields.to_h { |name, field| [name, Schema.for(field.type, field.options)] }
        }.tap { |schema| schema[:required] = required unless required.empty? }
      end
    end

    def initialize(**attributes)
      errors = []
      self.class.fields.each_value do |field|
        value = attributes.key?(field.name) ? attributes[field.name] : field.default
        if value.equal?(UNDEFINED)
          errors << { type: "missing", loc: [field.name], msg: "Field required", input: attributes }
          next
        end
        begin
          instance_variable_set(:"@#{field.name}", Validator.coerce(value, field.type, field.options))
        rescue ValidationError => e
          errors.concat(e.errors.map { |error| error.merge(loc: [field.name] + Array(error[:loc])) })
        end
      end
      raise ValidationError, errors unless errors.empty?
      freeze
    end

    def model_dump(exclude_none: false, by_alias: false)
      self.class.fields.each_with_object({}) do |(name, field), output|
        value = public_send(name)
        next if exclude_none && value.nil?
        key = by_alias && field.options[:alias] ? field.options[:alias] : name
        output[key] = Serializer.dump(value)
      end
    end
    alias to_h model_dump

    def to_json(*) = JSON.generate(model_dump)
    def ==(other) = other.instance_of?(self.class) && other.model_dump == model_dump
  end

  module Validator
    module_function

    def coerce(value, type, constraints = {})
      return nil if value.nil? && nullable?(type, constraints)
      result =
        if type.is_a?(Array)
          validate_union(value, type, constraints)
        elsif type.is_a?(Hash) && type.key?(:array)
          Array(value).map { |item| coerce(item, type[:array], {}) }
        elsif type.is_a?(Class) && type <= Model
          type.validate(value, location: [])
        elsif type == String then String(value)
        elsif type == Integer then Integer(value, exception: true)
        elsif type == Float then Float(value)
        elsif type == Numeric then Float(value)
        elsif type == TrueClass || type == FalseClass || type == :boolean then boolean(value)
        elsif type == Symbol then value.to_sym
        elsif type == Date then Date.parse(value.to_s)
        elsif type == Time || type == DateTime then Time.parse(value.to_s)
        elsif type == URI then URI.parse(value.to_s)
        elsif type == Array then Array(value)
        elsif type == Hash then Hash(value)
        elsif type.respond_to?(:call) && !type.is_a?(Class) then type.call(value)
        elsif value.is_a?(type) then value
        else raise TypeError, "expected #{type}"
        end
      constrain(result, constraints)
    rescue ValidationError
      raise
    rescue StandardError
      raise ValidationError, [{ type: type_name(type), loc: [], msg: "Input should be a valid #{type_name(type)}", input: value }]
    end

    def nullable?(type, constraints) = constraints[:nullable] || (type.is_a?(Array) && type.include?(NilClass))

    def validate_union(value, types, constraints)
      return nil if value.nil? && types.include?(NilClass)
      failures = []
      types.reject { |type| type == NilClass }.each do |type|
        return coerce(value, type, constraints)
      rescue ValidationError => e
        failures.concat(e.errors)
      end
      raise ValidationError, failures
    end

    def boolean(value)
      return value if value == true || value == false
      return true if %w[1 true on yes].include?(value.to_s.downcase)
      return false if %w[0 false off no].include?(value.to_s.downcase)
      raise TypeError
    end

    def constrain(value, options)
      length = value.respond_to?(:length) ? value.length : nil
      fail_constraint(value, "string_too_short", "Value is too short") if options[:min_length] && length && length < options[:min_length]
      fail_constraint(value, "string_too_long", "Value is too long") if options[:max_length] && length && length > options[:max_length]
      fail_constraint(value, "greater_than", "Value must be greater than #{options[:gt]}") if options[:gt] && !(value > options[:gt])
      fail_constraint(value, "greater_than_equal", "Value must be greater than or equal to #{options[:ge]}") if options[:ge] && !(value >= options[:ge])
      fail_constraint(value, "less_than", "Value must be less than #{options[:lt]}") if options[:lt] && !(value < options[:lt])
      fail_constraint(value, "less_than_equal", "Value must be less than or equal to #{options[:le]}") if options[:le] && !(value <= options[:le])
      pattern = options[:pattern] || options[:regex]
      fail_constraint(value, "string_pattern_mismatch", "Value does not match pattern") if pattern && !(Regexp.new(pattern.to_s) =~ value.to_s)
      fail_constraint(value, "enum", "Value is not an allowed option") if options[:enum] && !options[:enum].include?(value)
      value
    end

    def fail_constraint(value, type, message)
      raise ValidationError, [{ type:, loc: [], msg: message, input: value }]
    end

    def type_name(type)
      { Integer => "integer", Float => "number", String => "string", TrueClass => "boolean",
        FalseClass => "boolean", Hash => "object", Array => "array" }[type] || type.to_s.downcase
    end
  end

  module Serializer
    module_function
    def dump(value)
      case value
      when Model then value.model_dump.transform_values { |item| dump(item) }
      when Hash then value.to_h { |key, item| [key, dump(item)] }
      when Array then value.map { |item| dump(item) }
      when Time, Date, DateTime then value.iso8601
      when Symbol then value.to_s
      else
        value.respond_to?(:to_h) && !value.is_a?(Struct) ? value.to_h : value
      end
    end
  end

  module Schema
    module_function
    def for(type, options = {})
      schema =
        if type.is_a?(Array)
          non_nil = type.reject { |item| item == NilClass }
          non_nil.length == 1 ? self.for(non_nil.first) : { anyOf: non_nil.map { |item| self.for(item) } }
        elsif type.is_a?(Hash) && type.key?(:array) then { type: "array", items: self.for(type[:array]) }
        elsif type.is_a?(Class) && type <= Model then { "$ref": "#/components/schemas/#{type.name.split("::").last}" }
        else
          { String => { type: "string" }, Integer => { type: "integer" }, Float => { type: "number" },
            Numeric => { type: "number" }, TrueClass => { type: "boolean" }, FalseClass => { type: "boolean" },
            Array => { type: "array", items: {} }, Hash => { type: "object" },
            Date => { type: "string", format: "date" }, Time => { type: "string", format: "date-time" } }[type] || {}
        end
      schema.merge(options.slice(:title, :description, :minimum, :maximum, :min_length, :max_length, :pattern, :enum).compact)
    end
  end
end
