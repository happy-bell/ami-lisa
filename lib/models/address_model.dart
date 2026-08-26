
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
      id: id.toString(),
      name: name.toString(),
      code: code,
      type: (type ?? '').toString(),
      status: int.tryParse((json['status'] ?? '0').toString()) ?? 0,
      call: int.tryParse((json['call'] ?? '0').toString()) ?? 0,
      called: int.tryParse((json['called'] ?? '0').toString()) ?? 0,
      userType: (json['userType'] ?? json['USER_TYPE'] ?? type ?? '').toString(),
      photo: (photo ?? '').toString(),
    );
  }

  static List<Address> fromJsonList(List<dynamic> json) {
    var list = <Address>[];
    for (var i = 0; i < json.length; i++) {
      final item = json[i];
      if (item is! Map) continue;
      var address = Address.fromJson(Map<String, dynamic>.from(item));
      list.add(address);
    }
    return list;
  }
}
