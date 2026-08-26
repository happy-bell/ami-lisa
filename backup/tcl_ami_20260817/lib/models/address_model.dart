
class Address {
  String id;
  String name;
  String code;
  String type;
  int status;
  int call;
  int called;
  int supported = 0;
  int watching = 0;
  String userType;
  String photo = '';
  String liveimage = '';
  String sensor = '';
  List<dynamic> sensors = [];

  Address({
    required this.id,
    required this.name,
    required this.code,
    required this.type,
    required this.status,
    required this.call,
    required this.called,
    required this.userType,
    required this.photo,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    var id = json.keys.contains("id") ? json['id'] : json['TARGET_ID'];
    var name = json.keys.contains("name") ? json['name'] : json['NAME'];
    var type = json.keys.contains("type") ? json['type'] : (json.keys.contains("userType") ? json['userType'] : json['USER_TYPE']);
    var photo = json.keys.contains("photo") ? json['photo'] : json['PHOTO'];

    var code = '';
    if (json.keys.contains("code")) {
      code = json['code'].toString();
    } else if (json.keys.contains("bookGrp")) {
      code = json['bookGrp'].toString();
    } else if (json.keys.contains("BOOK_GRP")) {
      code = json['BOOK_GRP'].toString();
    }

    return Address(
      id: id,
      name: name,
      code: code,
      type: type,
      status: int.parse(json['status']),
      call: int.parse(json['call']),
      called: int.parse(json['called']),
      userType: json['userType'],
      photo: photo
    );
  }

  static List<Address> fromJsonList(List<dynamic> json) {
    var list = <Address>[];
    for (var i = 0; i < json.length; i++) {
      var address = Address.fromJson(json[i]);
      list.add(address);
    }
    return list;
  }
}
