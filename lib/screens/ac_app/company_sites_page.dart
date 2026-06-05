import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/models/admin_model.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/main_navigation_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CompanySitesPage extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String bucket;

  const CompanySitesPage({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.bucket,
  });

  @override
  State<CompanySitesPage> createState() => _CompanySitesPageState();
}

class _CompanySitesPageState extends State<CompanySitesPage> {
  List<Site> sites = [];
  bool isLoading = true;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    try {
      final sitesList = await AdminService.fetchSites(
        companyId: widget.companyId,
        bucket: widget.bucket,
      );

      if (!mounted) return;
      setState(() {
        sites = sitesList
            .map((data) => Site.fromJson(data))
            .where((site) =>
                (site.companyId ?? '').trim().toLowerCase() ==
                widget.companyId.trim().toLowerCase())
            .toList();
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        _fitMapBounds();
      });
    } catch (e) {
      debugPrint('Error loading company sites: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _fitMapBounds() {
    if (_mapController == null || sites.isEmpty) return;
    
    final validSites = sites.where((s) => s.latitude != null && s.longitude != null).toList();
    if (validSites.isEmpty) return;
    
    if (validSites.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(validSites.first.latitude!, validSites.first.longitude!),
          11,
        ),
      );
      return;
    }
    
    double? minLat, maxLat, minLng, maxLng;
    for (final s in validSites) {
      if (minLat == null || s.latitude! < minLat) minLat = s.latitude;
      if (maxLat == null || s.latitude! > maxLat) maxLat = s.latitude;
      if (minLng == null || s.longitude! < minLng) minLng = s.longitude;
      if (maxLng == null || s.longitude! > maxLng) maxLng = s.longitude;
    }
    
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat!, minLng!),
          northeast: LatLng(maxLat!, maxLng!),
        ),
        50, // padding
      ),
    );
  }

  static const String _darkMapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [{"color": "#1d2c4d"}]
    },
    {
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#8ec3b9"}]
    },
    {
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#1a3646"}]
    },
    {
      "featureType": "administrative.country",
      "elementType": "geometry.stroke",
      "stylers": [{"color": "#4b687a"}]
    },
    {
      "featureType": "administrative.province",
      "elementType": "geometry.stroke",
      "stylers": [{"color": "#4b687a"}]
    },
    {
      "featureType": "landscape.man_made",
      "elementType": "geometry.stroke",
      "stylers": [{"color": "#334e87"}]
    },
    {
      "featureType": "landscape.natural",
      "elementType": "geometry",
      "stylers": [{"color": "#023e58"}]
    },
    {
      "featureType": "poi",
      "elementType": "geometry",
      "stylers": [{"color": "#283d6a"}]
    },
    {
      "featureType": "poi",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#6f9ba5"}]
    },
    {
      "featureType": "road",
      "elementType": "geometry",
      "stylers": [{"color": "#304a7d"}]
    },
    {
      "featureType": "road",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#98a5be"}]
    },
    {
      "featureType": "road.highway",
      "elementType": "geometry",
      "stylers": [{"color": "#2c4577"}]
    },
    {
      "featureType": "road.highway",
      "elementType": "geometry.stroke",
      "stylers": [{"color": "#1f2835"}]
    },
    {
      "featureType": "road.highway",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#f0d195"}]
    },
    {
      "featureType": "water",
      "elementType": "geometry",
      "stylers": [{"color": "#0e1626"}]
    },
    {
      "featureType": "water",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#4e5d6c"}]
    }
  ]
  ''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.companyName,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.button))
          : SingleChildScrollView(
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
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Builder(
                          builder: (context) {
                            LatLng initialPos = const LatLng(13.0827, 80.2707); // Chennai default
                            final firstValid = sites.firstWhere(
                              (s) => s.latitude != null && s.longitude != null,
                              orElse: () => Site(siteId: '', name: '', shortId: ''),
                            );
                            if (firstValid.siteId.isNotEmpty) {
                              initialPos = LatLng(firstValid.latitude!, firstValid.longitude!);
                            }

                            final markers = sites
                                .where((s) => s.latitude != null && s.longitude != null)
                                .map((s) => Marker(
                                      markerId: MarkerId(s.siteId),
                                      position: LatLng(s.latitude!, s.longitude!),
                                      infoWindow: InfoWindow(
                                        title: s.name,
                                        snippet: '${s.city ?? ''}, ${s.state ?? ''}'.trim(),
                                      ),
                                    ))
                                .toSet();

                            return GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: initialPos,
                                zoom: sites.length == 1 ? 11 : 9,
                              ),
                              markers: markers,
                              zoomControlsEnabled: true,
                              myLocationButtonEnabled: false,
                              mapToolbarEnabled: false,
                              onMapCreated: (controller) {
                                _mapController = controller;
                                _mapController?.setMapStyle(_darkMapStyle);
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

                    // Site Count Text
                    Text(
                      '${sites.length} ${sites.length == 1 ? "site" : "sites"} found',
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Site List
                    if (sites.isEmpty)
                      _buildEmptyState('No sites found for this company.', Icons.location_off_rounded)
                    else
                      ...sites.map((site) {
                        return GestureDetector(
                          onTap: () async {
                            await AuthService.setSelectedSiteAndCompany(
                              site.siteId,
                              widget.companyId,
                              zoneId: site.zoneId,
                              bucket: widget.bucket,
                            );
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MainNavigationPage(),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A172E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6CC042),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.location_on,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        site.name,
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${site.city ?? "Chennai"}, ${site.state ?? "Tamil Nadu"}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF6CC042),
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
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
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
