var utils = (function () {

  this.right = function(str, length) {
    if (typeof str === 'string') {
      var len = str.length;
      if (len < length) {
        return str;
      }
      return str.substr(len - length, length);
    }
    return '';
  };

  this.dateFormat = function(dt, f) {
    var ret = f
      , last
      , w = ["日","月","火","水","木","金","土"];
    if (ret.indexOf('yyyy') !== -1) {
      ret = ret.replace('yyyy', dt.getFullYear());
    }
    if (ret.indexOf('yy') !== -1) {
      ret = ret.replace('yy', dt.getFullYear().substr(2));
    }
    if (ret.indexOf('mm') !== -1) {
      ret = ret.replace('mm', this.right('' + '0' + (dt.getMonth() + 1), 2));
    }
    if (ret.indexOf('m') !== -1) {
      ret = ret.replace('m', (dt.getMonth() + 1));
    }
    if (ret.indexOf('dd') !== -1) {
      ret = ret.replace('dd', this.right('' + '0' + dt.getDate(), 2));
    }
    if (ret.indexOf('d') !== -1) {
      ret = ret.replace('d', dt.getDate());
    }
    if (ret.indexOf('H') !== -1) {
      ret = ret.replace('H', this.right('' + '0' + dt.getHours(), 2));
    }
    if (ret.indexOf('i') !== -1) {
      ret = ret.replace('i', this.right('' + '0' + dt.getMinutes(), 2));
    }
    if (ret.indexOf('s') !== -1) {
      ret = ret.replace('s', this.right('' + '0' + dt.getSeconds(), 2));
    }
    if (ret.indexOf('tt') !== -1) {
      last = new Date(dt.getFullYear(), dt.getMonth() + 1, 0);
      ret = ret.replace('tt', this.right('' + '0' + last.getDate(), 2));
    }
    if (ret.indexOf('t') !== -1) {
      last = new Date(dt.getFullYear(), dt.getMonth() + 1, 0);
      ret = ret.replace('t', last.getDate());
    }
    if (ret.indexOf('w') !== -1) {
      ret = ret.replace('w', w[dt.getDay()]);
    }
    return ret;
  };

  return this;
})();

module.exports = utils;