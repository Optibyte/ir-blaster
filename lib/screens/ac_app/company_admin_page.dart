import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/models/admin_model.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/sigin.dart';
import 'package:ir_blaster_ac/screens/main_navigation_page.dart';

class CompanyAdminPage extends StatefulWidget {
  const CompanyAdminPage({super.key});

  @override
  State<CompanyAdminPage> createState() => _CompanyAdminPageState();
}

class _CompanyAdminPageState extends State<CompanyAdminPage>
    with TickerProviderStateMixin {
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';

  List<AdminUser> admins = [];
  List<AdminUser> filteredAdmins = [];
  String searchTerm = '';

  Company? company;
  List<Site> sites = [];
  List<Zone> zones = [];

  // Map state
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  bool _mapReady = false; // Lazy-init: only show map when sites are loaded
  static const LatLng _indiaCenter = LatLng(20.5937, 78.9629);

  // Tab View state
  late TabController _tabController;

  // Admin User state
  List<AdminUser> adminUsers = [];
  List<AdminUser> filteredAdminUsers = [];
  String searchAdminUserTerm = '';
  bool isAdminUsersLoading = false;

  // Form controllers for Add Company Admin / Admin User
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  late TextEditingController _searchAdminController;
  late TextEditingController _searchAdminUserController;
  late TextEditingController _searchEmployeeController;

  // Employee User state
  List<AdminUser> employeeUsers = [];
  List<AdminUser> filteredEmployeeUsers = [];
  String searchEmployeeTerm = '';
  bool isEmployeeUsersLoading = false;
  bool _isAddingEmployee = false;

  String? _selectedCompanyId;
  String? _selectedSiteId;
  String? _selectedZoneId;
  String? _selectedRole = 'site_technician';
  String? _selectedServiceType = 'AC';
  bool _isAddingAdmin = false;

  // Edit form state
  String? _editingAdminId;
  bool _isEditingAdmin = false;
  String currentUserRole = 'companyAdmin';

  @override
  void initState() {
    super.initState();
    // Start with 2 tabs — correct for companyAdmin/admin (the typical users of this page).
    // Will be updated if a different role is found, avoiding the dispose→build gap crash.
    _tabController = TabController(length: 2, vsync: this);

    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _searchAdminController = TextEditingController();
    _searchAdminUserController = TextEditingController();
    _searchEmployeeController = TextEditingController();

    _loadInitialData();
    _searchAdminController.addListener(_onSearchChanged);
    _searchAdminUserController.addListener(_onSearchAdminUserChanged);
    _searchEmployeeController.addListener(_onSearchEmployeeChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapController?.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _searchAdminController.dispose();
    _searchAdminUserController.dispose();
    _searchEmployeeController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      searchTerm = _searchAdminController.text;
      _filterAdmins();
    });
  }

  void _onSearchAdminUserChanged() {
    setState(() {
      searchAdminUserTerm = _searchAdminUserController.text;
      _filterAdminUsers();
    });
  }

  void _onSearchEmployeeChanged() {
    setState(() {
      searchEmployeeTerm = _searchEmployeeController.text;
      _filterEmployeeUsers();
    });
  }

  void _filterEmployeeUsers() {
    if (searchEmployeeTerm.isEmpty) {
      filteredEmployeeUsers = List.from(employeeUsers);
    } else {
      final query = searchEmployeeTerm.toLowerCase();
      filteredEmployeeUsers = employeeUsers
          .where((emp) =>
              emp.name.toLowerCase().contains(query) ||
              emp.email.toLowerCase().contains(query))
          .toList();
    }
  }

  void _filterAdmins() {
    if (searchTerm.isEmpty) {
      filteredAdmins = List.from(admins);
    } else {
      final query = searchTerm.toLowerCase();
      filteredAdmins = admins
          .where((admin) =>
              admin.name.toLowerCase().contains(query) ||
              admin.email.toLowerCase().contains(query))
          .toList();
    }
  }

  void _filterAdminUsers() {
    if (searchAdminUserTerm.isEmpty) {
      filteredAdminUsers = List.from(adminUsers);
    } else {
      final query = searchAdminUserTerm.toLowerCase();
      filteredAdminUsers = adminUsers
          .where((admin) =>
              admin.name.toLowerCase().contains(query) ||
              admin.email.toLowerCase().contains(query))
          .toList();
    }
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.secondaryBackground,
        title: Text('Logout',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to logout?',
            style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Logout',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await AuthService.logout();
        if (!context.mounted) return;
        // Navigate to SignIn page
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SignInPage()),
          (route) => false,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout error: $e', style: GoogleFonts.poppins()),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => isLoading = true);
    try {
      final userData = await AuthService.getUserData();
      if (userData != null) {
        final role = userData['role']?.toString() ?? 'companyAdmin';
        final newTabCount = (role == 'admin' || role == 'companyAdmin') ? 2 : 3;

        if (_tabController.length != newTabCount) {
          // Safely swap: setState with the NEW controller first, THEN dispose the old.
          // This prevents the frame gap where the widget renders with a disposed controller.
          final old = _tabController;
          setState(() {
            currentUserRole = role;
            _tabController = TabController(length: newTabCount, vsync: this);
          });
          old.dispose(); // safe to dispose AFTER the new one is in the tree
        } else {
          setState(() => currentUserRole = role);
        }
      }
      await _loadCompanySites();
      await _fetchCompanyAdmins();
      await _fetchAdminUsers();
      await _fetchEmployeeUsers(showLocalLoader: false);
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchEmployeeUsers({bool showLocalLoader = true}) async {
    if (!mounted) return;
    if (showLocalLoader) {
      setState(() => isEmployeeUsersLoading = true);
    }
    try {
      final userData = await AuthService.getUserData();
      final companyId = AuthService.extractCompanyId(userData);

      if (companyId == null || companyId.isEmpty) return;

      final response = await AdminService.fetchSiteTechnicians(
        companyId: companyId,
      );

      List<AdminUser> parsedEmployees = [];
      final data = response['data'];

      List<dynamic> rawList = [];
      if (data is Map && data['SiteTechnicians'] is List) {
        rawList = data['SiteTechnicians'];
      } else if (data is Map && data['siteTechnicians'] is List) {
        rawList = data['siteTechnicians'];
      } else if (data is List) {
        rawList = data;
      }

      for (var item in rawList) {
        final adminData = item as Map<String, dynamic>;
        // Auth service returns SiteTechnicianId — normalise to userId
        if (!adminData.containsKey('userId') &&
            adminData.containsKey('siteTechnicianId')) {
          adminData['userId'] = adminData['siteTechnicianId'];
        }
        // Normalise companyId / siteId from GUID fields
        if (!adminData.containsKey('site') && adminData.containsKey('siteId')) {
          adminData['site'] = adminData['siteId']?.toString();
        }
        final user = AdminUser.fromJson(adminData);
        parsedEmployees.add(user);
      }

      if (!mounted) return;
      setState(() {
        employeeUsers = parsedEmployees;
        _filterEmployeeUsers();
      });
    } catch (e) {
      debugPrint('Error fetching employee users: $e');
    } finally {
      if (mounted && showLocalLoader) {
        setState(() => isEmployeeUsersLoading = false);
      }
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _zoomMapToMarkers();
  }

  void _zoomMapToMarkers() {
    if (_mapController == null) return;
    if (_markers.isEmpty) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_CompanyAdminPageState._indiaCenter, 5),
      );
      return;
    }
    final pos = _markers.first.position;
    if (pos.latitude >= 8.0 &&
        pos.latitude <= 38.0 &&
        pos.longitude >= 68.0 &&
        pos.longitude <= 98.0) {
      if (_markers.length == 1) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(pos, 10));
      } else {
        double minLat = pos.latitude, maxLat = pos.latitude;
        double minLng = pos.longitude, maxLng = pos.longitude;
        for (final m in _markers) {
          if (m.position.latitude < minLat) minLat = m.position.latitude;
          if (m.position.latitude > maxLat) maxLat = m.position.latitude;
          if (m.position.longitude < minLng) minLng = m.position.longitude;
          if (m.position.longitude > maxLng) maxLng = m.position.longitude;
        }
        const pad = 0.5;
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat - pad, minLng - pad),
              northeast: LatLng(maxLat + pad, maxLng + pad),
            ),
            60,
          ),
        );
      }
    } else {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_CompanyAdminPageState._indiaCenter, 5),
      );
    }
  }

  LatLng? _getValidSiteCoordinate(Site site) {
    final nameLower = site.name.toLowerCase();
    final shortIdLower = site.shortId.toLowerCase();

    if (nameLower.contains('dummy') ||
        shortIdLower.contains('funf') ||
        shortIdLower.contains('dummy')) {
      return null;
    }

    double? lat = site.latitude;
    double? lng = site.longitude;

    if (lat == null || lng == null) {
      final city = (site.city ?? '').toLowerCase();
      if (city.contains('chennai') || nameLower.contains('chennai')) {
        return const LatLng(13.0827, 80.2707);
      }
      if (nameLower.contains('madurai') || shortIdLower.contains('jnmac')) {
        return const LatLng(9.9252, 78.1198);
      }
      return null;
    }

    if (lng < 0) lng = lng.abs();

    if (lat >= 8.0 && lat <= 38.0 && lng >= 68.0 && lng <= 98.0) {
      return LatLng(lat, lng);
    }
    return null;
  }

  Future<void> _openSite(Site site) async {
    if (company == null) return;
    await AuthService.setSelectedSiteAndCompany(
      site.siteId,
      company!.companyId,
      zoneId: site.zoneId,
      bucket: company!.bucket,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MainNavigationPage()),
    );
  }

  Future<void> _loadCompanySites() async {
    try {
      final userData = await AuthService.getUserData();
      if (userData == null) return;

      final companyId = AuthService.extractCompanyId(userData) ?? '';
      if (companyId.isEmpty) return;

      final companyName =
          AuthService.extractCompanyName(userData) ?? 'My Company';
      final bucket = AuthService.extractBucket(userData) ?? '';

      final companyData = await AdminService.fetchCompanyById(companyId);
      Company fetchedCompany;
      if (companyData.isNotEmpty) {
        fetchedCompany = Company.fromJson(companyData);
      } else {
        fetchedCompany = Company(
          companyId: companyId,
          name: companyName,
          bucket: bucket,
        );
      }

      var sitesList = await AdminService.fetchSites(
        companyId: companyId,
        bucket: fetchedCompany.bucket ?? bucket,
      );

      if (sitesList.isEmpty && (fetchedCompany.bucket ?? '').isNotEmpty) {
        sitesList = await AdminService.fetchSites(companyId: companyId);
      }

      var parsedSites = sitesList
          .map((siteData) => Site.fromJson(siteData))
          .where((site) =>
              (site.companyId ?? '').trim().toLowerCase() ==
              companyId.trim().toLowerCase())
          .toList();

      final fetchedZones = await AdminService.fetchZones();
      var parsedZones = fetchedZones
          .map((z) => Zone.fromJson(z))
          .where((z) =>
              z.companyId.trim().toLowerCase() ==
              companyId.trim().toLowerCase())
          .toList();

      final userRole = AuthService.roleFromUserData(userData).toLowerCase();
      final userSiteId =
          (userData['site'] ?? userData['siteId'] ?? '').toString().trim();
      if (userRole == 'admin' && userSiteId.isNotEmpty) {
        parsedSites = parsedSites
            .where((site) =>
                site.siteId.trim().toLowerCase() == userSiteId.toLowerCase())
            .toList();
      }

      final tempMarkers = <Marker>{};
      for (final site in parsedSites) {
        final pos = _getValidSiteCoordinate(site);
        if (pos == null) continue;
        tempMarkers.add(
          Marker(
            markerId:
                MarkerId(site.siteId.isNotEmpty ? site.siteId : site.name),
            position: pos,
            infoWindow: InfoWindow(
              title: site.name,
              snippet: '${site.city ?? 'Unknown'}, ${site.state ?? 'Unknown'}',
              onTap: () => _openSite(site),
            ),
            onTap: () => _openSite(site),
          ),
        );
      }

      if (tempMarkers.isEmpty &&
          fetchedCompany.latitude != null &&
          fetchedCompany.longitude != null) {
        final lat = fetchedCompany.latitude!;
        final lng = fetchedCompany.longitude!;
        if (lat >= 8.0 && lat <= 38.0 && lng >= 68.0 && lng <= 98.0) {
          tempMarkers.add(
            Marker(
              markerId: MarkerId('company_$companyId'),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(title: fetchedCompany.name),
            ),
          );
        }
      }

      setState(() {
        company = fetchedCompany;
        sites = parsedSites;
        zones = parsedZones;
        _markers = tempMarkers;
        _selectedCompanyId = companyId;
        _mapReady = true; // Allow the map to render now that data is ready
      });

      _zoomMapToMarkers();
    } catch (e) {
      debugPrint('Error loading company sites: $e');
    }
  }

  Future<void> _fetchCompanyAdmins() async {
    try {
      final userData = await AuthService.getUserData();
      if (userData == null) return;

      final companyId = AuthService.extractCompanyId(userData) ?? '';
      if (companyId.isEmpty) return;

      final response = await AdminService.fetchCompanyAdmins();
      List<AdminUser> parsedAdmins = [];

      if (response['status'] != 0) {
        final data = response['data'];
        List<dynamic> rawList = [];
        if (data is Map && data['companyAdmins'] is List) {
          rawList = data['companyAdmins'];
        } else if (data is List) {
          rawList = data;
        }

        parsedAdmins = rawList.map((item) {
          final adminData = item as Map<String, dynamic>;
          if (!adminData.containsKey('userId') &&
              adminData.containsKey('companyAdminId')) {
            adminData['userId'] = adminData['companyAdminId'];
          }
          return AdminUser.fromJson(adminData);
        }).toList();
      }

      setState(() {
        admins = parsedAdmins;
        _filterAdmins();
      });
    } catch (e) {
      debugPrint('Error fetching company admins: $e');
    }
  }

  Future<void> _fetchAdminUsers() async {
    setState(() => isAdminUsersLoading = true);
    try {
      final userData = await AuthService.getUserData();
      final companyId = AuthService.extractCompanyId(userData) ?? '';
      final bucket =
          AuthService.extractBucket(userData) ?? company?.bucket ?? '';

      if (companyId.isEmpty) return;

      final response = await AdminService.fetchAdminsForCompany(
        companyId: companyId,
        bucket: bucket,
      );

      List<AdminUser> parsedAdminUsers = [];
      final data = response['data'];

      List<dynamic> rawList = [];
      if (data is Map && data['admins'] is List) {
        rawList = data['admins'];
      } else if (data is List) {
        rawList = data;
      }

      for (var item in rawList) {
        final adminData = item as Map<String, dynamic>;
        if (!adminData.containsKey('userId') &&
            adminData.containsKey('adminId')) {
          adminData['userId'] = adminData['adminId'];
        }
        final user = AdminUser.fromJson(adminData);
        final roleLower = user.role.toLowerCase();
        if (roleLower == 'admin' || roleLower.contains('admin')) {
          parsedAdminUsers.add(user);
        }
      }

      setState(() {
        adminUsers = parsedAdminUsers;
        _filterAdminUsers();
      });
    } catch (e) {
      debugPrint('Error fetching admin users: $e');
    } finally {
      setState(() => isAdminUsersLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: AppColors.button,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool _validateForm() {
    if (_nameController.text.isEmpty) {
      _showError('Please enter a name');
      return false;
    }
    if (_emailController.text.isEmpty) {
      _showError('Please enter an email');
      return false;
    }
    if (!_emailController.text.contains('@')) {
      _showError('Please enter a valid email');
      return false;
    }
    if (_passwordController.text.isEmpty) {
      _showError('Please enter a password');
      return false;
    }
    if (_passwordController.text.length < 6) {
      _showError('Password must be at least 6 characters');
      return false;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match');
      return false;
    }
    return true;
  }

  Future<void> _addAdminUser() async {
    if (!_validateForm()) return;

    if (_selectedSiteId == null || _selectedSiteId!.isEmpty) {
      _showError('Please assign a site to this Admin');
      return;
    }

    if (!mounted) return;
    setState(() => _isAddingAdmin = true);

    try {
      final userData = await AuthService.getUserData();
      final bucket =
          AuthService.extractBucket(userData) ?? company?.bucket ?? '';

      final response = await AdminService.createAdmin(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        role: 'admin',
        companyId: _selectedCompanyId!,
        bucket: bucket,
        siteId: _selectedSiteId!,
      );

      if (!mounted) return;

      if (response['status'] == 1) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _selectedSiteId = null;
        Navigator.pop(context);

        _showSuccess('Admin User created successfully');
        await _fetchAdminUsers();
      } else {
        _showError(
            response['error']?.toString() ?? 'Failed to create Admin User');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Error creating Admin User: $e');
    } finally {
      if (mounted) setState(() => _isAddingAdmin = false);
    }
  }

  Future<void> _updateAdminUser() async {
    if (_editingAdminId == null) return;

    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      _showError('Name and email are required');
      return;
    }

    setState(() => _isEditingAdmin = true);

    try {
      final response = await AdminService.updatePlatformAdmin(
        userId: _editingAdminId!,
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null,
        company: _selectedCompanyId,
        siteId: _selectedSiteId ?? '',
      );

      if (response['status'] != 0) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _editingAdminId = null;
        _selectedSiteId = null;
        if (context.mounted) Navigator.pop(context);

        _showSuccess('Admin User updated successfully');
        await _fetchAdminUsers();
      } else {
        _showError('Failed to update Admin User');
      }
    } catch (e) {
      _showError('Error updating Admin User: $e');
    } finally {
      setState(() => _isEditingAdmin = false);
    }
  }

  void _showEditAdminDialog(AdminUser admin) {
    _editingAdminId = admin.userId;
    _nameController.text = admin.name;
    _emailController.text = admin.email;
    _passwordController.clear();
    _confirmPasswordController.clear();

    // Find matching site id if any
    _selectedSiteId = sites.any((s) => s.siteId == admin.site)
        ? admin.site
        : (sites.isNotEmpty ? sites.first.siteId : null);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.secondaryBackground,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Admin User',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField(_nameController, 'Full Name', Icons.person_outline),
                const SizedBox(height: 12),
                _buildField(
                    _emailController, 'Email Address', Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _buildField(_passwordController, 'New Password (Optional)',
                    Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedSiteId,
                  dropdownColor: AppColors.secondaryBackground,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: _inputDecoration(
                      'Assign Site', Icons.location_on_outlined),
                  items: sites
                      .map((s) => DropdownMenuItem(
                            value: s.siteId,
                            child:
                                Text(s.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => _selectedSiteId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _editingAdminId = null;
                Navigator.pop(context);
              },
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: _isEditingAdmin
                  ? null
                  : () async {
                      await _updateAdminUser();
                    },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.button),
              child: _isEditingAdmin
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Update', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAdminUser(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.secondaryBackground,
        title: Text('Delete Site Admin',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this site admin?',
            style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete',
                  style: GoogleFonts.poppins(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await AdminService.deletePlatformAdmin(userId);
      if (response['status'] != 0) {
        _showSuccess('Site admin deleted successfully');
        await _fetchAdminUsers();
      } else {
        _showError(
            response['error']?.toString() ?? 'Failed to delete site admin');
      }
    } catch (e) {
      _showError('Error deleting site admin: $e');
    }
  }

  void _showAddAdminDialog() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _selectedSiteId = sites.isNotEmpty ? sites.first.siteId : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.secondaryBackground,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.button.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add,
                    color: AppColors.button, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Site Admin',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text('Create an admin account with site access.',
                        style: GoogleFonts.poppins(
                            color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                _buildField(_nameController, 'Full Name', Icons.person_outline),
                const SizedBox(height: 12),
                _buildField(
                    _emailController, 'Email Address', Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _buildField(_passwordController, 'Password', Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 12),
                _buildField(_confirmPasswordController, 'Confirm Password',
                    Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business,
                          color: Colors.white54, size: 18),
                      const SizedBox(width: 16),
                      Text(
                          company?.name.isNotEmpty == true
                              ? company!.name
                              : 'Ir blaster_Ac',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedSiteId,
                  dropdownColor: AppColors.secondaryBackground,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                  decoration: _inputDecoration(
                      'Assign Site', Icons.location_on_outlined),
                  items: sites
                      .map((site) => DropdownMenuItem(
                            value: site.siteId,
                            child: Text(site.name,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => _selectedSiteId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: _isAddingAdmin
                  ? null
                  : () async {
                      await _addAdminUser();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isAddingAdmin
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Add Site Admin',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
      TextEditingController controller, String hint, IconData icon,
      {bool obscureText = false, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: _inputDecoration(hint, icon),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white54, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: Colors.black12,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : Container(
                margin: const EdgeInsets.only(left: 16),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.gpp_good_outlined,
                  color: Color(0xFF6CC042),
                  size: 28,
                ),
              ),
        leadingWidth: canPop ? 56 : 44,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentUserRole == 'admin' ? 'Admin' : 'Company Admin',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              company?.name.isNotEmpty == true
                  ? company!.name
                  : 'Ir blaster_Ac',
              style: GoogleFonts.poppins(
                color: const Color(0xFF6CC042),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: AppColors.secondaryBackground,
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Text('Logout',
                        style: GoogleFonts.poppins(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.button,
          labelColor: AppColors.button,
          unselectedLabelColor: Colors.white54,
          labelStyle:
              GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: currentUserRole == 'admin'
              ? const [
                  Tab(text: 'Sites'),
                  Tab(text: 'Employee'),
                ]
              : currentUserRole == 'companyAdmin'
                  ? const [
                      Tab(text: 'Sites'),
                      Tab(text: 'Site Admins'),
                    ]
                  : const [
                      Tab(text: 'Sites'),
                      Tab(text: 'Site Admins'),
                      Tab(text: 'Employee'),
                    ],
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.button))
          : TabBarView(
              controller: _tabController,
              children: currentUserRole == 'admin'
                  ? [
                      _buildSitesTab(),
                      _buildEmployeeTab(),
                    ]
                  : currentUserRole == 'companyAdmin'
                      ? [
                          _buildSitesTab(),
                          _buildAdminsTab(),
                        ]
                      : [
                          _buildSitesTab(),
                          _buildAdminsTab(),
                          _buildEmployeeTab(),
                        ],
            ),
    );
  }

  Widget _buildSitesTab() {
    return Column(
      children: [
        // Quick Stats Summary
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.secondaryBackground,
                AppColors.secondaryBackground.withValues(alpha: 0.8)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
                bottom: BorderSide(
                    color: AppColors.button.withValues(alpha: 0.2), width: 1)),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatCard('Total Sites', '${sites.length}',
                      Icons.location_city_rounded, const Color(0xFF6CC042)),
                  const SizedBox(width: 12),
                  currentUserRole == 'admin'
                      ? _buildStatCard('Employees', '${employeeUsers.length}',
                          Icons.people_outline_rounded, const Color(0xFF0077BE))
                      : _buildStatCard('Site Admins', '${adminUsers.length}',
                          Icons.people_outline_rounded, const Color(0xFF0077BE)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '${sites.length} Active Site${sites.length != 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.button.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.button.withValues(alpha: 0.3),
                          width: 1),
                    ),
                    child: Text('Directory',
                        style: GoogleFonts.poppins(
                            color: AppColors.button,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: sites.isEmpty
              ? _buildEmptyState('No sites found in this company directory.',
                  Icons.location_off_rounded)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Google Map — lazy: only rendered after sites are loaded
                      // RepaintBoundary prevents the heavy map from repainting on every setState
                      RepaintBoundary(
                        child: Container(
                          height: 240,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.button.withValues(alpha: 0.3),
                                width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _mapReady
                                ? GoogleMap(
                                    onMapCreated: _onMapCreated,
                                    initialCameraPosition: CameraPosition(
                                      target:
                                          _CompanyAdminPageState._indiaCenter,
                                      zoom: 5,
                                    ),
                                    markers: _markers,
                                    myLocationButtonEnabled: false,
                                    zoomControlsEnabled: true,
                                    mapType: MapType.normal,
                                  )
                                : Container(
                                    color: const Color(0xFF1A172E),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircularProgressIndicator(
                                            color: AppColors.button,
                                            strokeWidth: 2,
                                          ),
                                          const SizedBox(height: 8),
                                          Text('Loading map…',
                                              style: GoogleFonts.poppins(
                                                  color: Colors.white38,
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Site Cards (tap → employee dashboard)
                      ...sites.map((site) => GestureDetector(
                            onTap: () => _openSite(site),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A172E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    width: 1),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6CC042)
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: const Color(0xFF6CC042)
                                                    .withValues(alpha: 0.3),
                                                width: 1),
                                          ),
                                          child: const Icon(
                                              Icons.location_on_outlined,
                                              color: Color(0xFF6CC042),
                                              size: 24),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(site.name,
                                                  style: GoogleFonts.poppins(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16)),
                                              if (site.shortId.isNotEmpty)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 6),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.redAccent.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                        color: Colors.redAccent.withValues(alpha: 0.4),
                                                        width: 1),
                                                  ),
                                                  child: Text(
                                                    'ID: ${site.shortId}',
                                                    style: GoogleFonts.poppins(
                                                        color: Colors.redAccent,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12.0),
                                      child: Divider(
                                          color: Colors.white10, height: 1),
                                    ),
                                    _siteDetailRow(Icons.map_outlined,
                                        'Location', _siteLocationLabel(site)),
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text('Open Dashboard',
                                            style: GoogleFonts.poppins(
                                                color: AppColors.button,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward,
                                            color: AppColors.button, size: 18),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  String _siteLocationLabel(Site site) {
    final parts = [site.city, site.state, site.country]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    return parts.isEmpty ? 'Location not set' : parts.join(', ');
  }

  Widget _siteDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6CC042), size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.poppins(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              Text(value,
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdminsTab() {
    return Column(
      children: [
        // Header Section
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.secondaryBackground,
                AppColors.secondaryBackground.withValues(alpha: 0.8)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
                bottom: BorderSide(
                    color: AppColors.button.withValues(alpha: 0.2), width: 1)),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search & Add Header
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.button.withValues(alpha: 0.2),
                            width: 1),
                      ),
                      child: TextField(
                        controller: _searchAdminUserController,
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search by name or email...',
                          hintStyle: GoogleFonts.poppins(
                              color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(Icons.search,
                              color: AppColors.button, size: 18),
                          suffixIcon: _searchAdminUserController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white38, size: 18),
                                  onPressed: () {
                                    _searchAdminUserController.clear();
                                    _filterAdminUsers();
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.button,
                          AppColors.button.withValues(alpha: 0.8)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.button.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: IconButton(
                      icon:
                          const Icon(Icons.add, color: Colors.white, size: 20),
                      onPressed: _showAddAdminDialog,
                      tooltip: 'Add Site Admin',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '${filteredAdminUsers.length} Site Admin${filteredAdminUsers.length != 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.button.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.button.withValues(alpha: 0.3),
                          width: 1),
                    ),
                    child: Text('Active',
                        style: GoogleFonts.poppins(
                            color: AppColors.button,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Admin List
        Expanded(
          child: isAdminUsersLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.button))
              : filteredAdminUsers.isEmpty
                  ? _buildEmptyState(
                      'No admin users found.', Icons.shield_outlined)
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Container(
                        margin: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131127),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Table Header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1A172E),
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Name',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Text(
                                      'Email',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Site',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'Actions',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                               ),
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            // Table Rows
                            ...filteredAdminUsers.map((admin) {
                              final siteMatch = sites.cast<Site?>().firstWhere(
                                  (s) => s!.siteId == admin.site,
                                  orElse: () => null);
                              final assignedSiteName = siteMatch?.name ??
                                  company?.name ??
                                  admin.site;
                              final isLast =
                                  filteredAdminUsers.indexOf(admin) ==
                                      filteredAdminUsers.length - 1;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  border: isLast
                                      ? null
                                      : Border(
                                          bottom: BorderSide(
                                              color: Colors.white
                                                  .withValues(alpha: 0.05),
                                              width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        admin.name,
                                        style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 5,
                                      child: Text(
                                        admin.email,
                                        style: GoogleFonts.poppins(
                                            color: Colors.white54,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        assignedSiteName,
                                        style: GoogleFonts.poppins(
                                            color: AppColors.button,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Tooltip(
                                            message: 'Edit admin',
                                            child: InkWell(
                                              onTap: () =>
                                                  _showEditAdminDialog(admin),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(Icons.edit_outlined,
                                                    color: Colors.orangeAccent,
                                                    size: 18),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Tooltip(
                                            message: 'Delete admin',
                                            child: InkWell(
                                              onTap: () => _deleteAdminUser(
                                                  admin.userId),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                    size: 18),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A172E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: color.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Icon(icon, color: color, size: 14),
                ),
                const Spacer(),
                Icon(Icons.trending_up,
                    color: color.withValues(alpha: 0.4), size: 14),
              ],
            ),
            const SizedBox(height: 10),
            Text(value,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Future<void> _addEmployee() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        (!_isEditingAdmin && _passwordController.text.isEmpty) ||
        _selectedRole == null ||
        _selectedServiceType == null) {
      _showError('Please fill all required fields');
      return;
    }

    setState(() => _isAddingEmployee = true);
    try {
      final userData = await AuthService.getUserData();
      final companyId =
          AuthService.extractCompanyId(userData) ?? _selectedCompanyId;

      Map<String, dynamic> response;
      if (_isEditingAdmin && _editingAdminId != null) {
        response = await AdminService.updateSiteTechnician(
          employeeId: _editingAdminId!,
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          companyId: companyId ?? '',
          siteId: _selectedSiteId ?? '',
          zoneId: _selectedZoneId,
          serviceType: _selectedServiceType ?? 'AC',
        );
      } else {
        response = await AdminService.createSiteTechnician(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          role: _selectedRole ?? 'site_technician',
          companyId: companyId ?? '',
          siteId: _selectedSiteId ?? '',
          zoneId: _selectedZoneId,
          serviceType: _selectedServiceType ?? 'AC',
        );
      }

      if (response['status'] == 1) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _selectedSiteId = null;
        _selectedZoneId = null;
        _selectedRole = 'site_technician';
        _selectedServiceType = 'AC';
        if (!context.mounted) return;
        Navigator.pop(context);
        _showSuccess(_isEditingAdmin
            ? 'Employee updated successfully'
            : 'Employee created successfully');
        await _fetchEmployeeUsers(showLocalLoader: false);
      } else {
        _showError(
            'Failed to ${_isEditingAdmin ? 'update' : 'create'} employee: ${response['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      _isAddingEmployee = false;
      _isEditingAdmin = false;
      _editingAdminId = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteEmployee(String employeeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.secondaryBackground,
        title: Text('Delete Employee',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this employee?',
            style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete',
                  style: GoogleFonts.poppins(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AdminService.deleteSiteTechnician(employeeId);
      _showSuccess('Employee deleted successfully');
      await _fetchEmployeeUsers(showLocalLoader: false);
    } catch (e) {
      _showError('Error deleting employee: $e');
    }
  }

  void _showAddEmployeeDialog([AdminUser? emp]) {
    if (emp != null) {
      _isEditingAdmin = true;
      _editingAdminId = emp.userId;
      _nameController.text = emp.name;
      _emailController.text = emp.email;
      _passwordController.text = '';
      _confirmPasswordController.text = '';

      final validSiteIds = sites.map((s) => s.siteId).toList();
      _selectedSiteId = validSiteIds.contains(emp.site)
          ? emp.site
          : (sites.isNotEmpty ? sites.first.siteId : null);

      final validZoneIds = zones.map((z) => z.zoneId).toList();
      _selectedZoneId = validZoneIds.contains(emp.zoneId)
          ? emp.zoneId
          : (zones.isNotEmpty ? zones.first.zoneId : null);

      _selectedRole = emp.role.isNotEmpty ? emp.role : 'site_technician';

      final validServices = [
        'EMS',
        'COMPRESSOR',
        'NEW COMPRESSOR',
        'AC',
        'CHILLER',
        'WATER',
        'WELD'
      ];
      final eService = emp.serviceType?.isNotEmpty == true
          ? emp.serviceType!
          : 'AC'; // It's mapped to serviceType sometimes
      _selectedServiceType = validServices.contains(eService) ? eService : 'AC';
    } else {
      _isEditingAdmin = false;
      _editingAdminId = null;
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _selectedSiteId = sites.isNotEmpty ? sites.first.siteId : null;
      _selectedZoneId = zones.isNotEmpty ? zones.first.zoneId : null;
      _selectedRole = 'site_technician';
      _selectedServiceType = 'AC';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.secondaryBackground,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(_isEditingAdmin ? 'Edit Employee' : 'Add Employee',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Full Name',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.person_outline,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Email Address',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.mail_outline,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _isEditingAdmin
                        ? 'Leave blank to keep current password'
                        : 'Password',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _isEditingAdmin
                        ? 'Leave blank to keep current password'
                        : 'Confirm Password',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business,
                          color: Colors.white54, size: 18),
                      const SizedBox(width: 16),
                      Text(
                          company?.name.isNotEmpty == true
                              ? company!.name
                              : 'Ir blaster_Ac',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  dropdownColor: AppColors.secondaryBackground,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Select Role',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.security_outlined,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'site_technician',
                        child: Text('Site Technician')),
                    DropdownMenuItem(
                        value: 'zone_technician',
                        child: Text('Zone Technician')),
                    DropdownMenuItem(
                        value: 'technician', child: Text('Technician')),
                  ],
                  onChanged: (val) => setDialogState(() => _selectedRole = val),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedZoneId,
                  dropdownColor: AppColors.secondaryBackground,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Select Zone',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.map_outlined,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  items: zones.isEmpty
                      ? [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('No Values Found'))
                        ]
                      : zones
                          .map((zone) => DropdownMenuItem<String>(
                                value: zone.zoneId,
                                child: Text(zone.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                  onChanged: zones.isEmpty
                      ? null
                      : (val) => setDialogState(() => _selectedZoneId = val),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedSiteId,
                  dropdownColor: AppColors.secondaryBackground,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Select Site',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.location_city_outlined,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  items: sites.isEmpty
                      ? [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('No Values Found'))
                        ]
                      : sites
                          .map((site) => DropdownMenuItem<String>(
                                value: site.siteId,
                                child: Text(site.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                  onChanged: sites.isEmpty
                      ? null
                      : (val) => setDialogState(() => _selectedSiteId = val),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedServiceType,
                  dropdownColor: AppColors.secondaryBackground,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Select Service Type',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.build_outlined,
                        color: Colors.white54, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.black12,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'EMS', child: Text('EMS')),
                    DropdownMenuItem(
                        value: 'COMPRESSOR', child: Text('COMPRESSOR')),
                    DropdownMenuItem(
                        value: 'NEW COMPRESSOR', child: Text('NEW COMPRESSOR')),
                    DropdownMenuItem(value: 'AC', child: Text('AC')),
                    DropdownMenuItem(value: 'CHILLER', child: Text('CHILLER')),
                    DropdownMenuItem(value: 'WATER', child: Text('WATER')),
                    DropdownMenuItem(value: 'WELD', child: Text('WELD')),
                  ],
                  onChanged: (val) =>
                      setDialogState(() => _selectedServiceType = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: _isAddingEmployee
                  ? null
                  : () async {
                      if (_passwordController.text !=
                          _confirmPasswordController.text) {
                        _showError('Passwords do not match');
                        return;
                      }
                      await _addEmployee();
                    },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.button),
              child: _isAddingEmployee
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_isEditingAdmin ? 'Save Changes' : 'Add Employee',
                      style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeTab() {
    return Column(
      children: [
        // Header Section
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.secondaryBackground,
                AppColors.secondaryBackground.withValues(alpha: 0.8)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
                bottom: BorderSide(
                    color: AppColors.button.withValues(alpha: 0.2), width: 1)),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.button.withValues(alpha: 0.2),
                            width: 1),
                      ),
                      child: TextField(
                        controller: _searchEmployeeController,
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search employees...',
                          hintStyle: GoogleFonts.poppins(
                              color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(Icons.search,
                              color: AppColors.button, size: 18),
                          suffixIcon: _searchEmployeeController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white38, size: 18),
                                  onPressed: () {
                                    _searchEmployeeController.clear();
                                    setState(() => _filterEmployeeUsers());
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.button,
                          AppColors.button.withValues(alpha: 0.8)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.button.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: IconButton(
                      icon:
                          const Icon(Icons.add, color: Colors.white, size: 20),
                      onPressed: _showAddEmployeeDialog,
                      tooltip: 'Add Employee',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '${filteredEmployeeUsers.length} Employee${filteredEmployeeUsers.length != 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.button.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.button.withValues(alpha: 0.3),
                          width: 1),
                    ),
                    child: Text('Active',
                        style: GoogleFonts.poppins(
                            color: AppColors.button,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: isEmployeeUsersLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.button))
              : filteredEmployeeUsers.isEmpty
                  ? _buildEmptyState(
                      'No employees found.', Icons.people_outline)
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Container(
                        margin: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131127),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Table Header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1A172E),
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Name',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      'Email',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Site',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 60,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'Action',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            // Table Rows
                            ...filteredEmployeeUsers.map((emp) {
                              // Resolve siteId → site name; fall back to company name or N/A
                              final empSiteMatch = sites
                                  .cast<Site?>()
                                  .firstWhere(
                                      (s) =>
                                          s!.siteId == emp.site ||
                                          s.siteId == emp.company,
                                      orElse: () => null);
                              final empSiteName = empSiteMatch?.name ??
                                  company?.name ??
                                  (emp.site.isNotEmpty ? emp.site : 'N/A');
                              final isLast =
                                  filteredEmployeeUsers.indexOf(emp) ==
                                      filteredEmployeeUsers.length - 1;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  border: isLast
                                      ? null
                                      : Border(
                                          bottom: BorderSide(
                                              color: Colors.white
                                                  .withValues(alpha: 0.05),
                                              width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        emp.name,
                                        style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        emp.email,
                                        style: GoogleFonts.poppins(
                                            color: Colors.white54,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        empSiteName,
                                        style: GoogleFonts.poppins(
                                            color: AppColors.button,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Tooltip(
                                            message: 'Edit',
                                            child: InkWell(
                                              onTap: () =>
                                                  _showAddEmployeeDialog(emp),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(Icons.edit_outlined,
                                                    color: Colors.white54,
                                                    size: 18),
                                              ),
                                            ),
                                          ),
                                          Tooltip(
                                            message: 'Delete',
                                            child: InkWell(
                                              onTap: () =>
                                                  _deleteEmployee(emp.userId),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                    size: 18),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white12, size: 48),
            const SizedBox(height: 16),
            Text(msg,
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
