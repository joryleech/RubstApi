# frozen_string_literal: true

module RubstApi
  class BackgroundTask
    def initialize(callable = nil, *args, **kwargs, &block)
      @callable, @args, @kwargs = callable || block, args, kwargs
    end
    def call = @callable.call(*@args, **@kwargs)
  end

  class BackgroundTasks
    def initialize = @tasks = []
    def add_task(callable = nil, *args, **kwargs, &block)
      @tasks << BackgroundTask.new(callable, *args, **kwargs, &block)
    end
    def call = @tasks.each(&:call)
  end
end
