import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';

class SystemListPage extends StatefulWidget {
  const SystemListPage({super.key});

  @override
  State<SystemListPage> createState() => _SystemListPageState();
}

class _SystemListPageState extends State<SystemListPage> {
  List<Map<String, dynamic>> _systems = [];
  bool _isLoading = true;
  String? _companyId;
  String? _siteId;

  @override
  void initState() {
    super.initState();
    _loadSystems();
  }

  Future<void> _loadSystems() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _companyId = await AuthService.getCompanyId();
      _siteId = await AuthService.getSiteId();

      if (_companyId != null && _siteId != null) {
        final list = await AdminService.fetchSystems(
          companyId: _companyId!,
          siteId: _siteId!,
        );
        setState(() {
          _systems = list;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading systems: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showEditSheet(Map<String, dynamic> system) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: (system['name'] ?? '').toString());
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Edit System',
                            style: GoogleFonts.outfit(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: subtitleColor),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Modify the system name. Other fields are fixed to maintain system integrity.',
                        style: GoogleFonts.inter(
                          color: subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Editable Name Field
                      TextFormField(
                        controller: nameController,
                        style: GoogleFonts.inter(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'System Name',
                          labelStyle: GoogleFonts.inter(color: subtitleColor, fontSize: 13),
                          prefixIcon: Icon(Icons.dns_rounded, color: subtitleColor, size: 20),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'System name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Read-only Details
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow('Short ID', (system['shortId'] ?? 'N/A').toString(), subtitleColor, textColor),
                            const SizedBox(height: 10),
                            _buildInfoRow('System Type', (system['systemType']?['name'] ?? system['systemTypeName'] ?? 'AC Monitoring System').toString(), subtitleColor, textColor),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setSheetState(() {
                                    isSaving = true;
                                  });

                                  final payload = {
                                    'systemId': system['systemId'],
                                    'name': nameController.text.trim(),
                                    'shortId': system['shortId'],
                                    'companyId': system['companyId'] ?? _companyId,
                                    'siteId': system['siteId'] ?? _siteId,
                                    'zoneId': system['zoneId'],
                                    'systemTypeId': system['systemTypeId'],
                                    'systemPolicies': system['systemPolicies'] ?? [],
                                  };

                                  final result = await AdminService.updateSystem(
                                    system['systemId'].toString(),
                                    payload,
                                  );

                                  if (mounted) {
                                    setSheetState(() {
                                      isSaving = false;
                                    });
                                    Navigator.pop(context);

                                    if (result['status'] == 1) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('System updated successfully', style: GoogleFonts.inter()),
                                          backgroundColor: AppColors.primary,
                                        ),
                                      );
                                      _loadSystems();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(result['error'] ?? 'Failed to update system', style: GoogleFonts.inter()),
                                          backgroundColor: AppColors.offline,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'Save Changes',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, Color labelColor, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: labelColor, fontSize: 12),
        ),
        Text(
          value,
          style: GoogleFonts.inter(color: valueColor, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
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
          'Manage Systems',
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _loadSystems,
              color: AppColors.primary,
              child: _systems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dns_rounded, size: 48, color: subtitleColor),
                          const SizedBox(height: 16),
                          Text(
                            'No systems found',
                            style: GoogleFonts.outfit(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pull down to refresh or create a new system.',
                            style: GoogleFonts.inter(
                              color: subtitleColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      itemCount: _systems.length,
                      itemBuilder: (context, index) {
                        final system = _systems[index];
                        final name = (system['name'] ?? 'Unnamed System').toString();
                        final shortId = (system['shortId'] ?? 'N/A').toString();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
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
                          child: InkWell(
                            onTap: () => _showEditSheet(system),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Leading DNS Icon
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.dns_rounded,
                                      color: AppColors.primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.outfit(
                                            color: textColor,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ID: $shortId',
                                          style: GoogleFonts.inter(
                                            color: subtitleColor,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Edit Icon
                                  Icon(
                                    Icons.edit_outlined,
                                    color: subtitleColor,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
