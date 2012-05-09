require 'sinatra'
require 'dropbox_sdk'
require 'json'
require 'haml'
require 'coffee-script'
# database
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'

enable :sessions
set :url, (settings.environment == :production) ? "http://dbinbox.com/" : "http://127.0.0.1:9393/"

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

  if User.get(username) || !(username =~ /^\w+$/)
    # username already exists/is of the wrong format
    @error = "Sorry! \"#{username}\" is already taken."
    @error = "Your username must only contain letters." if !(username =~ /^\w+$/)
    @error = "Your username can't be blank! I need to use that one! D:" if username.empty?
    return haml(:index)
  else
    dbsession = DropboxSession.new(dbkey, dbsecret)
    session[:dropbox_session] = dbsession.serialize #serialize and save this DropboxSession
    session[:username] = username

    # send them out to authenticate us
    redirect dbsession.get_authorize_url(settings.url)
  end
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
  puts "post /username"
  
  return unless @user = get_user

  redirect '/' unless @user.dropbox_session
  @dbsession = DropboxSession.deserialize(@user.dropbox_session)
  @client    = DropboxClient.new(@dbsession, :app_folder)

  # upload the posted file to dropbox keeping the same name
  responses = params[:files].map do |file|
    p file
    begin
      # if things go normally, just return the hashed response
      @client.put_file(file[:filename], file[:tempfile].read).map{ |f|
        # alter some fields for simplicity on the client end
        f[:name]          = f["path"].gsub(/^\//,'')
        f[:size]          = f["bytes"]
        f[:url]           = ""
        f[:thumbnail_url] = ""
        f[:delete_url]    = ""
        f[:delete_type]   = "DELETE"
      }
    rescue DropboxAuthError
      puts "DropboxAuthError"
      {
        :error => "Client not authorized.",
        :name          => file[:filename]
      }
    end
  end

  puts "returning: "
  p responses

  
  # looks like: [{"revision":1,"rev":"1079a1100","thumb_exists":true,"bytes":9646,"modified":"Wed, 09 May 2012 04:10:27 +0000","client_mtime":"Wed, 09 May 2012 04:10:27 +0000","path":"/!out.png","is_dir":false,"icon":"page_white_picture","root":"app_folder","mime_type":"image/png","size":"9.4 KB","name":"!out.png","size":9646,"url":"","thumbnail_url":"","delete_url":"","delete_type":"DELETE"}]

  responses.to_json
end