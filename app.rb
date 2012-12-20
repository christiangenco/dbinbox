require 'sinatra'
require 'dropbox_sdk'
require 'json'
require 'haml'
require 'coffee-script'
# database from http://datamapper.org/getting-started.html
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'

enable :sessions
# set :url, (settings.environment == :production) ? "http://dbinbox.com/" : "http://127.0.0.1:9393/"
# so hackey
production = !File.exists?("../../projects")
set :url, production ? "http://dbinbox.com/" : "http://127.0.0.1:9393/"

directory = production ? File.expand_path("../../shared") : Dir.pwd
DataMapper.setup(:default, "sqlite3://#{File.join(directory, "users.db")}")

class User
  include DataMapper::Resource
  property :username, String, :key => true, :required => true, :unique => true, :format => /^\w+$/
  property :dropbox_session, Text
  property :referral_link, String
  property :authenticated, Boolean
  property :display_name, String
  property :email, String
  property :uid, String
  property :country, String
  property :quota, Integer
  property :shared, Integer
  property :normal, Integer
  property :created_at, DateTime
end
# Automatically create the tables if they don't exist
DataMapper.auto_upgrade!

# dropbox api
dbkey = File.read(".dbkey")
dbsecret = File.read(".dbsecret")

class Numeric
  def to_human
    units = %w{bytes KB MB GB TB}
    e = (Math.log(self)/Math.log(1024)).floor
    s = "%.3f" % (to_f / 1024**e)
    s.sub(/\.?0*$/, " " + units[e])
  end
end

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
    # first-time user!
    haml :index
  else
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
      username: session[:username],
      dropbox_session: dbsession.serialize,
      referral_link: account_info["referral_link"],
      authenticated: true,
      display_name: account_info["display_name"],
      uid: account_info["uid"],
      country: account_info["country"],
      quota: quota["quota"],
      normal: quota["normal"],
      shared: quota["shared"],
      created_at: Time.now
    )

    if @user.saved?
      session[:registered] = true
      haml :index
    else
      @error = "Sorry, your information couldn't be saved: #{@user.errors.map{|e| e.to_s}}. Please try again or report the issue to @cgenco."
      haml :index
    end
  end
end

# request a username
post '/' do
  username = params['username']

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
  end

  return haml(:index) if @error

  dbsession = DropboxSession.new(dbkey, dbsecret)
  session[:dropbox_session] = dbsession.serialize #serialize and save this DropboxSession
  session[:username] = username

  # send them out to authenticate us
  redirect dbsession.get_authorize_url(settings.url)
end

get "/js/app.js" do
  content_type "text/javascript"
  coffee File.open("./app.coffee").read
end

get "/logout" do
  session = nil
  redirect "/"
end

def get_user
  puts "getting user"
  user = User.get(params[:username])

  # check if we're still authenticated

end

get "/:username" do
  puts "get /username"
  @user = get_user
  if !@user
    @error = "Username '#{params[:username]}' not found. Would you like to link it with a Dropbox account?"
    return haml :index
  end
  haml :upload
end

post '/:username' do
  content_type :json
  puts "post /#{params['username']}"
  
  return unless @user = get_user

  redirect '/' unless @user.dropbox_session
  @dbsession = DropboxSession.deserialize(@user.dropbox_session)
  @client    = DropboxClient.new(@dbsession, :app_folder)

  # upload the posted file to dropbox keeping the same name
  responses = params[:files].map do |file|
    begin
      # if things go normally, just return the hashed response
      response = @client.put_file(file[:filename], file[:tempfile].read)
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
      puts "DropboxAuthError"
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

post '/:username/send_text' do
  content_type :json
  puts "post /#{params['username']}/send_text"

  return unless @user = get_user

  redirect '/' unless @user.dropbox_session
  @dbsession = DropboxSession.deserialize(@user.dropbox_session)
  @client    = DropboxClient.new(@dbsession, :app_folder)

  message = params["message"]
  # add header to message
  # use @env['REMOTE_ADDR'] if request.ip doesn't work
  message = "Uploaded #{Time.now.to_s} from #{request.ip}\n\n#{message}"

  filename = Time.new.strftime("%Y-%m-%d-%H.%M.%S")
  filename += " " + params["filename"] if params["filename"] && !params["filename"].empty?
  filename += ".txt"

  begin
      # if things go normally, just return the hashed response
      response = @client.put_file(filename, message)
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
      puts "DropboxAuthError"
      session[:registered] = false
      @user.authenticated  = false
      @user.save

      {
        :error       => "Client not authorized.",
        :error_class => 'DropboxAuthError',
        :name        => file[:filename]
      }
    end.to_json
end