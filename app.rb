require 'sinatra'
require 'dropbox_sdk'
require 'coffee-script'
require 'coffee-filter'
enable :sessions

get '/' do
  if not params[:oauth_token] then
    dbsession = DropboxSession.new('ribh7ft60gym2l8', 'sj8rz89ril4wl76') # key, secret
    session[:dropbox_session] = dbsession.serialize #serialize and save this DropboxSession
    #pass to get_authorize_url a callback url that will return the user here
    # redirect dbsession.get_authorize_url url_for(:action => 'authorize')
    redirect dbsession.get_authorize_url("http://127.0.0.1:9393")
  else
    # the user has returned from Dropbox
    dbsession = DropboxSession.deserialize(session[:dropbox_session])
    dbsession.get_access_token  #we've been authorized, so now request an access_token
    session[:dropbox_session] = dbsession.serialize

    redirect '/upload'
  end
end

def get_session
  # Check if user has no dropbox session...re-direct them to authorize
  redirect '/' unless session[:dropbox_session]
  @dbsession = DropboxSession.deserialize(session[:dropbox_session])
  @client = DropboxClient.new(@dbsession, :app_folder) #raise an exception if session not authorized
  @info = @client.account_info # look up account information
end

get '/upload' do
  get_session
  # show a file upload page
  haml :upload
  end

  post '/upload' do
    get_session

    # upload the posted file to dropbox keeping the same name
    resp = client.put_file(params[:file].original_filename, params[:file].read)
    render :text => "Upload successful! File now at #{resp['path']}"
  end

# dropbox_session.mode = :dropbox
 # redirect '/' unless dropbox_session.authorized?
 # dropbox_session.upload 'testfile.txt', 'Folder'
 # uploaded_file = dropbox_session.file 'Folder/testfile.txt'
 # 'This is the metadata: ' + uploaded_file.metadata.size

get "/logout" do
  session = {}
  redirect "/"
end

__END__

@@ layout
%html
  %head
    %title Dropbox Dropbox
  %body
    =yield
    %script(src="js/jquery.min.js")
    %script(src="js/vendor/jquery.ui.widget.js")
    %script(src="js/jquery.iframe-transport.js")
    %script(src="js/jquery.fileupload.js")
    :coffeescript
      alert "rofl"

@@ upload
%h1=@info['email']
%form{action: 'upload', multipart: true}
  
<%= file_field_tag 'file' %><%= submit_tag %><% end %>