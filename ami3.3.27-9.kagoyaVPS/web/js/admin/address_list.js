
jQuery(function($) {

  $('#form1').submit(function() {
    if (!confirm('MCSから住所録を取得しますか？')) {
      return false;
    }
  });

  function init() {
    if (mcs == '1') {
      setTimeout(function(){toUpdate()}, 500);
    }
  }

  function toUpdate() {
    if (!confirm('取得しました。デリゲータに保存しますか？')) {
      return;
    }
    $('#form2').submit();
  }

  init();

});
