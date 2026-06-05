// Models used across the Platform Admin / Company Admin / Site Admin flows.

class AdminUser {
  final String userId;
  final String name;
  final String email;
  final String role;
  final String company;
  final String site;
  final String bucket;
  final String? serviceType;
  final String? zoneId;

  AdminUser({
    required this.userId,
    required this.name,
    required this.email,
    this.role = '',
    this.company = '',
    this.site = '',
    this.bucket = '',
    this.serviceType,
    this.zoneId,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      userId: (json['userId'] ?? json['SiteTechnicianId'] ?? json['siteTechnicianId'] ?? json['companyAdminId'] ?? json['adminId'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? json['userName'] ?? '').toString(),
      email: (json['email'] ?? json['Email'] ?? '').toString(),
      role: (json['role'] ?? json['Role'] ?? '').toString(),
      company: (json['company'] ?? json['Company'] ?? json['CompanyId'] ?? json['companyId'] ?? '').toString(),
      site: (json['site'] ?? json['Site'] ?? json['SiteId'] ?? json['siteId'] ?? '').toString(),
      bucket: (json['bucket'] ?? json['Bucket'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? json['ServiceType'])?.toString(),
      zoneId: (json['zoneId'] ?? json['zone'] ?? json['ZoneId'] ?? json['Zone'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'email': email,
    'role': role,
    'company': company,
    'site': site,
    'bucket': bucket,
    if (serviceType != null) 'serviceType': serviceType,
    if (zoneId != null) 'zoneId': zoneId,
  };
}

class Company {
  final String companyId;
  final String name;
  final String? bucket;
  final String? city;
  final String? state;
  final String? country;
  final double? latitude;
  final double? longitude;

  Company({
    required this.companyId,
    required this.name,
    this.bucket,
    this.city,
    this.state,
    this.country,
    this.latitude,
    this.longitude,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      companyId: (json['companyId'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? json['companyName'] ?? 'Unnamed Company').toString(),
      bucket: json['bucket']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString(),
      latitude: _parseDouble(json['latitude'] ?? json['lat']),
      longitude: _parseDouble(json['longitude'] ?? json['lng'] ?? json['lon']),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, dynamic> toJson() => {
    'companyId': companyId,
    'name': name,
    'bucket': bucket,
    'city': city,
    'state': state,
    'country': country,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class Site {
  final String siteId;
  final String name;
  final String shortId;
  final String? companyId;
  final String? spocName;
  final String? spocEmail;
  final String? zoneId;
  final String? city;
  final String? state;
  final String? country;
  final double? latitude;
  final double? longitude;

  Site({
    required this.siteId,
    required this.name,
    required this.shortId,
    this.companyId,
    this.spocName,
    this.spocEmail,
    this.zoneId,
    this.city,
    this.state,
    this.country,
    this.latitude,
    this.longitude,
  });

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      siteId: (json['siteId'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? json['siteName'] ?? 'Unnamed Site').toString(),
      shortId: (json['shortId'] ?? json['siteShortId'] ?? '').toString(),
      companyId: json['companyId']?.toString(),
      spocName: json['spocName']?.toString(),
      spocEmail: json['spocEmail']?.toString(),
      zoneId: json['zoneId']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString(),
      latitude: parseCoordinate(json['latitude'] ?? json['lat'] ?? json['Latitude'], isLatitude: true),
      longitude: parseCoordinate(json['longitude'] ?? json['lng'] ?? json['lon'] ?? json['Longitude'], isLatitude: false),
    );
  }

  /// Parses latitude/longitude from numbers or formatted strings (e.g. `13.08° N`).
  static double? parseCoordinate(dynamic value, {required bool isLatitude}) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty) return null;

    final direct = double.tryParse(str);
    if (direct != null) {
      final minVal = isLatitude ? -90.0 : -180.0;
      final maxVal = isLatitude ? 90.0 : 180.0;
      if (direct >= minVal && direct <= maxVal) return direct;
      return null;
    }

    try {
      final clean = str
          .replaceAll('~', '')
          .replaceAll('°', '')
          .replaceAll(' ', '')
          .replaceAll('\u202f', '')
          .trim();
      final isNegative =
          clean.endsWith('S') || clean.endsWith('W') || clean.startsWith('-');
      final numericStr = clean.replaceAll(RegExp(r'[a-zA-Z]'), '');
      final val = double.tryParse(numericStr);
      if (val == null) return null;
      final finalVal = isNegative ? -val : val;
      final minVal = isLatitude ? -90.0 : -180.0;
      final maxVal = isLatitude ? 90.0 : 180.0;
      if (finalVal >= minVal && finalVal <= maxVal) return finalVal;
    } catch (_) {}
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, dynamic> toJson() => {
    'siteId': siteId,
    'name': name,
    'shortId': shortId,
    'companyId': companyId,
    'spocName': spocName,
    'spocEmail': spocEmail,
    'zoneId': zoneId,
    'city': city,
    'state': state,
    'country': country,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class Zone {
  final String zoneId;
  final String companyId;
  final String name;
  final String shortId;

  Zone({
    required this.zoneId,
    required this.companyId,
    required this.name,
    required this.shortId,
  });

  factory Zone.fromJson(Map<String, dynamic> json) {
    return Zone(
      zoneId: json['zoneId']?.toString() ?? json['ZoneId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? json['CompanyId']?.toString() ?? '',
      name: json['name']?.toString() ?? json['Name']?.toString() ?? 'Unnamed Zone',
      shortId: json['shortId']?.toString() ?? json['ShortId']?.toString() ?? '',
    );
  }
}
