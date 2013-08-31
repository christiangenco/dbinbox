require 'sinatra'
require 'dropbox_sdk'
require 'json'
require 'haml'
require 'coffee-script'
# database from http://datamapper.org/getting-started.html
require 'dm-core'
require 'dm-types'
require 'dm-migrations'
require 'dm-validations'

enable :sessions

production = !File.exists?("../../../projects")
directory = production ? File.expand_path("../../shared") : Dir.pwd

# Use DATABASE_URL from the environment if we have it,
# otherwise just use sqlite
if ENV['DATABASE_URL']
  database_url = ENV['DATABASE_URL']
else
  database_url = "sqlite3://#{File.join(directory, "users.db")}"
end
DataMapper.setup(:default, database_url)

# enable logging
require 'logger'
if ENV['LOG_TO_STDOUT']
  logpath = STDOUT
else
  logdir = File.join(directory, "log")
  Dir.mkdir(logdir) unless File.directory? logdir
  logpath = File.join(logdir, "dbinbox.log")
end
@@log = Logger.new(logpath)
@@log.level = Logger::Severity::INFO

# from http://stackoverflow.com/questions/8414395/verb-agnostic-matching-in-sinatra
def self.get_or_post(url,&block)
  get(url,&block)
  post(url,&block)
end

class User
  terabyte = 1024 * 1024 * 1024 * 1024

  include DataMapper::Resource
  property :username, String, :key => true, :required => true, :unique => true, :format => /^\w+$/
  property :dropbox_session, Text
  property :referral_link, String, :length => 250
  property :authenticated, Boolean
  property :display_name, String, :length => 250
  property :email, String, :length => 250
  property :uid, String
  property :country, String
  property :quota, Integer, :min => 0, :max => 50 * terabyte
  property :shared, Integer, :min => 0, :max => 50 * terabyte
  property :normal, Integer, :min => 0, :max => 50 * terabyte
  property :created_at, DateTime
  property :password, BCryptHash
end
# Automatically create the tables if they don't exist
DataMapper.auto_upgrade!

# dropbox api
set :dbkey,    ENV['DROPBOX_KEY'] || File.read(".dbkey")
set :dbsecret, ENV['DROPBOX_SECRET'] || File.read(".dbsecret")

class Numeric
  def to_human
    return "empty" if self.zero?
    units = %w{bytes KB MB GB TB}
    e = (Math.log(self)/Math.log(1024)).floor
    s = "%.3f" % (to_f / 1024**e)
    s.sub(/\.?0*$/, " " + units[e])
  end
end

# compile app.coffee
File.open('./public/js/app.js', 'w'){|f|
  f.puts CoffeeScript.compile(File.open("./public/js/app.coffee").read)
}

# ----------------------------------------------

# user visits homepage
# user enters desired username
# app checks that username isn't already registered
  # if yes -> redirect to home page with error message
# app stores dbsession and desired username in session
# dropbox authenticates
# app creates user from session's username, dbtoken, and info from /account/info
  # doublechecks that username isn't taken
# app shows user registered page with link to their dbinbox

# person visits link
# app looks up access token based on username
#   if doesn't exist, show "user does not exist"
# if exists, look up access token and use that

get '/' do
  if !params[:oauth_token]
    @@log.info "first-time user!"
    haml :index
  else
    @@log.info "Creating account for \"#{session[:username]}\"."
    # the user has returned from Dropbox
    # we've been authorized, so now request an access_token
    dbsession = DropboxSession.deserialize(session[:dropbox_session])
    dbsession.get_access_token

    dbclient = DropboxClient.new(dbsession)

    # get info from dropbox
    account_info = dbclient.account_info
    puts "account_info = #{account_info}"
    quota = account_info["quota_info"]
    
    @user = User.create(
      :username        => session[:username],
      :dropbox_session => dbsession.serialize,
      # :referral_link => account_info["referral_link"],
      :authenticated   => true,
      :display_name    => account_info["display_name"],
      :uid             => account_info["uid"],
      :country         => account_info["country"],
      :quota           => quota["quota"],
      :normal          => quota["normal"],
      :shared          => quota["shared"],
      :created_at      => Time.now
    )

    if @user.saved?
      @@log.info "\"#{session[:username]}\"'s account has been created."
      session[:registered] = true
      haml :index
    else
      @@log.info "\"#{session[:username]}\"'s account could not be created."
      @@log.info @user
      @error = "Sorry, your information couldn't be saved: #{@user.errors.map(&:to_s).join(', ')}. Please try again or report the issue to <a href='https://twitter.com/cgenco'>@cgenco</a>."
      haml :index
    end
  end
end

# request a username
post '/' do
  username = params['username']
  @@log.info "\"#{username}\" username requested"

  # if the user already exists and is currently authenticated
  # or if the requested username isn't composed of word characters
  # then return an error
  user = User.get(username)
  if !user.nil? && user.authenticated
    @error = "Sorry! \"#{username}\" is already taken."
  elsif !(username =~ /^\w+$/)
    @error = "Your username must only contain letters." if !(username =~ /^\w+$/)
  elsif username.empty?
    @error = "Your username can't be blank! I need to use that one! D:"
  elsif username =~ /^admin|login|logout|delete|send$/
    @error = "Nice try, smarty pants."
  end

  return haml(:index) if @error

  dbsession = DropboxSession.new(settings.dbkey, settings.dbsecret)
  session[:dropbox_session] = dbsession.serialize #serialize and save this DropboxSession
  session[:username] = username

  # send them out to authenticate us
  redirect dbsession.get_authorize_url(url('/'))
end

get "/login" do
  dbsession = DropboxSession.new(settings.dbkey, settings.dbsecret)
  session[:dropbox_session] = dbsession.serialize
  redirect dbsession.get_authorize_url(url('/admin'))
end

get "/logout" do
  session.clear
  redirect "/"
end

get "/admin" do
  if params[:oauth_token] 
    # just came from being authenticated from Dropbox
    # stash this user's username and update their session
    dbsession = DropboxSession.deserialize(session[:dropbox_session])
    dbsession.get_access_token
    dbclient = DropboxClient.new(dbsession)
    @user = User.first(:uid => dbclient.account_info["uid"])

    # update the user with the new session in case they're re-authenticating
    @user.update(:dropbox_session => dbsession.serialize)

    session[:username] = @user.username
    session[:registered] = true
    return haml :admin
  elsif session[:registered]
    # already registered; render the admin panel

    @user = User.get(session[:username])

    return haml :admin
  else
    # need to get authenticated by Dropbox first
    redirect url('/signin')
  end

end

post "/admin" do
  @user = User.get(session[:username])
  redirect url('/signin') unless @user

  @user.update(:password => params[:access_code])
  return haml :admin
end

post "/delete" do
  if session[:registered]
    @user = User.get(session[:username])
    @user.destroy
    session.clear
    redirect url('/')
  else
    redirect url('/signin')
  end
end

get_or_post '/send/:username/?*' do
  @subfolder = params[:splat].first

  # IE 9 and below tries to download the result if Content-Type is application/json
  content_type (request.user_agent && request.user_agent.index(/MSIE [6-9]/) ? 'text/plain' : :json)

  unless @user = User.get(params[:username])
    status 404
    return
  end

  redirect '/' unless @user.dropbox_session
  @dbsession = DropboxSession.deserialize(@user.dropbox_session)
  @client    = DropboxClient.new(@dbsession, :app_folder)

  params[:files] ||= []

  if message = params["message"]
    @@log.info "Sending text to /#{params[:username]}: \"#{params["message"]}\""
    puts "post /#{params['username']}/send_text"

    message = params["message"]
    # add header to message
    # use @env['REMOTE_ADDR'] if request.ip doesn't work
    message = "Uploaded #{Time.now.to_s} from #{request.ip}\r\n\r\n#{message}"

    filename = Time.new.strftime("%Y-%m-%d-%H.%M.%S")
    filename += " " + params["filename"] if params["filename"] && !params["filename"].empty?
    filename += ".txt"

    params[:files].push({:filename => filename, :message => message})
  end

  responses = params[:files].map do |file|
    begin
      # if things go normally, just return the hashed response
      response = @client.put_file(File.join(@subfolder || '', file[:filename]), file[:message] || file[:tempfile].read)
      # alter some fields for simplicity on the client end
      response[:name]          = response["path"].gsub(/^\//,'')
      response[:size]          = response["bytes"]
      response[:human_size]    = response["bytes"].to_human
      response[:url]           = ""
      response[:thumbnail_url] = ""
      response[:delete_url]    = ""
      response[:delete_type]   = "DELETE"
      response
    rescue DropboxAuthError
      @@log.error "DropboxAuthError"
      session[:registered] = false
      @user.authenticated  = false
      @user.save
      {
        :error       => "Client not authorized.",
        :error_class => 'DropboxAuthError',
        :name        => file[:filename]
      }
    end
  end

  responses.to_json # an array of file description hashes
end

get "/:username/?*" do
  @@log.info "/#{params[:username]}"
  @subfolder = params[:splat].first
  @user = User.get(params[:username])
  @action = "/send/" + params[:username] + (@subfolder ? "/" + @subfolder : "")
  if !@user
    @error = "Username '#{params[:username]}' not found. Would you like to link it with a Dropbox account?"
    return haml :index
  end

  if @user.password.nil? || @user.password == params[:password]
    haml :upload
  else
    haml :enter_password
  end
end

