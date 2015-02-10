require 'openssl'
require 'json'

require 'smart_proxy_abrt/abrt_lib'

STATUS_ACCEPTED = 202

module AbrtProxy
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers
    authorize_with_ssl_client

    post '/reports/new/' do
      begin
        names = AbrtProxy::cert_names request
      rescue AbrtProxy::Error::Unauthorized => e
        log_halt 403, "Client authentication required: #{e.message}"
      rescue AbrtProxy::Error::CertificateError => e
        log_halt 403, "Could not determine common name from certificate: #{e.message}"
      end

      begin
        ureport_json = request['file'][:tempfile].read
      rescue => e
        log_halt 400, "Missing report file"
      end
      begin
        ureport = JSON.parse(ureport_json)
      rescue JSON::JSONError => e
        log_halt 400, "Malformed report file: #{e.message}"
      end

      #forward to FAF
      response = nil
      if AbrtProxy::Plugin.settings.server_url
        begin
          result = AbrtProxy::faf_request "/reports/new/", ureport_json
          response = result.body if result.code.to_s == STATUS_ACCEPTED.to_s
        rescue => e
          logger.error "Unable to forward to ABRT server: #{e}"
        end
      end
      unless response
        # forwarding is not configured or failed
        # FAF source that generates replies is in src/webfaf/reports/views.py
        response = { "result" => false,
                     "message" => "Report queued" }
        if Proxy::SETTINGS.foreman_url
          foreman_url = Proxy::SETTINGS.foreman_url
          foreman_url += "/" if foreman_url[-1] != "/"
          foreman_url += "hosts/#{names[-1]}/abrt_reports"
          response["reported_to"] = [{ "reporter" => "Foreman",
                                       "type" => "url",
                                       "value" => foreman_url }]
        end
        response = response.to_json
      end

      #save report to disk
      begin
        AbrtProxy::HostReport.save names, ureport
      rescue => e
        log_halt 500, "Failed to save the report: #{e}"
      end

      status STATUS_ACCEPTED
      response
    end

    post '/reports/:action/' do
      # pass through to real FAF if configured
      if AbrtProxy::Plugin.settings.server_url
        begin
          body = request['file'][:tempfile].read
        rescue => e
          log_halt 400, "File missing: #{e.message}"
        end
        begin
          result = AbrtProxy::faf_request "/reports/#{params[:action]}/", body
        rescue => e
          log_halt 503, "ABRT server unavailable: #{e}"
        end
        status result.code
        result.body
      else
        log_halt 404, "foreman-proxy does not implement /reports/#{params[:action]}/"
      end
    end
  end
end
