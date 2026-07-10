import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';

class CreateEquipmentPage extends StatefulWidget {
  const CreateEquipmentPage({super.key});

  @override
  State<CreateEquipmentPage> createState() => _CreateEquipmentPageState();
}

class _CreateEquipmentPageState extends State<CreateEquipmentPage> {
  final _formKey = GlobalKey<FormState>();

  // Form fields controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _shortIdController = TextEditingController();
  final TextEditingController _imeiController = TextEditingController();

  // Dropdown lists
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _systems = [];
  List<Map<String, dynamic>> _equipmentTypes = [];

  // Selected values
  String? _selectedCompanyId;
  String? _selectedSiteId;
  String? _selectedZoneId;
  String? _selectedSystemId;
  String? _selectedEquipmentTypeId;

  // Display names (shown fixed in UI)
  String _companyName = '';
  String _siteName = '';
  String _zoneName = '';

  // Loading states
  bool _isLoadingMetadata = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _generateShortId();
    _loadMetadata();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortIdController.dispose();
    _imeiController.dispose();
    super.dispose();
  }

  void _generateShortId() {
    final rand = Random();
    final num = rand.nextInt(900000) + 100000; // 6-digit number
    setState(() {
      _shortIdController.text = 'EQ-$num';
    });
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _isLoadingMetadata = true;
    });

    try {
      // Fetch data in parallel
      final results = await Future.wait([
        AdminService.fetchCompanies(),
        AdminService.fetchZones(),
        AdminService.fetchEquipmentTypes(),
        AuthService.getCompanyId(),
        AuthService.getSiteId(),
        AuthService.getZoneId(),
      ]);

      final companies = results[0] as List<Map<String, dynamic>>;
      final zones = results[1] as List<Map<String, dynamic>>;
      final equipmentTypes = results[2] as List<Map<String, dynamic>>;
      final savedCompanyId = results[3] as String?;
      final savedSiteId = results[4] as String?;
      final savedZoneId = results[5] as String?;

      if (mounted) {
        setState(() {
          _companies = companies;
          _zones = zones;
          _equipmentTypes = equipmentTypes;

          // 1. Pre-select company
          if (savedCompanyId != null && savedCompanyId.isNotEmpty) {
            final hasCompany = _companies.any((c) => 
                (c['companyId'] ?? c['id'] ?? '').toString() == savedCompanyId);
            if (hasCompany) {
              _selectedCompanyId = savedCompanyId;
            }
          }
          if (_selectedCompanyId == null && _companies.isNotEmpty) {
            _selectedCompanyId = (_companies.first['companyId'] ?? _companies.first['id'] ?? '').toString();
          }

          // Resolve company name
          if (_selectedCompanyId != null) {
            final companyObj = _companies.firstWhere(
              (c) => (c['companyId'] ?? c['id'] ?? '').toString() == _selectedCompanyId,
              orElse: () => {},
            );
            _companyName = (companyObj['name'] ?? companyObj['companyName'] ?? '').toString();
          }

          // 2. Pre-select zone
          if (savedZoneId != null && savedZoneId.isNotEmpty) {
            final hasZone = _zones.any((z) => 
                (z['zoneId'] ?? z['id'] ?? '').toString() == savedZoneId);
            if (hasZone) {
              _selectedZoneId = savedZoneId;
            }
          }
          if (_selectedZoneId == null && _zones.isNotEmpty) {
            _selectedZoneId = (_zones.first['zoneId'] ?? _zones.first['id'] ?? '').toString();
          }

          // Resolve zone name
          if (_selectedZoneId != null) {
            final zoneObj = _zones.firstWhere(
              (z) => (z['zoneId'] ?? z['id'] ?? '').toString() == _selectedZoneId,
              orElse: () => {},
            );
            _zoneName = (zoneObj['name'] ?? zoneObj['zoneName'] ?? '').toString();
          }

          // 3. Pre-select equipment type matching 'AC Monitoring System'
          if (_equipmentTypes.isNotEmpty) {
            final targetType = _equipmentTypes.firstWhere(
              (et) {
                final name = (et['name'] ?? et['equipmentTypeName'] ?? '').toString().toLowerCase();
                return name.contains('ac monitoring') || 
                       name.contains('ac_monitoring') || 
                       name.contains('acmonitoring') ||
                       name.contains('ac');
              },
              orElse: () => _equipmentTypes.first,
            );
            _selectedEquipmentTypeId = (targetType['equipmentTypeId'] ?? targetType['id'] ?? '').toString();
          }
        });

        // Fetch sites if company is selected
        if (_selectedCompanyId != null) {
          await _loadSitesForCompany(_selectedCompanyId!, savedSiteId);
        }

        // Fetch systems if company and site are selected
        if (_selectedCompanyId != null && _selectedSiteId != null) {
          await _loadSystemsForSite(_selectedCompanyId!, _selectedSiteId!);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading metadata: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMetadata = false;
        });
      }
    }
  }

  Future<void> _loadSitesForCompany(String companyId, [String? preselectSiteId]) async {
    try {
      final sites = await AdminService.fetchSites(companyId: companyId);
      if (mounted) {
        setState(() {
          _sites = sites;

          // Pre-select site
          if (preselectSiteId != null && preselectSiteId.isNotEmpty) {
            final hasSite = _sites.any((s) => 
                (s['siteId'] ?? s['id'] ?? '').toString() == preselectSiteId);
            if (hasSite) {
              _selectedSiteId = preselectSiteId;
            }
          }
          if (_selectedSiteId == null && _sites.isNotEmpty) {
            _selectedSiteId = (_sites.first['siteId'] ?? _sites.first['id'] ?? '').toString();
          }

          // Resolve site name
          if (_selectedSiteId != null) {
            final siteObj = _sites.firstWhere(
              (s) => (s['siteId'] ?? s['id'] ?? '').toString() == _selectedSiteId,
              orElse: () => {},
            );
            _siteName = (siteObj['name'] ?? siteObj['siteName'] ?? '').toString();
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading sites: $e');
    }
  }

  Future<void> _loadSystemsForSite(String companyId, String siteId) async {
    try {
      final systems = await AdminService.fetchSystems(companyId: companyId, siteId: siteId);
      if (mounted) {
        setState(() {
          _systems = systems;
          if (_systems.isNotEmpty) {
            _selectedSystemId = (_systems.first['systemId'] ?? _systems.first['id'] ?? '').toString();
          } else {
            _selectedSystemId = null;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading systems: $e');
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCompanyId == null || _selectedSiteId == null || 
        _selectedZoneId == null || _selectedSystemId == null || _selectedEquipmentTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Missing required details. Please check all fields.', style: GoogleFonts.inter()),
          backgroundColor: AppColors.offline,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final payload = {
      'name': _nameController.text.trim(),
      'shortId': _shortIdController.text.trim(),
      'companyId': _selectedCompanyId,
      'siteId': _selectedSiteId,
      'zoneId': _selectedZoneId,
      'systemId': _selectedSystemId,
      'equipmentTypeId': _selectedEquipmentTypeId,
      'imei': _imeiController.text.trim(),
      'oemType': 'AC Monitoring System',
      'equipmentPolicies': [],
    };

    try {
      final result = await AdminService.createEquipment(payload);
      if (mounted) {
        if (result['status'] == 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Equipment created successfully! 🎉', style: GoogleFonts.inter()),
              backgroundColor: AppColors.online,
            ),
          );
          Navigator.pop(context, true); // Return true to trigger reload
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to create equipment', style: GoogleFonts.inter()),
              backgroundColor: AppColors.offline,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e', style: GoogleFonts.inter()),
            backgroundColor: AppColors.offline,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.backgroundDark : AppColors.background;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'Create Equipment',
          style: GoogleFonts.outfit(
            color: textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _isLoadingMetadata
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Define New Equipment',
                      style: GoogleFonts.outfit(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Fill in the specifications below to register a new AC monitoring device.',
                      style: GoogleFonts.inter(
                        color: subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Main Fields Card (Name & Short ID)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Equipment Name Field
                          TextFormField(
                            controller: _nameController,
                            style: GoogleFonts.inter(color: textColor, fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Equipment Name',
                              labelStyle: GoogleFonts.inter(color: subtitleColor, fontSize: 13),
                              prefixIcon: Icon(Icons.ac_unit_rounded, color: subtitleColor, size: 20),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Equipment name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // Short ID Field with Generate Button
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _shortIdController,
                                  style: GoogleFonts.inter(color: textColor, fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText: 'Short ID',
                                    labelStyle: GoogleFonts.inter(color: subtitleColor, fontSize: 13),
                                    prefixIcon: Icon(Icons.qr_code_rounded, color: subtitleColor, size: 20),
                                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return 'Short ID is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                                tooltip: 'Regenerate ID',
                                onPressed: _generateShortId,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // IMEI Field
                          TextFormField(
                            controller: _imeiController,
                            style: GoogleFonts.inter(color: textColor, fontSize: 14),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'IMEI',
                              labelStyle: GoogleFonts.inter(color: subtitleColor, fontSize: 13),
                              prefixIcon: Icon(Icons.sim_card_rounded, color: subtitleColor, size: 20),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'IMEI is required';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Associations & Metadata Card (Dropdowns & Read-Only Info)
                    Text(
                      'Associations & Metadata',
                      style: GoogleFonts.outfit(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFixedRow(
                            label: 'Company',
                            icon: Icons.business_rounded,
                            value: _companyName,
                          ),
                          Divider(color: borderColor, height: 26),
                          _buildFixedRow(
                            label: 'Site',
                            icon: Icons.location_on_rounded,
                            value: _siteName,
                          ),
                          Divider(color: borderColor, height: 26),
                          _buildFixedRow(
                            label: 'Zone',
                            icon: Icons.grid_view_rounded,
                            value: _zoneName,
                          ),
                          Divider(color: borderColor, height: 26),

                          // System Selection Dropdown
                          Text(
                            'Assign System',
                            style: GoogleFonts.inter(
                              color: subtitleColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _selectedSystemId,
                            dropdownColor: cardColor,
                            style: GoogleFonts.inter(color: textColor, fontSize: 14),
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.apartment_rounded, color: subtitleColor, size: 20),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                            ),
                            items: _systems.map((sys) {
                              final name = (sys['name'] ?? sys['systemName'] ?? 'Unnamed System').toString();
                              final id = (sys['systemId'] ?? sys['id']).toString();
                              return DropdownMenuItem<String>(
                                value: id,
                                child: Text(name, style: GoogleFonts.inter(color: textColor)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedSystemId = val;
                              });
                            },
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'System assignment is required';
                              }
                              return null;
                            },
                          ),
                          Divider(color: borderColor, height: 26),

                          _buildFixedRow(
                            label: 'Equipment Type',
                            icon: Icons.tune_rounded,
                            value: 'AC Monitoring System',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 2,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                'Create Equipment',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFixedRow({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return Row(
      children: [
        Icon(icon, color: subtitleColor, size: 20),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: subtitleColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value.isNotEmpty ? value : 'Loading...',
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
