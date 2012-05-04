require 'sinatra'
require 'dropbox_sdk'
require 'json'
require 'haml'
require 'coffee-script'
enable :sessions

# database
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'
DataMapper.setup( :default, "sqlite3://#{Dir.pwd}/users.db" )
class User
  include DataMapper::Resource
  property :username, String, :key => true, :required => true, :unique => true, :format => /^\w+$/
  property :dropbox_session, Text
  property :referral_link, String
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
dbkey, dbsecret = 'ribh7ft60gym2l8', 'sj8rz89ril4wl76'

# ----------------------------------------------

# user visits homepage
# user enters desired username
# app checks that username isn't already registered
  # if yes -> redirect to home page with error message
# app stores dbsession and desired username in session
# dropbox authenticates
# app creates user from session's username, dbtoken, and info from /account/info
  # doublechecks that username isn't taken
# app shows user registered page with link to their dropbox dropbox

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
      display_name: account_info["display_name"],
      uid: account_info["uid"],
      country: account_info["country"],
      quota: quota["quota"],
      normal: quota["normal"],
      shared: quota["shared"],
      created_at: Time.now
    )

    if @user.saved?
      puts "USER HAS BEEN SAVED: #{@user.to_s}"
      puts "User.all.size = #{User.all.size}"
      haml :registered
    else
      # show @user.errors
      "there were errors saving: #{@user.errors.map{|e| e.to_s}}"
    end
  end
end

# request a username
post '/' do
  username = params['username']

  if User.get(username) || !(username =~ /^\w+$/)
    # username already exists/is of the wrong format
    @error = "Sorry! \"#{username}\" is already taken."
    @error = "Your username must only contain letters." if username =~ /^\w+$/
    return haml(:index)
  else
    dbsession = DropboxSession.new(dbkey, dbsecret)
    session[:dropbox_session] = dbsession.serialize #serialize and save this DropboxSession
    session[:username] = username

    # send them out to authenticate us
    redirect dbsession.get_authorize_url("http://127.0.0.1:9393/")
  end
end

get "/js/app.js" do
  content_type "text/javascript"
  coffee File.open("./app.coffee").read
end

def get_user
  user = User.get(params[:username])
  if !user
    @error = "User '#{params[:username]}' not found"
    redirect "/error"
  end
  user
end

get "/:username" do
  @user = get_user
  haml :upload
end

post '/:username' do  
  @user = get_user
  redirect '/' unless @user.dropbox_session
  @dbsession = DropboxSession.deserialize(@user.dropbox_session)
  @client = DropboxClient.new(@dbsession, :app_folder) #raise an exception if session not authorized

  # upload the posted file to dropbox keeping the same name
  resp = params[:files].map do |file|
    @client.put_file(file[:filename], file[:tempfile].read)
  end

  resp.map{|f|
    f[:name] = f["path"].gsub(/^\//,'')
    f[:size] = f["bytes"]
    f[:url] = "hi"
    f[:thumbnail_url] = "hi"
    f[:delete_url] = ""
    f[:delete_type] = "DELETE"
  }
  content_type :json
  resp.to_json
end