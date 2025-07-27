
if(! ('app' in window) ) window['app'] = {};
app.root = '/';
app.page = {};

app.get = function(url, postData) {
  var defer = $.Deferred();
  $.ajax({
    url: url,
    data: postData,
    type: 'GET',
    success: defer.resolve,
    error: defer.reject
  });
  return defer.promise();
};

app.post = function(url, postData) {
  var defer = $.Deferred();
  $.ajax({
    url: url,
    data: postData,
    type: 'POST',
    success: defer.resolve,
    error: defer.reject
  });
  return defer.promise();
};