# frozen_string_literal: true

module RubstApi
  class StaticFiles
    MIME_TYPES = {
      ".html" => "text/html; charset=utf-8", ".css" => "text/css; charset=utf-8",
      ".js" => "application/javascript", ".json" => "application/json",
      ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
      ".svg" => "image/svg+xml", ".txt" => "text/plain; charset=utf-8"
    }.freeze

    def initialize(directory:, html: false, check_dir: true)
      @directory, @html = File.expand_path(directory), html
      raise ArgumentError, "Directory does not exist: #{directory}" if check_dir && !Dir.exist?(@directory)
    end

    def call(env)
      relative = URI.decode_www_form_component(env.fetch("PATH_INFO", "/")).sub(%r{\A/+}, "")
      path = File.expand_path(relative, @directory)
      return not_found unless path == @directory || path.start_with?("#{@directory}#{File::SEPARATOR}")
      path = File.join(path, "index.html") if @html && File.directory?(path)
      return not_found unless File.file?(path)
      FileResponse.new(path, media_type: MIME_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")).finish
    end

    private

    def not_found = PlainTextResponse.new("Not Found", status_code: 404).finish
  end
end
