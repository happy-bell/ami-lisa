
jQuery(function($) {

  function init() {
    var i
      , $selY = $('#syear')
      , $option
      , dt = new Date()
      , year = dt.getFullYear()
      , month = dt.getMonth() + 1
      , day = dt.getDate();

    for (i = minYear; i <= maxYear; i++) {
      $option = $('<option>')
        .val(i)
        .text(i);
      if (i == year) {
        $option.prop('selected', true);
      }
      $selY.append($option);
    }

    $('#smonth').val(month);
    $('#sday').val(day);

    selChanged();
  }

  $('select').on('change', function() {
    selChanged();
  });

  function selChanged() {
    var year = $('#syear').val()
      , month = $('#smonth').val()
      , day = $('#sday').val()
      , doc = $('#sdoc').val()
      , pat = $('#spat').val()
      , $this;
    $('tr[data-year]').each(function() {
      $this = $(this);
      if ($this.data('year') != year) {
        $this.hide();
        return;
      }
      if ($this.data('month') != month) {
        $this.hide();
        return;
      }
      if ($this.data('day') != day) {
        $this.hide();
        return;
      }
      if (doc.length > 0) {
        if ($this.data('id1') != doc && $this.data('id2') != doc) {
          $this.hide();
          return;
        }
      }
      if (pat.length > 0) {
        if ($this.data('id1') != pat && $this.data('id2') != pat) {
          $this.hide();
          return;
        }
      }
      $this.show();
    });
  }

  init();


});