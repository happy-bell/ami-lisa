
jQuery(function($) {

  var $modal = $('#modal-push');
  var $title = $('#modal-push-title');
  var $message = $('#modal-push-message');
  var list;
  var udid = '';

  $('#tbody1').on('click', '.push', function() {
    udid = $(this).data('id');
    clearModal();
    $modal.modal('show');
    return false;
  });

  function clearModal() {
    $title.val('');
    $message.val('');
  }

  $('#modal-push-btn').click(function() {
    var postData = {
      "TOKEN": list[udid]["token"],
      "TITLE" : $title.val(),
      "MESSAGE": $message.val()
    };
    app.post('/push_test', postData).done(function(data) {
      if (data.STATUS == 'NOLOGIN') {
        location.href('/');
        return;
      }
      $modal.modal('hide');
    });
  });

  function init() {
    getData();
  }

  function getData() {
    list = {};
    app.get('/push_info', {}).done(function(data) {
      $('#tbody1').html('');
      if (data.STATUS == 'NG') {
        alert('PUSH通知情報を取得できません');
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
          '<td>' + (i + 1) + '</td>' +
        '<td><a href="#" class="push" data-id="' + item["udid"] + '">' + item["udid"] + '</a></td>' +
        '<td>' + item["group"] + '</td>' +
        '<td><div class="token">' + item["token"] + '</div></td>' +
        '<td>' + '' + '</td>' +
        '</tr>';
      list[item["udid"]] = item;
    }
    $('#tbody1').html(tr);
  }

  init();

});
