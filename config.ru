require 'sinatra'
 
set :environment, :production
set :port, 3200
disable :run, :reload

require File.join(File.dirname(__FILE__), 'app')
run Sinatra::Application