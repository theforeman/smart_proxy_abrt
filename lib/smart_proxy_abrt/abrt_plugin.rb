require 'smart_proxy_abrt/abrt_version'

module AbrtProxy
  class Plugin < ::Proxy::Plugin
    plugin :abrt, AbrtProxy::VERSION

    https_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))

    default_settings :spooldir => "/var/spool/foreman-proxy-abrt",
                     :aggregate_reports => false,
                     :server_ssl_noverify => false

    after_activation do
      if settings.server_url && !settings.server_url.to_s.empty?
        check_file(:server_ssl_cert)
        check_file(:server_ssl_key)
      end
    end

    def check_file(conf_sym)
      path = settings.send(conf_sym)
      unless (path.to_s.empty? or File.exist?(path))
        logger.error "Cannot find #{conf_sym} file #{path}"
      end
    end
    private :check_file
  end
end
