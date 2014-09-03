require 'smart_proxy_abrt/abrt_api'

map '/abrt' do
  run AbrtProxy::Api
end
