import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';

/// Service to interact with the ProvisionService admin endpoints.
class AdminService {
  // ── Helpers ─────────────────────────────────────────────────────────
  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getCookieHeader() ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Cookie': 'auth_token=$token',
      'Content-Type': 'application/json',
    };
  }

  /// Cookie-only headers for auth-service admin endpoints (matches diesel app).
  static Future<Map<String, String>?> _authCookieHeaders() async {
    final token = await AuthService.getCookieHeader();
    if (token == null || token.isEmpty) return null;
    final cookie = token.contains('auth_token=') ? token : 'auth_token=$token';
    return {
      'Content-Type': 'application/json',
      'Cookie': cookie,
    };
  }

  // ── Companies ───────────────────────────────────────────────────────

  /// Fetch all companies visible to the current user.
  static Future<List<Map<String, dynamic>>> fetchCompanies() async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/companies';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      debugPrint('⚠️ [AdminService] fetchCompanies status: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ [AdminService] fetchCompanies error: $e');
    }
    return [];
  }

  /// Fetch a single company by its ID.
  static Future<Map<String, dynamic>> fetchCompanyById(String companyId) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/companies/$companyId';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('❌ [AdminService] fetchCompanyById error: $e');
    }
    return {};
  }

  // ── Sites ───────────────────────────────────────────────────────────

  /// Fetch sites for a given company.
  static Future<List<Map<String, dynamic>>> fetchSites({
    required String companyId,
    String bucket = '',
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/sites?companyId=$companyId&bucket=$bucket';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('❌ [AdminService] fetchSites error: $e');
    }
    return [];
  }

  // ── Zones ───────────────────────────────────────────────────────────

  /// Fetch zones.
  static Future<List<Map<String, dynamic>>> fetchZones() async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/zones';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('❌ [AdminService] fetchZones error: $e');
    }
    return [];
  }

  // ── Company Admins ──────────────────────────────────────────────────

  /// Fetch all company admins (platform-level view).
  static Future<Map<String, dynamic>> fetchCompanyAdmins() async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/platform-admin/company-admins?pageSize=10000';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body;
      }
    } catch (e) {
      debugPrint('❌ [AdminService] fetchCompanyAdmins error: $e');
    }
    return {'status': 0, 'data': []};
  }

  /// Create a new company admin.
  static Future<Map<String, dynamic>> createCompanyAdmin({
    required String name,
    required String email,
    required String password,
    required String companyId,
    String? bucket,
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/platform-admin/company-admins';
      debugPrint('📡 [AdminService] POST $url');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'companyId': companyId,
          'bucket': bucket ?? '',
          'role': 'companyAdmin',
        }),
      ).timeout(const Duration(seconds: 10));

      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          return body;
        }
      } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'status': 1};
      }
    } catch (e) {
      debugPrint('❌ [AdminService] createCompanyAdmin error: $e');
    }
    return {'status': 0};
  }

  /// Delete a company admin by userId.
  static Future<void> deleteCompanyAdmin(String userId) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/company-admins/$userId';
      debugPrint('📡 [AdminService] DELETE $url');

      await http.delete(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('❌ [AdminService] deleteCompanyAdmin error: $e');
    }
  }

  /// Update a company admin.
  static Future<Map<String, dynamic>> updateCompanyAdmin({
    required String userId,
    required String name,
    required String email,
    String? password,
    String? companyId,
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/company-admins/$userId';
      debugPrint('📡 [AdminService] PUT $url');

      final body = <String, dynamic>{
        'name': name,
        'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
        if (companyId != null) 'companyId': companyId,
      };

      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {}

      if (response.statusCode == 200) {
        return {'status': 1};
      }
    } catch (e) {
      debugPrint('❌ [AdminService] updateCompanyAdmin error: $e');
    }
    return {'status': 0};
  }

  // ── Admins (Site-level) — auth service (same as diesel app) ─────────

  /// Fetch admins for a specific company (site-admin level).
  static Future<Map<String, dynamic>> fetchAdminsForCompany({
    required String companyId,
    String bucket = '',
    int page = 1,
    int pageSize = 10000,
  }) async {
    try {
      final headers = await _authCookieHeaders();
      if (headers == null) {
        return {'status': 0, 'error': 'No authentication cookie found', 'data': null};
      }

      final url =
          '${AppConfig.authBaseUrl}/users/admins?page=$page&pageSize=$pageSize&companyId=${Uri.encodeComponent(companyId)}&bucket=${Uri.encodeComponent(bucket)}';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('❌ [AdminService] fetchAdminsForCompany status: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ [AdminService] fetchAdminsForCompany error: $e');
    }
    return {'status': 0, 'data': []};
  }

  /// Create a new site-level admin via auth register endpoint.
  static Future<Map<String, dynamic>> createAdmin({
    required String name,
    required String email,
    required String password,
    required String role,
    required String companyId,
    required String bucket,
    required String siteId,
  }) async {
    try {
      final headers = await _authCookieHeaders();
      if (headers == null) {
        return {'status': 0, 'error': 'No authentication cookie found'};
      }

      final url =
          '${AppConfig.authBaseUrl}/register?companyId=${Uri.encodeComponent(companyId)}&bucket=${Uri.encodeComponent(bucket)}';
      debugPrint('📡 [AdminService] POST $url');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'role': role,
          'Company': companyId,
          'site': siteId,
          'siteId': siteId,
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint('📡 [AdminService] createAdmin status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        Map<String, dynamic>? data;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) data = decoded;
        } catch (_) {}
        return {
          'status': 1,
          'message': 'Admin created successfully',
          if (data != null) 'data': data,
        };
      }

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return {
            'status': 0,
            'error': decoded['message'] ?? decoded['Message'] ?? decoded['error'] ?? 'Failed to create admin',
          };
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ [AdminService] createAdmin error: $e');
      return {'status': 0, 'error': 'Exception: $e'};
    }
    return {'status': 0, 'error': 'Failed to create admin'};
  }

  /// Update a site admin.
  static Future<Map<String, dynamic>> updatePlatformAdmin({
    required String userId,
    required String name,
    required String email,
    String? password,
    String? company,
    String? siteId,
  }) async {
    try {
      final headers = await _authCookieHeaders();
      if (headers == null) {
        return {'status': 0, 'error': 'No authentication cookie found'};
      }

      final url = Uri.parse('${AppConfig.authBaseUrl}/users/admins/$userId');
      debugPrint('📡 [AdminService] PUT $url');

      final bodyMap = <String, dynamic>{
        'name': name,
        'email': email,
        'role': 'admin',
        if (siteId != null && siteId.isNotEmpty) ...{
          'site': siteId,
          'siteId': siteId,
        },
      };
      if (password != null && password.isNotEmpty) {
        bodyMap['password'] = password;
      }
      if (company != null && company.isNotEmpty) {
        bodyMap['company'] = company;
      }

      final response = await http.put(
        url,
        headers: headers,
        body: jsonEncode(bodyMap),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('❌ [AdminService] updatePlatformAdmin error: $e');
    }
    return {'status': 0, 'error': 'Failed to update admin'};
  }

  /// Delete a site admin.
  static Future<Map<String, dynamic>> deletePlatformAdmin(String userId) async {
    try {
      final headers = await _authCookieHeaders();
      if (headers == null) {
        return {'status': 0, 'error': 'No authentication cookie found'};
      }

      final url = Uri.parse('${AppConfig.authBaseUrl}/users/admins/$userId');
      debugPrint('📡 [AdminService] DELETE $url');

      final response = await http.delete(url, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('❌ [AdminService] deletePlatformAdmin error: $e');
    }
    return {'status': 0, 'error': 'Failed to delete admin'};
  }

  // ── Site Technicians (Employees) ────────────────────────────────────

  /// Fetch site technicians (employees) for a company.
  /// Calls the AuthService which owns user management.
  static Future<Map<String, dynamic>> fetchSiteTechnicians({
    required String companyId,
  }) async {
    try {
      final headers = await _authCookieHeaders();
      if (headers == null) return {'status': 0, 'data': []};

      final url = '${AppConfig.authBaseUrl}/users/site-technicians?companyId=$companyId&all=true';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('📥 [AdminService] fetchSiteTechnicians status: ${response.statusCode} body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('❌ [AdminService] fetchSiteTechnicians error: $e');
    }
    return {'status': 0, 'data': []};
  }

  /// Create a site technician (employee).
  /// POSTs to the AuthService /register endpoint which handles all user creation.
  /// Valid roles: site_technician, zone_technician, technician
  static Future<Map<String, dynamic>> createSiteTechnician({
    required String name,
    required String email,
    required String password,
    required String role,
    required String companyId,
    required String siteId,
    required String serviceType,
    String? zoneId,
    String? bucket,
  }) async {
    try {
      final headers = await _authCookieHeaders();
      if (headers == null) {
        return {'status': 0, 'error': 'No authentication cookie found'};
      }

      final url = Uri.parse('${AppConfig.authBaseUrl}/register');
      debugPrint('📡 [AdminService] POST $url (createSiteTechnician)');

      final payload = {
        'name': name,
        'email': email,
        'password': password,
        'role': role,       // e.g. site_technician, zone_technician, technician
        'companyId': companyId,
        'siteId': siteId,
        if (zoneId != null && zoneId.isNotEmpty) 'zoneId': zoneId,
        'serviceType': serviceType,
      };
      debugPrint('📦 [AdminService] createSiteTechnician payload: $payload');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 [AdminService] createSiteTechnician status: ${response.statusCode} body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      // Return the error body so the UI can display it
      try {
        final errorBody = jsonDecode(response.body);
        return {'status': 0, 'error': errorBody['message'] ?? errorBody.toString()};
      } catch (_) {
        return {'status': 0, 'error': 'Server returned ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('❌ [AdminService] createSiteTechnician error: $e');
    }
    return {'status': 0, 'error': 'Failed to create employee'};
  }

  /// Delete a site technician.
  static Future<void> deleteSiteTechnician(String employeeId) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/site-technicians/$employeeId';
      debugPrint('📡 [AdminService] DELETE $url');

      await http.delete(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('❌ [AdminService] deleteSiteTechnician error: $e');
    }
  }

  /// Update a site technician (employee).
  static Future<Map<String, dynamic>> updateSiteTechnician({
    required String employeeId,
    required String name,
    required String email,
    String? password,
    required String companyId,
    required String siteId,
    String? zoneId,
    required String serviceType,
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/site-technicians/$employeeId';
      debugPrint('📡 [AdminService] PUT $url');

      final body = <String, dynamic>{
        'name': name,
        'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
        'type': 'siteTechnician',
        'company': companyId,
        'site': siteId,
        if (zoneId != null && zoneId.isNotEmpty) 'zone': zoneId,
        'serviceType': serviceType,
      };

      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 [AdminService] updateSiteTechnician status: ${response.statusCode} body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }

      try {
        final errorBody = jsonDecode(response.body);
        return {'status': 0, 'error': errorBody['message'] ?? errorBody.toString()};
      } catch (_) {
        return {'status': 0, 'error': 'Server returned status ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('❌ [AdminService] updateSiteTechnician error: $e');
    }
    return {'status': 0, 'error': 'Failed to update employee'};
  }

  // ── Site Admins ─────────────────────────────────────────────────────

  /// Fetch all site admins (platform-level view).
  static Future<Map<String, dynamic>> fetchSiteAdmins() async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/platform-admin/site-admins?pageSize=10000';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body;
      }
    } catch (e) {
      debugPrint('❌ [AdminService] fetchSiteAdmins error: $e');
    }
    return {'status': 0, 'data': []};
  }

  /// Create a new site admin.
  static Future<Map<String, dynamic>> createSiteAdmin({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required String siteId,
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/platform-admin/site-admins';
      debugPrint('📡 [AdminService] POST $url');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'companyId': companyId,
          'siteId': siteId,
          'role': 'siteAdmin',
        }),
      ).timeout(const Duration(seconds: 10));

      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          return body;
        }
      } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'status': 1};
      }
    } catch (e) {
      debugPrint('❌ [AdminService] createSiteAdmin error: $e');
    }
    return {'status': 0};
  }

  /// Update a site admin.
  static Future<Map<String, dynamic>> updateSiteAdmin({
    required String userId,
    required String name,
    required String email,
    String? password,
    String? companyId,
    String? siteId,
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/site-admins/$userId';
      debugPrint('📡 [AdminService] PUT $url');

      final body = <String, dynamic>{
        'name': name,
        'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
        if (companyId != null) 'companyId': companyId,
        if (siteId != null) 'siteId': siteId,
      };

      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {}

      if (response.statusCode == 200) {
        return {'status': 1};
      }
    } catch (e) {
      debugPrint('❌ [AdminService] updateSiteAdmin error: $e');
    }
    return {'status': 0};
  }

  /// Delete a site admin by userId.
  static Future<void> deleteSiteAdmin(String userId) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.authBaseUrl}/users/site-admins/$userId';
      debugPrint('📡 [AdminService] DELETE $url');

      await http.delete(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('❌ [AdminService] deleteSiteAdmin error: $e');
    }
  }

  // ── Systems and System Types ────────────────────────────────────────

  /// Fetch all system types.
  static Future<List<Map<String, dynamic>>> fetchSystemTypes() async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/systemtypes';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('❌ [AdminService] fetchSystemTypes error: $e');
    }
    return [];
  }

  /// Create a new system.
  static Future<Map<String, dynamic>> createSystem(Map<String, dynamic> payload) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/systems';
      debugPrint('📡 [AdminService] POST $url');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 [AdminService] createSystem response status: ${response.statusCode}');

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'status': 1,
          'message': body['message'] ?? 'System created successfully',
          'data': body['data'],
        };
      } else {
        return {
          'status': 0,
          'error': body['message'] ?? body['error'] ?? 'Failed to create system',
        };
      }
    } catch (e) {
      debugPrint('❌ [AdminService] createSystem error: $e');
      return {'status': 0, 'error': 'Exception: $e'};
    }
  }

  /// Fetch all systems for a given company and site.
  static Future<List<Map<String, dynamic>>> fetchSystems({
    required String companyId,
    required String siteId,
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/systems?companyId=$companyId&siteId=$siteId';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      debugPrint('⚠️ [AdminService] fetchSystems status: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ [AdminService] fetchSystems error: $e');
    }
    return [];
  }

  /// Fetch all equipment types.
  static Future<List<Map<String, dynamic>>> fetchEquipmentTypes() async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/equipmenttypes';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      debugPrint('⚠️ [AdminService] fetchEquipmentTypes status: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ [AdminService] fetchEquipmentTypes error: $e');
    }
    return [];
  }

  /// Create a new equipment.
  static Future<Map<String, dynamic>> createEquipment(Map<String, dynamic> payload) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/equipments';
      debugPrint('📡 [AdminService] POST $url');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 [AdminService] createEquipment response status: ${response.statusCode}');

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'status': 1,
          'message': body['message'] ?? 'Equipment created successfully',
          'data': body['data'],
        };
      } else {
        return {
          'status': 0,
          'error': body['message'] ?? body['error'] ?? 'Failed to create equipment',
        };
      }
    } catch (e) {
      debugPrint('❌ [AdminService] createEquipment error: $e');
      return {'status': 0, 'error': 'Exception: $e'};
    }
  }

  /// Fetch all equipments for a given company and site.
  static Future<List<Map<String, dynamic>>> fetchEquipments({
    required String companyId,
    required String siteId,
  }) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/equipments?companyId=$companyId&siteId=$siteId';
      debugPrint('📡 [AdminService] GET $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      debugPrint('⚠️ [AdminService] fetchEquipments status: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ [AdminService] fetchEquipments error: $e');
    }
    return [];
  }

  /// Update an equipment.
  static Future<Map<String, dynamic>> updateEquipment(String equipmentId, Map<String, dynamic> payload) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/equipments/$equipmentId';
      debugPrint('📡 [AdminService] PUT $url');

      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 [AdminService] updateEquipment response status: ${response.statusCode}');

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'status': 1,
          'message': body['message'] ?? 'Equipment updated successfully',
          'data': body['data'],
        };
      } else {
        return {
          'status': 0,
          'error': body['message'] ?? body['error'] ?? 'Failed to update equipment',
        };
      }
    } catch (e) {
      debugPrint('❌ [AdminService] updateEquipment error: $e');
      return {'status': 0, 'error': 'Exception: $e'};
    }
  }

  /// Update an existing system.
  static Future<Map<String, dynamic>> updateSystem(String systemId, Map<String, dynamic> payload) async {
    try {
      final headers = await _authHeaders();
      final url = '${AppConfig.provisionBaseUrl}/systems/$systemId';
      debugPrint('📡 [AdminService] PUT $url');

      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 [AdminService] updateSystem response status: ${response.statusCode}');

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'status': 1,
          'message': body['message'] ?? 'System updated successfully',
          'data': body['data'],
        };
      } else {
        return {
          'status': 0,
          'error': body['message'] ?? body['error'] ?? 'Failed to update system',
        };
      }
    } catch (e) {
      debugPrint('❌ [AdminService] updateSystem error: $e');
      return {'status': 0, 'error': 'Exception: $e'};
    }
  }
}
