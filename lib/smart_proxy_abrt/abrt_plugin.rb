require 'smart_proxy_abrt/abrt_version'

module Proxy::Abrt
  class Plugin < ::Proxy::Plugin
    plugin :abrt, Proxy::Abrt::VERSION

    http_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))
    https_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))

    #default settings
  end
end
