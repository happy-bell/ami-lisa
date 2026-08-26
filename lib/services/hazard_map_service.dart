import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/jma_area_location.dart';

/// 表示地点は「設定 → 天気予報」で選んだ地域に合わせる。
/// 未設定のときは岐阜県を使う（[JmaAreaLocation.fallbackCode]）。
double get hazardLatitude =>
    JmaAreaLocation.latOf(AppManager.weatherArea);
double get hazardLongitude =>
    JmaAreaLocation.lonOf(AppManager.weatherArea);
String get hazardAreaLabel =>
    JmaAreaLocation.labelOf(AppManager.weatherArea);

/// APIキーを配布するサーバー側エンドポイント（46amip4 → newhealthcare46amip4 経由）。
/// AppDefine.baseURL（fun-talk.net）とは別系統のため絶対URLで保持する。
const String _hazardKeyEndpoint =
    'https://mcs-a.com/frinurse/newhealthcare46amip4/hazardmap_key.php';

const String _reinfolibBase =
    'https://www.reinfolib.mlit.go.jp/ex-api/external';

class HazardLayerResult {
  HazardLayerResult({
    required this.label,
    required this.hasRisk,
    required this.detail,
  });

  final String label;
  final bool hasRisk;
  final String detail;
}

class ShelterResult {
  ShelterResult({required this.name, required this.address});
  final String name;
  final String address;
}

class TileXY {
  const TileXY(this.x, this.y);
  final int x;
  final int y;
}

class HazardMapData {
  HazardMapData({
    required this.layers,
    required this.shelter,
    required this.tileZ,
    required this.tileX,
    required this.tileY,
  });

  final List<HazardLayerResult> layers;
  final ShelterResult? shelter;
  final int tileZ;
  final int tileX;
  final int tileY;
}

class HazardMapService {
  HazardMapService._();
  static final HazardMapService instance = HazardMapService._();

  String? _cachedKey;

  Future<String?> _fetchKey() async {
    if (_cachedKey != null) return _cachedKey;
    try {
      final res = await http
          .get(Uri.parse(_hazardKeyEndpoint))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _cachedKey = data['key']?.toString();
      }
    } catch (e) {
      print('[HazardMap] key fetch error $e');
    }
    return _cachedKey;
  }

  /// 緯度経度 → タイル座標(z/x/y)。国土地理院・不動産情報ライブラリ共通のWebメルカトル方式。
  static TileXY latLonToTile(double lat, double lon, int z) {
    final n = pow(2, z).toDouble();
    final x = ((lon + 180) / 360 * n).floor();
    final latRad = lat * pi / 180;
    final y = ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n).floor();
    return TileXY(x, y);
  }

  Future<Map<String, dynamic>?> _fetchLayer(
    String layerId,
    int z,
    int x,
    int y,
    String key,
  ) async {
    final url = Uri.parse(
        '$_reinfolibBase/$layerId?response_format=geojson&z=$z&x=$x&y=$y');
    try {
      final res = await http.get(url, headers: {
        'Ocp-Apim-Subscription-Key': key
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 204 || res.statusCode == 404) return null;
      if (res.statusCode != 200) return null;
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (e) {
      print('[HazardMap] layer $layerId fetch error $e');
      return null;
    }
  }

  List<dynamic> _features(Map<String, dynamic>? geojson) {
    final f = geojson?['features'];
    return f is List ? f : const [];
  }

  /// [lat]/[lon] 未指定時は「設定 → 天気予報」で選んだ地域の座標を使う。
  Future<HazardMapData> fetchAll({double? lat, double? lon}) async {
    final useLat = lat ?? hazardLatitude;
    final useLon = lon ?? hazardLongitude;
    // ignore: avoid_print
    print('[HazardMap] area=${AppManager.weatherArea} '
        'label=$hazardAreaLabel lat=$useLat lon=$useLon');
    final key = await _fetchKey();
    final tile15 = latLonToTile(useLat, useLon, 15);

    final layers = <HazardLayerResult>[];

    if (key == null) {
      layers.add(HazardLayerResult(
        label: '取得エラー',
        hasRisk: false,
        detail: 'APIキーの取得に失敗しました。ネットワーク接続を確認してください。',
      ));
      return HazardMapData(
        layers: layers,
        shelter: null,
        tileZ: 15,
        tileX: tile15.x,
        tileY: tile15.y,
      );
    }

    // 洪水浸水想定区域（想定最大規模）
    final flood = await _fetchLayer('XKT026', 15, tile15.x, tile15.y, key);
    final floodFeatures = _features(flood);
    layers.add(HazardLayerResult(
      label: '洪水',
      hasRisk: floodFeatures.isNotEmpty,
      detail: floodFeatures.isEmpty
          ? '該当する浸水想定なし'
          : '浸水深ランク: ${floodFeatures.first['properties']?['A31a_205'] ?? '不明'}',
    ));

    // 津波浸水想定
    final tsunami = await _fetchLayer('XKT028', 15, tile15.x, tile15.y, key);
    final tsunamiFeatures = _features(tsunami);
    layers.add(HazardLayerResult(
      label: '津波',
      hasRisk: tsunamiFeatures.isNotEmpty,
      detail: tsunamiFeatures.isEmpty
          ? '該当する浸水想定なし'
          : '浸水深: ${tsunamiFeatures.first['properties']?['A40_003'] ?? '不明'}',
    ));

    // 高潮浸水想定区域
    final hightide = await _fetchLayer('XKT027', 13, tile15.x, tile15.y, key);
    final hightideFeatures = _features(hightide);
    layers.add(HazardLayerResult(
      label: '高潮',
      hasRisk: hightideFeatures.isNotEmpty,
      detail: hightideFeatures.isEmpty
          ? '該当する浸水想定なし'
          : '浸水深: ${hightideFeatures.first['properties']?['A49_003'] ?? '不明'}',
    ));

    // 土砂災害警戒区域
    final sediment = await _fetchLayer('XKT029', 15, tile15.x, tile15.y, key);
    final sedimentFeatures = _features(sediment);
    layers.add(HazardLayerResult(
      label: '土砂災害',
      hasRisk: sedimentFeatures.isNotEmpty,
      detail: sedimentFeatures.isEmpty
          ? '該当する警戒区域なし'
          : '区域区分コード: ${sedimentFeatures.first['properties']?['A33_002'] ?? '不明'}',
    ));

    // 指定緊急避難場所（最寄り1件）
    ShelterResult? shelter;
    final shelterData =
        await _fetchLayer('XGT001', 15, tile15.x, tile15.y, key);
    final shelterFeatures = _features(shelterData);
    if (shelterFeatures.isNotEmpty) {
      final props = shelterFeatures.first['properties'] ?? {};
      shelter = ShelterResult(
        name: (props['facility_name_ja'] ?? '不明').toString(),
        address: (props['address_ja'] ?? '').toString(),
      );
    }

    return HazardMapData(
      layers: layers,
      shelter: shelter,
      tileZ: 15,
      tileX: tile15.x,
      tileY: tile15.y,
    );
  }
}
