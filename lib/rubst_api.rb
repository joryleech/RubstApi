# frozen_string_literal: true

require_relative "rubst_api/version"
require_relative "rubst_api/errors"
require_relative "rubst_api/params"
require_relative "rubst_api/model"
require_relative "rubst_api/http"
require_relative "rubst_api/responses"
require_relative "rubst_api/dependencies"
require_relative "rubst_api/security"
require_relative "rubst_api/routing"
require_relative "rubst_api/openapi"
require_relative "rubst_api/middleware"
require_relative "rubst_api/background_tasks"
require_relative "rubst_api/websocket"
require_relative "rubst_api/static_files"
require_relative "rubst_api/sse"
require_relative "rubst_api/status"
require_relative "rubst_api/app"
require_relative "rubst_api/test_client"

module RubstApi
  class << self
    def Query(type = String, **options) = Param.new(:query, type:, **options)
    def Path(type = String, **options) = Param.new(:path, type:, required: true, **options)
    def Header(type = String, **options) = Param.new(:header, type:, **options)
    def Cookie(type = String, **options) = Param.new(:cookie, type:, **options)
    def Body(type = Hash, **options) = Param.new(:body, type:, **options)
    def Form(type = String, **options) = Param.new(:form, type:, **options)
    def File(**options) = Param.new(:file, type: UploadFile, **options)
    def Depends(callable = nil, **options, &block) = Dependency.new(callable || block, **options)
    def Security(callable = nil, scopes: [], **options, &block)
      SecurityDependency.new(callable || block, scopes:, **options)
    end

    def jsonable_encoder(value, **)
      Serializer.dump(value)
    end
  end
end
