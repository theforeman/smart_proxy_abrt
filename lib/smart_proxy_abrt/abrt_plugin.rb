require 'smart_proxy_abrt/abrt_version'

module AbrtProxy
  class Plugin < ::Proxy::Plugin
    plugin :abrt, AbrtProxy::VERSION

    http_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))
    https_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))

    default_settings :spooldir => "/var/spool/foreman-proxy-abrt",
                     :aggregate_reports => false,
                     :server_ssl_noverify => false
  end
end
