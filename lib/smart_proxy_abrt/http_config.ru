require 'smart_proxy_abrt/abrt_api'

map '/abrt' do
  run Proxy::Abrt::Api
end
