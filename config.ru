require 'sinatra'
 
set :environment, :production
set :port, 3200
disable :run, :reload

require File.join(File.dirname(__FILE__), 'app')
set :protection, :except => [:remote_token, :frame_options, :json_csrf]
run Sinatra::Application