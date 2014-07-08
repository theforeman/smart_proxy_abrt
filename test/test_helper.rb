path_to_smart_proxy_repo = '../smart-proxy'
$LOAD_PATH.unshift File.join(path_to_smart_proxy_repo, 'test')

# create log directory in our (not smart-proxy) repo
logdir = File.join(File.dirname(__FILE__), '..', 'logs')
FileUtils.mkdir_p(logdir) unless File.exists?(logdir)

require 'test_helper'

APP_ROOT = File.join(File.dirname(__FILE__), '..')
