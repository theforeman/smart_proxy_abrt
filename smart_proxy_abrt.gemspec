require File.expand_path('../lib/smart_proxy_abrt/abrt_version', __FILE__)

Gem::Specification.new do |s|
  s.name = 'smart_proxy_abrt'
  s.version = Proxy::Abrt::VERSION
  s.summary = "Automatic Bug Reporting Tool plugin for Foreman's smart proxy"
  s.description = 'This smart proxy plugin, together with a Foreman plugin, add the capability to send ABRT micro-reports from your managed hosts to Foreman.'
  s.authors = ['Martin Milata']
  s.email = 'mmilata@redhat.com'
  s.files = Dir['{bin,lib,settings.d,bundler.d,test,extra}/**/*'] + ['README', 'LICENSE', 'Rakefile']
  s.executables = ['smart-proxy-abrt-send']
  s.homepage = 'http://github.com/abrt/smart-proxy-abrt'
  s.license = 'GPL-3'
  s.add_dependency 'satyr', '~> 0.1'
end
