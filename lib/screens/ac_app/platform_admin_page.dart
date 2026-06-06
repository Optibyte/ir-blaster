import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/models/admin_model.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/sigin.dart';
import 'package:ir_blaster_ac/screens/ac_app/company_sites_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:ir_blaster_ac/core/theme/theme_provider.dart';

class PlatformAdminPage extends StatefulWidget {
  final String? companyId;

  const PlatformAdminPage({super.key, this.companyId});

  @override
  State<PlatformAdminPage> createState() => _PlatformAdminPageState();
}

class _PlatformAdminPageState extends State<PlatformAdminPage>
    with SingleTickerProviderStateMixin {
  List<Company> companies = [];
  bool isLoading = false;

  bool _isDarkTheme = true;

  Color get _bgColor => Theme.of(context).scaffoldBackgroundColor;
  // Color get _cardColor => Theme.of(context).cardColor;
  // Color get _cardColor => Theme.of(context).cardColor;
  Color get _cardColor => _isDarkTheme ? const Color(0xFF2A244D) : const Color.fromARGB(255, 249, 249, 248);
  Color get _textColor => _isDarkTheme ? Colors.white : Colors.white ;
  Color get _textbody => _isDarkTheme ? Colors.white : Color.fromARGB(223, 74, 137, 8) ;
  Color get _textSecondaryColor => _isDarkTheme ? Colors.white70 : Colors.white70;
  Color get _textMutedColor => _isDarkTheme ? Colors.white38 : const Color(0xFF8A9EAD);
  Color get _appBarIconColor => _isDarkTheme ? Colors.white : const Color(0xFF1B172E);
  Color get _dialogBgColor => Theme.of(context).cardColor;
  Color get _dividerColor => _isDarkTheme ? Colors.white12 : Colors.black12;
  Color get _shadowColor => _isDarkTheme ? Colors.black26 : Colors.black.withValues(alpha: 0.05);

  void _showThemePreferencesDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _dialogBgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Theme Preferences',
            style: GoogleFonts.poppins(
              color: _textbody,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                title: Text(
                  'Dark Theme',
                  style: GoogleFonts.poppins(color: _textbody),
                ),
                subtitle: Text(
                  'Sleek dark purple & green',
                  style: GoogleFonts.poppins(color: _textbody, fontSize: 11),
                ),
                value: true,
                groupValue: _isDarkTheme,
                activeColor: AppColors.button,
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() {
                      _isDarkTheme = val;
                    });
                    Provider.of<ThemeProvider>(context, listen: false).setDarkMode(val);
                  }
                },
              ),
              RadioListTile<bool>(
                title: Text(
                  'Light Theme',
                  style: GoogleFonts.poppins(color: _textbody),
                ),
                subtitle: Text(
                  'Clean white & green / dark blue',
                  style: GoogleFonts.poppins(color: _textbody, fontSize: 11),
                ),
                value: false,
                groupValue: _isDarkTheme,
                activeColor: AppColors.button,
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() {
                      _isDarkTheme = val;
                    });
                    Provider.of<ThemeProvider>(context, listen: false).setDarkMode(val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: GoogleFonts.poppins(color: AppColors.button, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Google Maps Controller
  GoogleMapController? _mapController;

  // Company Admin state
  List<AdminUser> companyAdmins = [];
  List<AdminUser> _allCompanyAdmins = [];
  bool companyAdminsLoading = false;
  String searchCompanyAdminTerm = '';

  // Site Admin state
  List<AdminUser> siteAdmins = [];
  List<AdminUser> _allSiteAdmins = [];
  bool siteAdminsLoading = false;
  String searchSiteAdminTerm = '';

  // Tab View state
  late TabController _tabController;

  // Form controllers for Add Company Admin
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  late TextEditingController _searchAdminController;
  late TextEditingController _searchSiteAdminController;

  String? _selectedCompanyId;
  String? _selectedSiteId;
  bool _isAddingAdmin = false;
  List<Map<String, dynamic>> _companySites = [];
  bool _loadingSites = false;

  // Edit form state (reserved for future use)
  // ignore: unused_field
  String? _editingAdminId;
  // ignore: unused_field
  bool _isEditingAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _searchAdminController = TextEditingController();
    _searchSiteAdminController = TextEditingController();

    _fetchCompanies();
    _fetchCompanyAdmins();
    _searchAdminController.addListener(_onSearchChanged);
    _searchSiteAdminController.addListener(_onSearchSiteAdminChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _searchAdminController.dispose();
    _searchSiteAdminController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _filterCompanyAdmins();
    });
  }

  void _onSearchSiteAdminChanged() {
    setState(() {
      _filterSiteAdmins();
    });
  }

  Future<void> _fetchCompanies() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final userData = await AuthService.getUserData();

      // Attempt to load assigned company list
      List<String> companyIds = [];
      if (userData != null) {
        final rawCompany = userData['company'] ?? userData['companyId'];
        if (rawCompany is List) {
          companyIds = List<String>.from(rawCompany.map((e) => e.toString()));
        } else if (rawCompany != null) {
          final raw = rawCompany.toString().trim();
          // Handle JSON array stored as string e.g. '["uuid"]'
          if (raw.startsWith('[')) {
            try {
              final parsed = jsonDecode(raw);
              if (parsed is List) {
                companyIds = List<String>.from(parsed.map((e) => e.toString()));
              } else {
                companyIds = [raw];
              }
            } catch (_) {
              companyIds = [raw];
            }
          } else if (raw.isNotEmpty) {
            companyIds = [raw];
          }
        }
      }

      final List<Map<String, dynamic>> fetchedCompaniesData = [];

      // Fetch each company's details
      for (final cid in companyIds) {
        if (cid.isEmpty) continue;
        final companyData = await AdminService.fetchCompanyById(cid);
        if (companyData.isNotEmpty) {
          fetchedCompaniesData.add(Map<String, dynamic>.from(companyData));
        } else {
          fetchedCompaniesData.add({
            'companyId': cid,
            'name': 'Company ($cid)',
            'bucket': '',
          });
        }
      }

      // If no company IDs were found in token, try fetching all
      if (fetchedCompaniesData.isEmpty) {
        if (widget.companyId != null && widget.companyId!.isNotEmpty) {
          final cid = widget.companyId!;
          final companyData = await AdminService.fetchCompanyById(cid);
          if (companyData.isNotEmpty) {
            fetchedCompaniesData.add(Map<String, dynamic>.from(companyData));
          } else {
            fetchedCompaniesData.add({
              'companyId': cid,
              'name': 'Company ($cid)',
              'bucket': '',
            });
          }
        } else {
          final list = await AdminService.fetchCompanies();
          fetchedCompaniesData.addAll(list);
        }
      }

      if (!mounted) return;

      setState(() {
        companies = fetchedCompaniesData
            .where((data) => data.isNotEmpty)
            .map((data) => Company.fromJson(data))
            .where((c) => c.companyId.isNotEmpty)
            .toList();
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        _fitMapBounds();
      });
    } catch (e) {
      debugPrint('Error fetching companies: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _fitMapBounds() {
    if (_mapController == null || companies.isEmpty) return;

    final positions = <LatLng>[];
    for (final c in companies) {
      final pos = _resolveCompanyPosition(c);
      if (pos != null) positions.add(pos);
    }
    if (positions.isEmpty) return;

    if (positions.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(positions.first, 11),
      );
      return;
    }

    double minLat = positions.first.latitude,
        maxLat = positions.first.latitude;
    double minLng = positions.first.longitude,
        maxLng = positions.first.longitude;
    for (final pos in positions) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50, // padding
      ),
    );
  }

  Future<void> _fetchCompanyAdmins() async {
    if (!mounted) return;
    setState(() => companyAdminsLoading = true);
    try {
      final response = await AdminService.fetchCompanyAdmins();

      if (!mounted) return;

      List<AdminUser> admins = [];
      final data = response['data'];

      if (data is Map && data['companyAdmins'] is List) {
        admins = (data['companyAdmins'] as List).map((item) {
          final adminData = item as Map<String, dynamic>;
          if (!adminData.containsKey('userId') &&
              adminData.containsKey('companyAdminId')) {
            adminData['userId'] = adminData['companyAdminId'];
          }
          return AdminUser.fromJson(adminData);
        }).toList();
      } else if (data is List) {
        admins = data.map((item) {
          final adminData = item as Map<String, dynamic>;
          if (!adminData.containsKey('userId') &&
              adminData.containsKey('companyAdminId')) {
            adminData['userId'] = adminData['companyAdminId'];
          }
          return AdminUser.fromJson(adminData);
        }).toList();
      }

      setState(() {
        _allCompanyAdmins = admins;
        _filterCompanyAdmins();
      });
    } catch (e) {
      debugPrint('Error fetching company admins: $e');
    } finally {
      if (mounted) {
        setState(() => companyAdminsLoading = false);
      }
    }
  }

  void _filterCompanyAdmins() {
    final term = _searchAdminController.text.trim().toLowerCase();
    searchCompanyAdminTerm = term;
    if (term.isEmpty) {
      companyAdmins = List.from(_allCompanyAdmins);
    } else {
      companyAdmins = _allCompanyAdmins
          .where((admin) =>
              admin.name.toLowerCase().contains(term) ||
              admin.email.toLowerCase().contains(term))
          .toList();
    }
  }

  Future<void> _fetchSiteAdmins() async {
    if (!mounted) return;
    setState(() => siteAdminsLoading = true);
    try {
      final response = await AdminService.fetchSiteAdmins();

      if (!mounted) return;

      List<AdminUser> admins = [];
      final data = response['data'];

      if (data is Map && data['siteAdmins'] is List) {
        admins = (data['siteAdmins'] as List).map((item) {
          final adminData = item as Map<String, dynamic>;
          if (!adminData.containsKey('userId') &&
              adminData.containsKey('siteAdminId')) {
            adminData['userId'] = adminData['siteAdminId'];
          }
          return AdminUser.fromJson(adminData);
        }).toList();
      } else if (data is List) {
        admins = data.map((item) {
          final adminData = item as Map<String, dynamic>;
          if (!adminData.containsKey('userId') &&
              adminData.containsKey('siteAdminId')) {
            adminData['userId'] = adminData['siteAdminId'];
          }
          return AdminUser.fromJson(adminData);
        }).toList();
      }

      setState(() {
        _allSiteAdmins = admins;
        _filterSiteAdmins();
      });
    } catch (e) {
      debugPrint('Error fetching site admins: $e');
    } finally {
      if (mounted) {
        setState(() => siteAdminsLoading = false);
      }
    }
  }

  void _filterSiteAdmins() {
    final term = _searchSiteAdminController.text.trim().toLowerCase();
    searchSiteAdminTerm = term;
    if (term.isEmpty) {
      siteAdmins = List.from(_allSiteAdmins);
    } else {
      siteAdmins = _allSiteAdmins
          .where((admin) =>
              admin.name.toLowerCase().contains(term) ||
              admin.email.toLowerCase().contains(term))
          .toList();
    }
  }

  Future<void> _fetchSitesForSelectedCompany(String companyId,
      [StateSetter? setDialogState]) async {
    if (setDialogState != null) {
      setDialogState(() => _loadingSites = true);
    } else {
      setState(() => _loadingSites = true);
    }

    try {
      final list = await AdminService.fetchSites(companyId: companyId);
      if (setDialogState != null) {
        setDialogState(() {
          _companySites = list;
          final validSiteIds = _companySites
              .map((s) => (s['siteId'] ?? s['_id'] ?? '').toString())
              .toList();
          if (_selectedSiteId == null ||
              !validSiteIds.contains(_selectedSiteId)) {
            _selectedSiteId =
                validSiteIds.isNotEmpty ? validSiteIds.first : null;
          }
          _loadingSites = false;
        });
      } else {
        setState(() {
          _companySites = list;
          final validSiteIds = _companySites
              .map((s) => (s['siteId'] ?? s['_id'] ?? '').toString())
              .toList();
          if (_selectedSiteId == null ||
              !validSiteIds.contains(_selectedSiteId)) {
            _selectedSiteId =
                validSiteIds.isNotEmpty ? validSiteIds.first : null;
          }
          _loadingSites = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sites: $e');
      if (setDialogState != null) {
        setDialogState(() => _loadingSites = false);
      } else {
        setState(() => _loadingSites = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: AppColors.button,
        behavior: SnackBarBehavior.floating,
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
    if (_selectedCompanyId == null) {
      _showError('Please select a company');
      return false;
    }
    return true;
  }

  bool _validateSiteAdminForm() {
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
    if (_selectedCompanyId == null) {
      _showError('Please select a company');
      return false;
    }
    if (_selectedSiteId == null) {
      _showError('Please select a site');
      return false;
    }
    return true;
  }

  Future<void> _addCompanyAdmin() async {
    if (!_validateForm()) return;

    setState(() => _isAddingAdmin = true);

    try {
      final selectedCompany =
          companies.firstWhere((c) => c.companyId == _selectedCompanyId);
      final response = await AdminService.createCompanyAdmin(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        companyId: _selectedCompanyId!,
        bucket: selectedCompany.bucket,
      );

      final status = response['status'] ?? response['Status'];
      final message = response['message'] ?? response['Message'];
      final hasData = response['data'] ?? response['Data'];
      final userId = response['userId'] ??
          response['UserId'] ??
          (hasData is Map ? (hasData['userId'] ?? hasData['UserId']) : null);

      if (status == 1 || status == true || userId != null) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _selectedCompanyId = null;
        if (!context.mounted) return;
        Navigator.pop(context);
        _showSuccess('Company admin created successfully');
        await _fetchCompanyAdmins();
      } else {
        _showError(message?.toString() ?? 'Failed to create company admin');
      }
    } catch (e) {
      _showError('Error creating company admin: $e');
    } finally {
      setState(() => _isAddingAdmin = false);
    }
  }

  Future<void> _deleteCompanyAdmin(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _dialogBgColor,
        title: Text('Delete Company Admin',
            style: GoogleFonts.poppins(
                color: _textColor, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this company admin?',
            style: GoogleFonts.poppins(color: _textSecondaryColor)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: _textMutedColor))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete',
                  style: GoogleFonts.poppins(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AdminService.deleteCompanyAdmin(userId);
      _showSuccess('Company admin deleted successfully');
      await _fetchCompanyAdmins();
    } catch (e) {
      _showError('Error deleting company admin: $e');
    }
  }

  Future<void> _updateCompanyAdmin() async {
    if (_editingAdminId == null) return;
    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      _showError('Name and email are required');
      return;
    }

    setState(() => _isEditingAdmin = true);

    try {
      final response = await AdminService.updateCompanyAdmin(
        userId: _editingAdminId!,
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null,
        companyId: _selectedCompanyId,
      );

      if (response['status'] != 0 ||
          response['userId'] != null ||
          response['data'] != null) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _editingAdminId = null;
        _selectedCompanyId = null;
        if (!context.mounted) return;
        Navigator.pop(context);
        _showSuccess('Company admin updated successfully');
        await _fetchCompanyAdmins();
      } else {
        _showError('Failed to update company admin');
      }
    } catch (e) {
      _showError('Error updating company admin: $e');
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

    // Find matching company id if any
    _selectedCompanyId = companies.any((c) => c.companyId == admin.company)
        ? admin.company
        : (companies.isNotEmpty ? companies.first.companyId : null);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _dialogBgColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Company Admin',
              style: GoogleFonts.poppins(
                  color: _textColor, fontWeight: FontWeight.bold)),
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
                  value: _selectedCompanyId,
                  dropdownColor: _dialogBgColor,
                  style: GoogleFonts.poppins(color: _textColor),
                  decoration: _inputDecoration(
                      'Assign Company', Icons.business_outlined),
                  items: companies
                      .map((c) => DropdownMenuItem(
                            value: c.companyId,
                            child:
                                Text(c.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => _selectedCompanyId = val),
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
                  style: GoogleFonts.poppins(color: _textMutedColor)),
            ),
            ElevatedButton(
              onPressed: _isEditingAdmin
                  ? null
                  : () async {
                      await _updateCompanyAdmin();
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

  void _showAddAdminDialog() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _selectedCompanyId =
        companies.isNotEmpty ? companies.first.companyId : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _dialogBgColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('New Company Admin',
              style: GoogleFonts.poppins(
                  color: _textColor, fontWeight: FontWeight.bold)),
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
                _buildField(_passwordController, 'Password', Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 12),
                _buildField(_confirmPasswordController, 'Confirm Password',
                    Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCompanyId,
                  dropdownColor: _dialogBgColor,
                  style: GoogleFonts.poppins(color: _textColor),
                  decoration: _inputDecoration(
                      'Assign Company', Icons.business_outlined),
                  items: companies
                      .map((c) => DropdownMenuItem(
                            value: c.companyId,
                            child:
                                Text(c.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => _selectedCompanyId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: _textMutedColor)),
            ),
            ElevatedButton(
              onPressed: _isAddingAdmin
                  ? null
                  : () async {
                      await _addCompanyAdmin();
                    },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.button),
              child: _isAddingAdmin
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add Admin',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSiteAdmin() async {
    if (!_validateSiteAdminForm()) return;

    setState(() => _isAddingAdmin = true);

    try {
      final response = await AdminService.createSiteAdmin(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        companyId: _selectedCompanyId!,
        siteId: _selectedSiteId!,
      );

      final status = response['status'] ?? response['Status'];
      final message = response['message'] ?? response['Message'];
      final hasData = response['data'] ?? response['Data'];
      final userId = response['userId'] ??
          response['UserId'] ??
          (hasData is Map ? (hasData['userId'] ?? hasData['UserId']) : null);

      if (status == 1 || status == true || userId != null) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _selectedCompanyId = null;
        _selectedSiteId = null;
        if (!context.mounted) return;
        Navigator.pop(context);
        _showSuccess('Site admin created successfully');
        await _fetchSiteAdmins();
      } else {
        _showError(message?.toString() ?? 'Failed to create site admin');
      }
    } catch (e) {
      _showError('Error creating site admin: $e');
    } finally {
      setState(() => _isAddingAdmin = false);
    }
  }

  Future<void> _deleteSiteAdmin(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _dialogBgColor,
        title: Text('Delete Site Admin',
            style: GoogleFonts.poppins(
                color: _textColor, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this site admin?',
            style: GoogleFonts.poppins(color: _textSecondaryColor)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: _textMutedColor))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete',
                  style: GoogleFonts.poppins(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AdminService.deleteSiteAdmin(userId);
      _showSuccess('Site admin deleted successfully');
      await _fetchSiteAdmins();
    } catch (e) {
      _showError('Error deleting site admin: $e');
    }
  }

  Future<void> _updateSiteAdmin() async {
    if (_editingAdminId == null) return;
    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      _showError('Name and email are required');
      return;
    }
    if (_selectedCompanyId == null || _selectedSiteId == null) {
      _showError('Company and site are required');
      return;
    }

    setState(() => _isAddingAdmin = true);

    try {
      final response = await AdminService.updateSiteAdmin(
        userId: _editingAdminId!,
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null,
        companyId: _selectedCompanyId,
        siteId: _selectedSiteId,
      );

      if (response['status'] != 0 ||
          response['userId'] != null ||
          response['data'] != null) {
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        _editingAdminId = null;
        _selectedCompanyId = null;
        _selectedSiteId = null;
        if (!context.mounted) return;
        Navigator.pop(context);
        _showSuccess('Site admin updated successfully');
        await _fetchSiteAdmins();
      } else {
        _showError('Failed to update site admin');
      }
    } catch (e) {
      _showError('Error updating site admin: $e');
    } finally {
      setState(() => _isAddingAdmin = false);
    }
  }

  void _showEditSiteAdminDialog(AdminUser admin) {
    _editingAdminId = admin.userId;
    _nameController.text = admin.name;
    _emailController.text = admin.email;
    _passwordController.clear();
    _confirmPasswordController.clear();

    // Find matching company id if any
    _selectedCompanyId = companies.any((c) => c.companyId == admin.company)
        ? admin.company
        : (companies.isNotEmpty ? companies.first.companyId : null);

    _selectedSiteId = admin.site.isNotEmpty ? admin.site : null;
    _companySites = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (_companySites.isEmpty && _selectedCompanyId != null) {
            _fetchSitesForSelectedCompany(_selectedCompanyId!, setDialogState);
          }

          return AlertDialog(
            backgroundColor: _dialogBgColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Edit Site Admin',
                style: GoogleFonts.poppins(
                    color: _textColor, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildField(
                      _nameController, 'Full Name', Icons.person_outline),
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
                    value: _selectedCompanyId,
                    dropdownColor: _dialogBgColor,
                    style: GoogleFonts.poppins(color: _textColor),
                    decoration: _inputDecoration(
                        'Assign Company', Icons.business_outlined),
                    items: companies
                        .map((c) => DropdownMenuItem(
                              value: c.companyId,
                              child:
                                  Text(c.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          _selectedCompanyId = val;
                        });
                        _fetchSitesForSelectedCompany(val, setDialogState);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedSiteId,
                    dropdownColor: _dialogBgColor,
                    style: GoogleFonts.poppins(color: _textColor),
                    decoration: _inputDecoration(
                        _loadingSites ? 'Loading sites...' : 'Select Site',
                        Icons.location_city_outlined),
                    items: _loadingSites
                        ? []
                        : _companySites.map((s) {
                            final id =
                                (s['siteId'] ?? s['_id'] ?? '').toString();
                            final name =
                                (s['name'] ?? 'Unnamed Site').toString();
                            return DropdownMenuItem(
                              value: id,
                              child:
                                  Text(name, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                    onChanged: _loadingSites
                        ? null
                        : (val) => setDialogState(() => _selectedSiteId = val),
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
                    style: GoogleFonts.poppins(color: _textMutedColor)),
              ),
              ElevatedButton(
                onPressed: _isAddingAdmin
                    ? null
                    : () async {
                        await _updateSiteAdmin();
                      },
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.button),
                child: _isAddingAdmin
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Update',
                        style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddSiteAdminDialog() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _selectedCompanyId =
        companies.isNotEmpty ? companies.first.companyId : null;
    _selectedSiteId = null;
    _companySites = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (_companySites.isEmpty && _selectedCompanyId != null) {
            _fetchSitesForSelectedCompany(_selectedCompanyId!, setDialogState);
          }
          return AlertDialog(
            backgroundColor: _dialogBgColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('New Site Admin',
                style: GoogleFonts.poppins(
                    color: _textColor, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildField(
                      _nameController, 'Full Name', Icons.person_outline),
                  const SizedBox(height: 12),
                  _buildField(
                      _emailController, 'Email Address', Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _buildField(
                      _passwordController, 'Password', Icons.lock_outline,
                      obscureText: true),
                  const SizedBox(height: 12),
                  _buildField(_confirmPasswordController, 'Confirm Password',
                      Icons.lock_outline,
                      obscureText: true),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedCompanyId,
                    dropdownColor: _dialogBgColor,
                    style: GoogleFonts.poppins(color: _textColor),
                    decoration: _inputDecoration(
                        'Select Company', Icons.business_outlined),
                    items: companies
                        .map((c) => DropdownMenuItem(
                              value: c.companyId,
                              child:
                                  Text(c.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          _selectedCompanyId = val;
                        });
                        _fetchSitesForSelectedCompany(val, setDialogState);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedSiteId,
                    dropdownColor: _dialogBgColor,
                    style: GoogleFonts.poppins(color: _textColor),
                    decoration: _inputDecoration(
                        _loadingSites ? 'Loading sites...' : 'Select Site',
                        Icons.location_city_outlined),
                    items: _loadingSites
                        ? []
                        : _companySites.map((s) {
                            final id =
                                (s['siteId'] ?? s['_id'] ?? '').toString();
                            final name =
                                (s['name'] ?? 'Unnamed Site').toString();
                            return DropdownMenuItem(
                              value: id,
                              child:
                                  Text(name, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                    onChanged: _loadingSites
                        ? null
                        : (val) => setDialogState(() => _selectedSiteId = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel',
                    style: GoogleFonts.poppins(color: _textMutedColor)),
              ),
              ElevatedButton(
                onPressed: _isAddingAdmin
                    ? null
                    : () async {
                        await _addSiteAdmin();
                      },
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.button),
                child: _isAddingAdmin
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Add Site Admin',
                        style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
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
      style: GoogleFonts.poppins(color: _textColor, fontSize: 14),
      decoration: _inputDecoration(hint, icon),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: _textMutedColor, fontSize: 13),
      prefixIcon: Icon(icon, color: _textSecondaryColor, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: _isDarkTheme ? Colors.black12 : Colors.black.withValues(alpha: 0.05),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _dialogBgColor,
        title: Text('Logout',
            style: GoogleFonts.poppins(
                color: _textColor, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to logout?',
            style: GoogleFonts.poppins(color: _textSecondaryColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: _textMutedColor)),
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

  @override
  Widget build(BuildContext context) {
    _isDarkTheme = Provider.of<ThemeProvider>(context).isDarkMode;
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        
        // backgroundColor: Colors.transparent,
         backgroundColor: _isDarkTheme ? const Color(0xFF2A244D) : const Color.fromARGB(223, 74, 137, 8),
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 16),
          alignment: Alignment.center,
          child: Icon(
            Icons.gpp_good_outlined,
            color: _isDarkTheme ? Color(0xFF6CC042) : Colors.white,
            size: 28,
          ),
        ),
        leadingWidth: 44,
        title: Text(
          'Platform Admin',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: _appBarIconColor),
            color: _dialogBgColor,
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              } else if (value == 'theme') {
                _showThemePreferencesDialog();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      _isDarkTheme ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: _isDarkTheme ? Colors.orangeAccent : const Color(0xFF1B172E),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isDarkTheme ? 'Light Theme' : 'Dark Theme',
                      style: GoogleFonts.poppins(color: _textbody),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Text('Logout',
                        style: GoogleFonts.poppins(color: _textColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicator: UnderlineTabIndicator(
  borderSide: BorderSide(
    color: _isDarkTheme
        ? const Color(0xFF6CC042)
        : const Color(0xFF242038),
    width: 3,
  ),
),
          labelColor: _isDarkTheme ? AppColors.button : const Color(0xFF1B172E),
          unselectedLabelColor: _textSecondaryColor,
          labelStyle:
              GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Companies'),
            Tab(text: 'Company Admins'),
          ],
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.button))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCompaniesTab(),
                _buildCompanyAdminsTab(),
              ],
            ),
    );
  }

  /// Resolve a map position for a company.
  /// Falls back to city name lookup when lat/lng are not available.
  LatLng? _resolveCompanyPosition(Company c) {
    // 1. Try explicit coordinates
    if (c.latitude != null && c.longitude != null) {
      return LatLng(c.latitude!, c.longitude!);
    }
    // 2. Fallback: resolve from city name
    final city = (c.city ?? c.name).toLowerCase().trim();
    const cityCoords = <String, LatLng>{
      'chennai': LatLng(13.0827, 80.2707),
      'mumbai': LatLng(19.0760, 72.8777),
      'delhi': LatLng(28.6139, 77.2090),
      'new delhi': LatLng(28.6139, 77.2090),
      'bangalore': LatLng(12.9716, 77.5946),
      'bengaluru': LatLng(12.9716, 77.5946),
      'hyderabad': LatLng(17.3850, 78.4867),
      'kolkata': LatLng(22.5726, 88.3639),
      'pune': LatLng(18.5204, 73.8567),
      'ahmedabad': LatLng(23.0225, 72.5714),
      'coimbatore': LatLng(11.0168, 76.9558),
      'madurai': LatLng(9.9252, 78.1198),
      'jaipur': LatLng(26.9124, 75.7873),
      'lucknow': LatLng(26.8467, 80.9462),
      'kochi': LatLng(9.9312, 76.2673),
      'cochin': LatLng(9.9312, 76.2673),
      'visakhapatnam': LatLng(17.6868, 83.2185),
      'indore': LatLng(22.7196, 75.8577),
      'nagpur': LatLng(21.1458, 79.0882),
      'bhopal': LatLng(23.2599, 77.4126),
      'trivandrum': LatLng(8.5241, 76.9366),
      'thiruvananthapuram': LatLng(8.5241, 76.9366),
    };
    for (final entry in cityCoords.entries) {
      if (city.contains(entry.key)) {
        return entry.value;
      }
    }
    // 3. Default to Chennai if nothing matches
    return const LatLng(13.0827, 80.2707);
  }

  Widget _buildCompaniesTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map Card
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _shadowColor,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Builder(
                  builder: (context) {
                    LatLng initialPos =
                        const LatLng(13.0827, 80.2707); // Chennai default

                    // Build markers using city fallback when lat/lng is missing
                    final markers = <Marker>{};
                    for (final c in companies) {
                      final pos = _resolveCompanyPosition(c);
                      if (pos == null) continue;
                      markers.add(Marker(
                        markerId: MarkerId(c.companyId),
                        position: pos,
                        infoWindow: InfoWindow(
                          title: c.name,
                          snippet:
                              '${c.city ?? ''}, ${c.state ?? ''}'.trim(),
                        ),
                      ));
                    }

                    if (markers.isNotEmpty) {
                      initialPos = markers.first.position;
                    }

                    return GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: initialPos,
                        zoom: companies.length == 1 ? 11 : 9,
                      ),
                      markers: markers,
                      zoomControlsEnabled: true,
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        // Use default (light/white) map style
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _fitMapBounds();
                        });
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Companies on Map Section
            Text(
              'Companies on Map',
              style: GoogleFonts.poppins(
                color: _textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            if (companies.isEmpty)
              _buildEmptyState(
                  'No companies on map.', Icons.location_off_rounded)
            else
              ...companies.map((comp) {
                debugPrint('Companies: $companies');
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _dividerColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF6CC042),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        comp.name,
                        style: GoogleFonts.poppins(
                          color: _textbody,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        comp.city != null && comp.city!.isNotEmpty
                            ? '${comp.city}, ${comp.state ?? "Tamil Nadu"}'
                            : 'Chennai, Tamil Nadu',
                        style: GoogleFonts.poppins(
                          color: _textSecondaryColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 24),

            // Company Selection Section
            Text(
              'Company Selection',
              style: GoogleFonts.poppins(
                color: _textbody,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select a company to view its dashboard',
              style: GoogleFonts.poppins(
                color: _textbody,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            if (companies.isEmpty)
              _buildEmptyState('No registered enterprise accounts found.',
                  Icons.business_outlined)
            else
              ...companies.map((comp) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompanySitesPage(
                          companyId: comp.companyId,
                          companyName: comp.name,
                          bucket: comp.bucket ?? '',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6CC042)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.business_rounded,
                                color: Color(0xFF6CC042),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                comp.name,
                                style: GoogleFonts.poppins(
                                  color: _textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'View Sites',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF6CC042),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Color(0xFF6CC042),
                              size: 16,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyAdminsTab() {
    return Column(
      children: [
        // Header Section
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _cardColor,
                _cardColor.withValues(alpha: 0.8)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
                bottom: BorderSide(
                    color: _dividerColor, width: 1)),
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
                        color: _isDarkTheme 
                            ? Colors.black.withValues(alpha: 0.2) 
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _isDarkTheme 
                                ? AppColors.button.withValues(alpha: 0.2) 
                                : const Color(0xFF1B172E).withValues(alpha: 0.1),
                            width: 1),
                      ),
                      child: TextField(
                        controller: _searchAdminController,
                        style: GoogleFonts.poppins(
                            color: _textColor, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search by name or email...',
                          hintStyle: GoogleFonts.poppins(
                              color: _textMutedColor, fontSize: 13),
                          prefixIcon: const Icon(Icons.search,
                              color: AppColors.button, size: 18),
                          suffixIcon: _searchAdminController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear,
                                      color: _textMutedColor, size: 18),
                                  onPressed: () {
                                    _searchAdminController.clear();
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
                      tooltip: 'Add Company Admin',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '${companyAdmins.length} Enterprise Manager${companyAdmins.length != 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                          color: _textSecondaryColor,
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
                    child: Text('Registered',
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
          child: companyAdminsLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.button))
              : companyAdmins.isEmpty
                  ? _buildEmptyState('No enterprise managers registered yet.',
                      Icons.admin_panel_settings_rounded)
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Container(
                        margin: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: _isDarkTheme ? const Color(0xFF131127) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _dividerColor,
                              width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Table Header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: _isDarkTheme ? const Color(0xFF1A172E) : const Color(0xFFEDF2F7),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Name',
                                      style: GoogleFonts.poppins(
                                          color: _textSecondaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      'Email',
                                      style: GoogleFonts.poppins(
                                          color: _textSecondaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Company',
                                      style: GoogleFonts.poppins(
                                          color: _textSecondaryColor,
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
                                            color: _textSecondaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(color: _dividerColor, height: 1),
                            // Table Rows
                            ...companyAdmins.map((admin) {
                              final compName = companies
                                  .firstWhere(
                                      (c) => c.companyId == admin.company,
                                      orElse: () => Company(
                                          companyId: '',
                                          name: 'General Platform'))
                                  .name;
                              final isLast = companyAdmins.indexOf(admin) ==
                                  companyAdmins.length - 1;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  border: isLast
                                      ? null
                                      : Border(
                                          bottom: BorderSide(
                                              color: _dividerColor,
                                              width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        admin.name,
                                        style: GoogleFonts.poppins(
                                            color: _textColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        admin.email,
                                        style: GoogleFonts.poppins(
                                            color: _textSecondaryColor,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        compName,
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
                                              onTap: () => _deleteCompanyAdmin(
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

  Widget _buildSiteAdminsTab() {
    return Column(
      children: [
        // Header Section
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _cardColor,
                _cardColor.withValues(alpha: 0.8)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
                bottom: BorderSide(
                    color: _dividerColor, width: 1)),
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
                        color: _isDarkTheme 
                            ? Colors.black.withValues(alpha: 0.2) 
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _isDarkTheme 
                                ? AppColors.button.withValues(alpha: 0.2) 
                                : const Color(0xFF1B172E).withValues(alpha: 0.1),
                            width: 1),
                      ),
                      child: TextField(
                        controller: _searchSiteAdminController,
                        style: GoogleFonts.poppins(
                            color: _textColor, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search by name or email...',
                          hintStyle: GoogleFonts.poppins(
                              color: _textMutedColor, fontSize: 13),
                          prefixIcon: const Icon(Icons.search,
                              color: AppColors.button, size: 18),
                          suffixIcon: _searchSiteAdminController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear,
                                      color: _textMutedColor, size: 18),
                                  onPressed: () {
                                    _searchSiteAdminController.clear();
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
                      onPressed: _showAddSiteAdminDialog,
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
                      '${siteAdmins.length} Site Admin${siteAdmins.length != 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                          color: _textSecondaryColor,
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
                    child: Text('Registered',
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
          child: siteAdminsLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.button))
              : siteAdmins.isEmpty
                  ? _buildEmptyState('No site admins registered yet.',
                      Icons.admin_panel_settings_rounded)
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Container(
                        margin: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: _isDarkTheme ? const Color(0xFF131127) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _dividerColor,
                              width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Table Header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: _isDarkTheme ? const Color(0xFF1A172E) : const Color(0xFFEDF2F7),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Name',
                                      style: GoogleFonts.poppins(
                                          color: _textSecondaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      'Email',
                                      style: GoogleFonts.poppins(
                                          color: _textSecondaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Site',
                                      style: GoogleFonts.poppins(
                                          color: _textSecondaryColor,
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
                                            color: _textSecondaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(color: _dividerColor, height: 1),
                            // Table Rows
                            ...siteAdmins.map((admin) {
                              final isLast = siteAdmins.indexOf(admin) ==
                                  siteAdmins.length - 1;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  border: isLast
                                      ? null
                                      : Border(
                                          bottom: BorderSide(
                                              color: _dividerColor,
                                              width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        admin.name,
                                        style: GoogleFonts.poppins(
                                            color: _textColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        admin.email,
                                        style: GoogleFonts.poppins(
                                            color: _textSecondaryColor,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        admin.site.isNotEmpty
                                            ? admin.site
                                            : 'N/A',
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
                                                  _showEditSiteAdminDialog(
                                                      admin),
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
                                              onTap: () => _deleteSiteAdmin(
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

  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _isDarkTheme ? Colors.white12 : Colors.black12, size: 48),
            const SizedBox(height: 16),
            Text(msg,
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.poppins(color: _textSecondaryColor, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
