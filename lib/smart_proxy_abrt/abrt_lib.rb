require 'net/http'
require 'net/https'
require 'uri'
require 'time'
require 'fileutils'

require 'openssl'

require 'proxy/log'
require 'proxy/request'

module AbrtProxy
  module Error
    class Unauthorized < StandardError; end
    class CertificateError < StandardError; end
    class SyntaxError < StandardError; end
  end

  # Returns hex representation of random bytes-long number
  def self.random_hex_string(nbytes)
    OpenSSL::Random.random_bytes(nbytes).unpack('H*').join
  end

  # Generate multipart boundary separator
  def self.suggest_separator
      separator = "-"*28
      separator + self.random_hex_string(16)
  end

  # It seems that Net::HTTP does not support multipart/form-data - this function
  # is adapted from http://stackoverflow.com/a/213276 and lib/proxy/request.rb
  def self.form_data_file(content, file_content_type)
    # Assemble the request body using the special multipart format
    thepart =  "Content-Disposition: form-data; name=\"file\"; filename=\"*buffer*\"\r\n" +
               "Content-Type: #{ file_content_type }\r\n\r\n#{ content }\r\n"

    boundary = self.suggest_separator
    while thepart.include? boundary
      boundary = self.suggest_separator
    end

    body = "--" + boundary + "\r\n" + thepart + "--" + boundary + "--\r\n"
    headers = {
      "User-Agent"     => "foreman-proxy/#{Proxy::VERSION}",
      "Content-Type"   => "multipart/form-data; boundary=#{ boundary }",
      "Content-Length" => body.length.to_s
    }

    return headers, body
  end

  def self.faf_request(path, content, content_type="application/json")
    uri              = URI.parse(AbrtProxy::Plugin.settings.server_url.to_s)
    http             = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = uri.scheme == 'https'
    http.verify_mode =
      if AbrtProxy::Plugin.settings.server_ssl_noverify
        OpenSSL::SSL::VERIFY_NONE
      else
        OpenSSL::SSL::VERIFY_PEER
      end

    if AbrtProxy::Plugin.settings.server_ssl_cert && !AbrtProxy::Plugin.settings.server_ssl_cert.to_s.empty? \
        && AbrtProxy::Plugin.settings.server_ssl_key && !AbrtProxy::Plugin.settings.server_ssl_key.to_s.empty?
      http.cert = OpenSSL::X509::Certificate.new(File.read(AbrtProxy::Plugin.settings.server_ssl_cert))
      http.key  = OpenSSL::PKey::RSA.new(File.read(AbrtProxy::Plugin.settings.server_ssl_key), nil)
    end

    headers, body = self.form_data_file content, content_type

    path = [uri.path, path].join unless uri.path.empty?
    response = http.start { |con| con.post(path, body, headers) }

    response
  end

  def self.cert_names(request)
    client_cert = request.env['SSL_CLIENT_CERT']
    raise AbrtProxy::Error::Unauthorized, "Client certificate required" if client_cert.to_s.empty?

    begin
      client_cert = OpenSSL::X509::Certificate.new(client_cert)
    rescue OpenSSL::OpenSSLError => e
      raise AbrtProxy::Error::CertificateError, e.message
    end

    begin
      cn = client_cert.subject.to_a.find { |name, value| name == 'CN' }
      names = [cn[1]]
    rescue NoMethodError
      raise AbrtProxy::Error::CertificateError, "Common Name not found in the certificate"
    end

    alt_name_ext = client_cert.extensions.find { |ext| ext.oid == 'subjectAltName' }
    if alt_name_ext
      names += alt_name_ext.value.
                            split(/, ?/).
                            select { |s| s.start_with? 'URI:CN=' }.
                            map { |s| s.sub(/^URI:CN=/, '') }
    end

    return names
  end

  class AbrtRequest < Proxy::HttpRequest::ForemanRequest
    def post_report(report)
      send_request(request_factory.create_post('api/abrt_reports', report))
    end
  end

  class HostReport
    include Proxy::Log

    class AggregatedReport
      attr_accessor :report, :count, :hash, :reported_at
      def initialize(report, count, hash, reported_at)
        @report = report
        @count = count
        @hash = hash
        @reported_at = Time.parse reported_at
      end
    end

    class Error < RuntimeError; end

    attr_reader :host, :reports, :files, :by_hash

    def initialize(fname)
      contents = IO.read(fname)
      json = JSON.parse(contents)

      [:report, :reported_at, :host].each do |field|
        if !json.has_key?(field.to_s)
          raise AbrtProxy::Error::SyntaxError, "Report #{fname} missing field #{field}"
        end
      end

      report = json["report"]
      hash = HostReport.duphash report
      ar = AggregatedReport.new(json["report"], 1, hash, json["reported_at"])
      @reports = [ar]
      # index the array elements by duphash, if they have one
      @by_hash = {}
      @by_hash[hash] = ar unless hash.nil?
      @files = [fname]
      @host = json["host"]
      @althosts = json["althosts"]
    end

    def merge(other)
      raise HostReport::Error, "Host names do not match" unless @host == other.host

      other.reports.each do |ar|
        if !ar.hash.nil? && @by_hash.has_key?(ar.hash)
          # we already have this report, just increment the counter
          found_report = @by_hash[ar.hash]
          found_report.count += ar.count
          found_report.reported_at = [found_report.reported_at, ar.reported_at].min
        else
          # we either don't have this report or it has no hash
          @reports << ar
          @by_hash[ar.hash] = ar unless ar.hash.nil?
        end
      end
      @files += other.files
    end

    def send_to_foreman
      foreman_report = create_foreman_report
      logger.debug "Sending #{foreman_report}"
      AbrtRequest.new.post_report(foreman_report.to_json)
    end

    def unlink
      @files.each do |fname|
        logger.debug "Deleting #{fname}"
        File.unlink(fname)
      end
    end

    def self.save(hostnames, report, reported_at=nil)
      # create the spool dir if it does not exist
      FileUtils.mkdir_p HostReport.spooldir

      reported_at ||= Time.now.utc
      on_disk_report = { "host" => hostnames[0], "report" => report , "reported_at" => reported_at.to_s, "althosts" => hostnames[1..-1] }

      # write report to temporary file
      temp_fname = unique_filename "new-"
      File.open temp_fname, File::WRONLY|File::CREAT|File::EXCL do |tmpfile|
        tmpfile.write(on_disk_report.to_json)
      end

      # rename it
      final_fname = unique_filename("ureport-" + DateTime.now.strftime("%FT%T") + "-")
      File.link temp_fname, final_fname
      File.unlink temp_fname
    end

    def self.load_from_spool
      reports = []
      report_files = Dir[File.join(HostReport.spooldir, "ureport-*")]
      report_files.each do |fname|
        begin
          reports << new(fname)
        rescue => e
          logger.error "Failed to parse report #{fname}: #{e}"
        end
      end
      reports
    end

    private

    def format_reports
      @reports.collect do |ar|
        r = {
          "count"       => ar.count,
          "reported_at" => ar.reported_at.utc.to_s,
          "full"        => ar.report
        }
        r["duphash"] = ar.hash unless ar.hash.nil?
        r
      end
    end

    def create_foreman_report
      { "abrt_report" => {
            "host"        => @host,
            "althosts"    => @althosts,
            "reports"     => format_reports
        }
      }
    end

    def self.duphash(report)
      return nil if !AbrtProxy::Plugin.settings.aggregate_reports

      begin
        satyr_report = Satyr::Report.new report.to_json
        stacktrace = satyr_report.stacktrace
        thread = stacktrace.find_crash_thread
        thread.duphash
      rescue => e
        logger.error "Error computing duphash: #{e}"
        nil
      end
    end

    def self.unique_filename(prefix)
      File.join(HostReport.spooldir, prefix + AbrtProxy::random_hex_string(8))
    end

    def self.spooldir
      AbrtProxy::Plugin.settings.spooldir
    end
  end
end
