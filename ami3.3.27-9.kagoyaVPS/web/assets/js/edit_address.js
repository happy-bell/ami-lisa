
jQuery(function($) {
  var cnt = $('#tbody1 tr').size();

  $('#addbtn').click(function() {
    var tr1 = $('[name="name1"]').closest('tr').clone();
    var tds = tr1.children();
    $(tds[0]).text(cnt);
    tr1.find('input').each(function() {
      var $this = $(this);
      var na = $this.attr('name');
      $this.val('');
      $this.attr('name', na.replace('1', cnt));
    });
    tr1.find('select').each(function() {
      var $this = $(this);
      var na = $this.attr('name');
      $this.val('');
      $this.attr('name', na.replace('1', cnt));
    });

    $('#tbody1').append(tr1);
    cnt++;
  });

  $('#tbody1').on('click', '.delbtn', function() {
    var tr = $(this).closest('tr');
    $(tr).remove();
  });
});