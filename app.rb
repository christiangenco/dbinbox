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
production = !File.exists?("../../projects")

directory = production ? File.expand_path("../../shared") : Dir.pwd
DataMapper.setup(:default, "sqlite3://#{File.join(directory, "users.db")}")

# enable logging
require 'logger'
logdir = File.join(directory, "log")
Dir.mkdir(logdir) unless File.directory? logdir
@@log = Logger.new(File.join(logdir, "dbinbox.log"))

class User
  include DataMapper::Resource
  property :username, String, :key => true, :required => true, :unique => true, :format => /^\w+$/
  property :dropbox_session, Text
  property :referral_link, String, :length => 250
  property :authenticated, Boolean
  property :display_name, String, :length => 250
  property :email, String, :length => 250
  property :uid, String
  property :country, String
  property :quota, Integer
  property :shared, Integer
  property :normal, Integer
  property :created_at, DateTime
  property :password, BCryptHash
end
# Automatically create the tables if they don't exist
DataMapper.auto_upgrade!

# dropbox api
set :dbkey, File.read(".dbkey")
set :dbsecret, File.read(".dbsecret")

class Numeric
  def to_human
    return "empty" if self.zero?
    units = %w{bytes KB MB GB TB}
    e = (Math.log(self)/Math.log(1024)).floor
    s = "%.3f" % (to_f / 1024**e)
    s.sub(/\.?0*$/, " " + units[e])
  end
end


# ----------------------------------------------
# HELPER METHODS
# ----------------------------------------------

def get_user(username = params[:username])
  puts "getting user"
  user = User.get(username)

  # should we check if we're still authenticated?
end

def is_allowed_to_upload_for(username)
  return true if get_user(username).password.nil?

  paths = session[:allowed_upload_paths]
  return false if paths.nil?
  return paths.include?(username)
end

def allow_uploads_for(username)
  session[:allowed_upload_paths] ||= Set.new
  session[:allowed_upload_paths] << username.to_s
end

def redirect_with_authenticated_dropboxsession(return_url)
  dbsession = DropboxSession.new(settings.dbkey, settings.dbsecret)
  session[:unverified_dropboxsession] = dbsession.serialize

  redirect dbsession.get_authorize_url(return_url)
end

def retrieve_authenticated_dropboxsession
    # the user has returned from Dropbox
    # we've been authorized, so now request an access_token
  dbsession = DropboxSession.deserialize(session.delete(:unverified_dropboxsession))
  dbsession.get_access_token
  return dbsession
end


# ----------------------------------------------
# ROUTES
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

    dbsession = retrieve_authenticated_dropboxsession

    dbclient = DropboxClient.new(dbsession)

    # get info from dropbox
    account_info = dbclient.account_info
    puts "account_info = #{account_info}"
    quota = account_info["quota_info"]

    @user = User.create(
      username: session[:username],
      dropbox_session: dbsession.serialize,
      # referral_link: account_info["referral_link"],
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
  end

  return haml(:index) if @error

  session[:username] = username

  # send them out to authenticate us
  redirect_with_authenticated_dropboxsession(url('/'))
end

get "/js/app.js" do
  content_type "text/javascript"
  coffee File.open("./app.coffee").read
end

get "/logout" do
  session.clear
  redirect "/"
end

get "/:username" do
  @@log.info "/#{params[:username]}"
  @user = get_user
  if !@user
    @error = "Username '#{params[:username]}' not found. Would you like to link it with a Dropbox account?"
    return haml :index
  end
  @allowed_to_upload = is_allowed_to_upload_for(params[:username])
  haml :upload
end

post '/:username' do
  filenames = params[:files].map{|f| f[:filename]}.join(', ')
  @@log.info "Uploading files to /#{params[:username]}: #{filenames}"

  # IE 9 and below tries to download the result if Content-Type is application/json
  content_type (request.user_agent.index(/MSIE [6-9]/) ? 'text/plain' : :json)

  return unless @user = get_user
  return unless is_allowed_to_upload_for(params[:username])

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

post '/:username/send_text' do
  @@log.info "Sending text to /#{params[:username]}: \"#{params["message"]}\""

  # IE 9 and below tries to download the result if Content-Type is application/json
  content_type (request.user_agent.index(/MSIE [6-9]/) ? 'text/plain' : :json)

  puts "post /#{params['username']}/send_text"

  return unless @user = get_user
  return unless is_allowed_to_upload_for(params[:username])

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

post '/:username/access_code' do
  # We asked the user for this dbinbox's access code.

  @user = get_user

  if @user.password == params[:access_code]
    allow_uploads_for(@user.username)
  end

  redirect url("/#{params[:username]}")
end

post '/:username/admin' do
  # The user wants to change the dbinbox settings.
  # First check with Dropbox to make sure they own the account

  session[:clear_access_code] = params[:clear_access_code]
  session[:access_code] = BCrypt::Password.create(params[:access_code])
  redirect_with_authenticated_dropboxsession(url("/#{params[:username]}/admin"))
end

get '/:username/admin' do
  if !params[:oauth_token]
    @user = get_user
    return haml :admin
  end

  # The user wants to change the dbinbox settings.
  # Now we're coming back from Dropbox's authentication.

  user = get_user

  dbsession = retrieve_authenticated_dropboxsession
  dbclient = DropboxClient.new(dbsession)
  account_info = dbclient.account_info

  unless user.uid.to_i == account_info['uid']
    @error = "You must be the owner of the Dropbox to change the access code"
    redirect url("/#{user.username}")
  end

  # Replace the Dropbox session so people can re-link the app if they unlinked
  # it from Dropbox
  user.dropbox_session = dbsession.serialize

  # Get our variables out of the sesson so we don't accidentally reuse them
  access_code = session.delete(:access_code)
  clear_access_code = session.delete(:clear_access_code)

  if clear_access_code
    user.password = nil
  elsif access_code && !(access_code == "")
    user.password = access_code
  end

  user.save
  redirect url("/#{user.username}")
end


post '/:username/delete' do
  # The user wants to delete their dbinbox account.
  # First make sure they confirmed they want this.

  if params[:delete_confirmation] != "DELETE"
    redirect url("/#{params[:username]}/admin")
  end

  # Now check with Dropbox to make sure they own the account
  redirect_with_authenticated_dropboxsession(url("/#{params[:username]}/delete"))
end

get '/:username/delete' do
  if !params[:oauth_token]
    @user = get_user
    return haml :admin
  end

  # The user wants to change the dbinbox settings.
  # Now we're coming back from Dropbox's authentication.

  user = get_user

  dbsession = retrieve_authenticated_dropboxsession
  dbclient = DropboxClient.new(dbsession)
  account_info = dbclient.account_info

  unless user.uid.to_i == account_info['uid']
    @error = "You must be the owner of the Dropbox to delete the dbinbox account."
    redirect url("/#{user.username}")
  end

  user.destroy

  redirect url("/")
end
