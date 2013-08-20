(function() {
  window.console || (window.console = {
    log: function() {
      return {};
    }
  });

  $(function() {
    var downloadRowHTML, uploadRowHTML;

    uploadRowHTML = function(filename, filesize, error) {
      var row;

      if (filesize == null) {
        filesize = -1;
      }
      if (error == null) {
        error = null;
      }
      row = $('<tr class="template-upload">' + '<td class="filename-col span7">' + '<img class="sprite s_page_white_get" src="/img/icon_spacer.gif" />' + '<span class="name"></span>' + '<span class="size"></span>' + '</td>' + '<td class="info-col span4">uploading to Dropbox...</td>' + '<td class="status-col span1">' + '<img class="" src="/img/ajax-loading-small.gif" />' + '</td>' + "</tr>");
      row.find('.name').text(filename);
      if (filesize !== -1) {
        row.find('.size').text(filesize);
      }
      if (error) {
        row.find('.error').text(error);
      }
      return row;
    };
    downloadRowHTML = function(file) {
      var row;

      row = $('<tr class="template-download">' + '<td class="filename-col span7">' + '<img class="sprite s_page_white_get image_icon" src="/img/icon_spacer.gif" />' + '<span class="name"></span>' + '<span class="size"></span>' + '</td>' + '<td class="info-col span4"></td>' + '<td class="status-col span1">' + '<img class="sprite s_synced status_image" src="/img/icon_spacer.gif" />' + '</td>' + "</tr>");
      row.find('.name').text(file.name);
      if (file.human_size) {
        row.find('.size').text('-' + file.human_size);
      }
      if (file.icon) {
        $(row.find("img.s_page_white_get")[0]).addClass('s_' + file.icon).removeClass("s_page_white_get");
      }
      if (file.error) {
        console.log("there are errors in the file: ");
        console.log(file.error_message);
        console.log(file.error);
        row.find('.info-col').addClass('error').text(file.error);
        row.find('.status_image').removeClass('s_synced').addClass('s_error');
        row.find('.image_icon').removeClass('s_page_white_get').addClass('s_cross');
        console.log(file.error_class);
      }
      return row;
    };
    $('#upload').fileupload({
      dataType: 'json',
      autoUpload: true,
      acceptFileTypes: /./,
      uploadTemplateId: null,
      downloadTemplateId: null,
      uploadTemplate: function(o) {
        var rows;

        $('.instructions').hide();
        console.log("uploadTemplate");
        rows = $();
        $.each(o.files, function(index, file) {
          console.log(file);
          console.log("filename = " + file.name);
          console.log("size = " + file.human_size);
          return rows = rows.add(uploadRowHTML(file.name, file.human_size, file.error));
        });
        return rows;
      },
      downloadTemplate: function(o) {
        var rows;

        console.log("downloadtemplate");
        console.log(o);
        rows = $();
        $.each(o.files, function(index, file) {
          console.log("looping over o.files in downloadTemplate...");
          console.log(file);
          console.log("filename = " + file.name);
          console.log("size = " + file.bytes);
          if (file.error && file.error_class === 'DropboxAuthError') {
            console.log("it's an authentication error!");
            $('#re-authenticate').show();
            $('#upload_button').addClass('disabled');
            $('#upload_button input').prop("disabled", true);
          }
          return rows = rows.add(downloadRowHTML(file));
        });
        return rows;
      }
    });
    $("#send_text").slideUp();
    $("#show_send_message").fadeIn();
    $("#show_send_message").click(function() {
      $(this).fadeOut();
      return $("#send_text").slideDown();
    });
    $("form#send_text").submit(function(e) {
      var filename, filename_value, form, formData, previous_submit_button_value, row, submit_button;

      e.preventDefault();
      form = $(this);
      formData = form.serialize();
      $('.instructions').hide();
      submit_button = form.children("input[type=submit]")[0];
      previous_submit_button_value = submit_button.value;
      submit_button.value = "Sending...";
      form.find("input, textarea").addClass("disabled").attr("disabled", "disabled");
      filename = $("#timestamp").text();
      filename_value = $("#filename").val();
      if (filename_value && filename_value !== "") {
        filename += " " + filename_value;
      }
      filename += ".txt";
      row = uploadRowHTML(filename);
      $('.filelist .files').append(row);
      console.log(form.attr("action"));
      return $.post(form.attr("action"), formData, function(data, textStatus, jqXHR) {
        console.log("text uploaded");
        form.find("input, textarea").removeClass("disabled").removeAttr("disabled");
        console.log(form);
        form[0].reset();
        submit_button.value = previous_submit_button_value;
        return $(row).replaceWith(downloadRowHTML(data[0]));
      });
    });
    return $(document).bind('dragover', function(e) {
      var dropZone, timeout;

      dropZone = $('#dropzone');
      timeout = window.dropZoneTimeout;
      $('.instructions').addClass('hover');
      if (!timeout) {
        dropZone.addClass('in');
      } else {
        clearTimeout(timeout);
      }
      if (e.target === dropZone[0]) {
        dropZone.addClass('hover');
      } else {
        dropZone.removeClass('hover');
      }
      return window.dropZoneTimeout = setTimeout((function() {
        $('.instructions').removeClass('hover');
        window.dropZoneTimeout = null;
        return dropZone.removeClass('in hover');
      }), 100);
    });
  });

}).call(this);
