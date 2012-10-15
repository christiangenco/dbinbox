$ ->
  uploadRowHTML = (filename, filesize=-1, error=null) ->
    row = $(
      '<tr class="template-upload fade">' +
      '<td class="filename-col span7">' +
      '<img class="sprite s_page_white_get" src="img/icon_spacer.gif" />' +
      '<span class="name"></span> - ' +
      '<span class="size"></span>' +
      '</td>' +
      '<td class="info-col span4">uploading to Dropbox...</td>' +
      '<td class="status-col span1">' +
      '<img class="" src="img/ajax-loading-small.gif" />' +
      '</td>' +
      "</tr>"
    )
    row.find('.name').text(filename)
    row.find('.size').text(filesize)
    row.find('.error').text(error) if error
    row

  $('#upload').fileupload({
    dataType: 'json',
    autoUpload: true,
    acceptFileTypes: /./,
    # dragover: ->
    #   console.log("DRAAAAAG")
    uploadTemplateId: null,
    downloadTemplateId: null,
    uploadTemplate: (o) ->
      $('.instructions').hide()
      console.log("uploadTemplate")
      rows = $()
      $.each o.files, (index, file) ->
        console.log(file)
        console.log("filename = " + file.name)
        console.log("size = " + o.formatFileSize(file.size))
        rows = rows.add(uploadRowHTML(file.name, o.formatFileSize(file.size), file.error))
      return rows
    downloadTemplate: (o) ->
      console.log("downloadtemplate")
      console.log(o)
      rows = $()

      $.each o.files, (index, file) ->
        console.log "looping over o.files in downloadTemplate..."
        console.log file

        console.log("filename = " + file.name)
        console.log("size = " + file.bytes)
        row = $(
          '<tr class="template-download fade">' +
          '<td class="filename-col span7">' +
          '<img class="sprite s_page_white_get image_icon" src="img/icon_spacer.gif" />' +
          '<span class="name"></span>' +
          '<span class="size"></span>' +
          '</td>' +
          '<td class="info-col span4"></td>' +
          '<td class="status-col span1">' +
          '<img class="sprite s_synced status_image" src="img/icon_spacer.gif" />' +
          '</td>' +
          "</tr>"
        )

        row.find('.name').text(file.name)
        row.find('.size').text('-' + o.formatFileSize(file.size)) if file.size
        # update the icon 
        $(row.find("img.s_page_white_get")[0]).addClass('s_' + file.icon).removeClass("s_page_white_get") if file.icon
        if file.error
          console.log "there are errors in the file: "
          console.log file.error_message
          console.log file.error
          row.find('.info-col').addClass('error').text(file.error)
          row.find('.status_image').removeClass('s_synced').addClass('s_error')
          row.find('.image_icon').removeClass('s_page_white_get').addClass('s_cross')
          console.log file.error_class
          if file.error_class == 'DropboxAuthError'
            console.log "it's an authentication error!"
            $('#re-authenticate').show()
            $('#upload_button').addClass('disabled')
            $('#upload_button input').prop("disabled", true)
        rows = rows.add(row)
      return rows
    # done: (e,data) ->
    #   console.log e
    #   console.log data
    #   $.each data.result, (index, file) ->
    #     console.log file
    #     console.log file.pat`h
    #     $('<p/>').text(file.path).appendTo(document.body)
  })
  
  # send text
  $("form#send_text").submit (e) ->
    e.preventDefault()

    $.post($(this).attr("action"), $(this).serialize(), (data, textStatus, jqXHR) -> 
      console.log("submitted!")
    )

  # dropzone effect
  $(document).bind 'dragover', (e) ->
    dropZone = $('#dropzone')
    timeout = window.dropZoneTimeout
    if !timeout
      dropZone.addClass('in') 
    else
      clearTimeout(timeout)
    if (e.target == dropZone[0])
      dropZone.addClass('hover');
    else
      dropZone.removeClass('hover');
    window.dropZoneTimeout = setTimeout (->
      window.dropZoneTimeout = null;
      dropZone.removeClass('in hover');
      ), 100