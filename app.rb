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
  puts "GETTING /upload"
  get_session
  # show a file upload page
  haml :upload
  end

  post '/upload' do
    puts "POSTING TO /upload"
    p params
    get_session

    # upload the posted file to dropbox keeping the same name
    resp = params[:files].map do |file|
      @client.put_file(file[:filename], file[:tempfile].read)
    end
    p resp
    "Upload successful! File now at #{resp}"
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
    %link(rel="stylesheet" href="http://blueimp.github.com/cdn/css/bootstrap.min.css")
    %link(rel="stylesheet" href="http://blueimp.github.com/cdn/css/bootstrap-responsive.min.css")
    /[if lt IE 7]
      %link(rel="stylesheet" href="http://blueimp.github.com/cdn/css/bootstrap-ie6.min.css")
    %link(rel="stylesheet" href="css/jquery.fileupload-ui.css")
    %link(rel="stylesheet" href="css/style.css")
  %body
    .container
      =yield
    %script(src="js/jquery.min.js")
    %script(src="js/vendor/jquery.ui.widget.js")
    %script(src="js/jquery.iframe-transport.js")
    %script(src="js/jquery.fileupload.js")
    %script(src="js/jquery.fileupload-fp.js")
    %script(src="js/jquery.fileupload-ui.js")
    :coffeescript
      $ ->
        $('#upload').fileupload({
          dataType: 'json',
          autoUpload: true,
          done: (e,data) ->
            $.each data.result, (index, file) ->
              $('<p/>').text(file.name).appendTo(document.body)
        })

@@ upload
%h1
  Send files to 
  =@info['email']
%form{action: 'upload', multipart: true, id: 'upload'}
  .row.fileupload-buttonbar.span7
    %span.btn.btn-success.fileinput-button
      %i.icon-plus.icon-white
      %span Add files...
      %input(type="file" name="files[]" multiple)
    or drag and drop files onto this page
    .span5.fileupload-progress.fade
      .progress.progress-success.progress-striped.active
      .bar{:style => "width:0%;"}
      .progress-extended &nbsp;
    .fileupload-loading
    %table.table.table-striped
      %tbody.files(data-toggle="modal-gallery" data-target="#modal-gallery")