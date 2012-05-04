$ ->
  $('#upload').fileupload({
    dataType: 'json',
    autoUpload: true,
    uploadTemplateId: null,
    downloadTemplateId: null,
    uploadTemplate: (o) ->
      console.log("uploadTemplate")
      rows = $()
      $.each o.files, (index, file) ->
        console.log(file)
        console.log("filename = " + file.name)
        console.log("size = " + o.formatFileSize(file.size))
        row = $(
          '<tr class="template-upload fade">' +
          '<td class="filename-col span7">' +
          '<img class="sprite s_page_white_get" src="img/icon_spacer.gif" />' +
          '<span class="name"></span> - ' +
          '<span class="size"></span>' +
          '</td>' +
          '<td class="info-col span4"></td>' +
          '<td class="status-col span1">' +
          '<img class="" src="img/ajax-loading-small.gif" />' +
          '</td>' +
          "</tr>"
        )

        row.find('.name').text(file.name)
        row.find('.size').text(o.formatFileSize(file.size))
        row.find('.error').text(locale.fileupload.errors[file.error] || file.error) if file.error
        rows = rows.add(row)
      return rows
    downloadTemplate: (o) ->
      console.log("downloadtemplate")
      console.log(o)
      rows = $()
      $.each o.files, (index, file) ->
        console.log("filename = " + file.name)
        console.log("size = " + file.bytes)
        row = $(
          '<tr class="template-download fade">' +
          '<td class="filename-col span7">' +
          '<img class="sprite s_page_white_get" src="img/icon_spacer.gif" />' +
          '<span class="name"></span> - ' +
          '<span class="size"></span>' +
          '</td>' +
          '<td class="info-col span4"></td>' +
          '<td class="status-col span1">' +
          '<img class="sprite s_synced" src="img/icon_spacer.gif" />' +
          '</td>' +
          "</tr>"
        )

        row.find('.name').text(file.name)
        row.find('.size').text(o.formatFileSize(file.size))
        # update the icon 
        $(row.find("img.s_page_white_get")[0]).addClass('s_' + file.icon).removeClass("s_page_white_get")
        row.find('.error').text(locale.fileupload.errors[file.error] || file.error) if file.error
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