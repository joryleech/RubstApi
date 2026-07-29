# frozen_string_literal: true

module RubstApi
  class Dependency
    attr_reader :callable, :use_cache, :dependencies
    def initialize(callable, use_cache: true, dependencies: {})
      raise ArgumentError, "dependency must be callable" unless callable.respond_to?(:call)
      @callable, @use_cache, @dependencies = callable, use_cache, dependencies
    end
  end

  class DependencyResolver
    def initialize(request, overrides = {})
      @request, @overrides, @cache, @cleanups = request, overrides, {}, []
    end

    def resolve(dependency)
      callable = @overrides.fetch(dependency.callable, dependency.callable)
      return @cache[callable] if dependency.use_cache && @cache.key?(callable)
      signature = callable.respond_to?(:parameters) ? callable : callable.method(:call)
      arguments = dependency.dependencies.to_h { |name, child| [name, resolve(child)] }
      signature.parameters.each do |kind, name|
        next unless %i[key keyreq].include?(kind)
        arguments[name] = @request if name == :request
      end
      value = callable.call(**arguments)
      value = consume_generator(value) if value.is_a?(Enumerator)
      @cache[callable] = value if dependency.use_cache
      value
    end

    def close
      return if @closed
      @closed = true
      @cleanups.reverse_each(&:call)
    end

    private

    def consume_generator(generator)
      value = generator.next
      @cleanups << proc { generator.next rescue StopIteration }
      value
    end
  end

  class SecurityDependency < Dependency
    attr_reader :scopes
    def initialize(callable, scopes: [], **options)
      super(callable, **options)
      @scopes = scopes
    end
  end

  def self.Depends(...) = RubstApi.Depends(...)
  def self.Security(...) = RubstApi.Security(...)
end
