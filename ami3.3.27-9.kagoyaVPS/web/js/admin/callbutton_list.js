
jQuery(function($) {

  var $buttonID = $('#modal-edit-buttonid');
  var $roomID = $('#modal-edit-roomid');
  var $group = $('#modal-edit-group');
  var $name = $('#modal-edit-name');
  var $delButton = $('#modal-edit-delete-btn');
  var list;
  var editID = '';

  $('#tbody1').on('click', '.edit', function() {
    editID = $(this).data('id');
    clearModal();
    setModal(list[editID]);
    $delButton.show();
    $('#modal-edit').modal('show');
    return false;
  });

  $('#add-button').click(function() {
    clearModal();
    $('#modal-edit').modal('show');
  });

  function clearModal() {
    $delButton.hide();
    $buttonID.val('');
    $roomID.val('');
    $group.val('');
    $name.val('');
  }

  function setModal(item) {
    $buttonID.val(item["BUTTON_ID"]);
    $roomID.val(item["TARGET_ID"]);
    $group.val(item["BOOK_GRP"]);
    $name.val(item["NAME"]);
  }

  $delButton.click(function() {
    if (!confirm('削除しますか？')) {
      return false;
    }

    var postData = {
      "ID": editID
    };
    app.post('/del_callbutton', postData).done(function(data) {
      $('#tbody1').html('');
      if (data.STATUS == 'NG') {
        alert(data.MSG);
        return;
      } else if (data.STATUS == 'NOLOGIN') {
        location.href('/');
        return;
      }
      $('#modal-edit').modal('hide');
      getData();
    });
  });

  $('#modal-edit-btn').click(function() {
    var postData = {
      "BUTTON_ID": $buttonID.val(),
      "BOOK_GRP" : $group.val(),
      "TARGET_ID": $roomID.val(),
      "NAME": $name.val()
    };
    app.post('/save_callbutton', postData).done(function(data) {
      if (data.STATUS == 'NG') {
        alert(data.MSG);
        return;
      } else if (data.STATUS == 'NOLOGIN') {
        location.href('/');
        return;
      }
      $('#modal-edit').modal('hide');
      getData();
    });
  });

  function init() {
    getData();
  }

  function getData() {
    list = {};
    app.get('/callbutton_info', {}).done(function(data) {
      $('#tbody1').html('');
      if (data.STATUS == 'NG') {
        alert('コールボタン情報を取得できません');
        return;
      }
      addTableRow(data.LIST);
    });
  }

  function addTableRow(items) {
    var item, tr = '';
    for (var i = 0; i < items.length; i++) {
      item = items[i];
      tr = tr +
        '<tr>' +
        '<td><a href="#" class="edit" data-id="' + item["_id"] + '">' + item["BUTTON_ID"] + '</a></td>' +
        '<td>' + item["TARGET_ID"] + '</td>' +
        '<td>' + item["BOOK_GRP"] + '</td>' +
        '<td>' + item["NAME"] + '</td>' +
        '</tr>';
      list[item["_id"]] = item;
    }
    $('#tbody1').html(tr);
  }

  init();

});
