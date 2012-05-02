enable :sessions

# Tutorial by Example, Sinatra Edition
# A simple app that allows a user to first authorize their Dropbox account, and then upload a file to their Dropbox.

get '/' do
  if params[:oauth_token] then
    dropbox_session = Dropbox::Session.deserialize(session[:dropbox_session])
    dropbox_session.authorize(params)
    session[:dropbox_session] = dropbox_session.serialize # re-serialize the authenticated session
    redirect '/upload'
  else
    dropbox_session = Dropbox::Session.new('key', 'secret')
    session[:dropbox_session] = dropbox_session.serialize
    redirect dropbox_session.authorize_url(:oauth_callback => 'http://localhost:9393')
  end
end

get '/upload' do
 redirect '/' unless session[:dropbox_session]
 dropbox_session = Dropbox::Session.deserialize(session[:dropbox_session])
 dropbox_session.mode = :dropbox
 redirect '/' unless dropbox_session.authorized?
 dropbox_session.upload 'testfile.txt', 'Folder'
 uploaded_file = dropbox_session.file 'Folder/testfile.txt'
 'This is the metadata: ' + uploaded_file.metadata.size
end

get "/logout" do
  session = {}
  redirect "/"
end