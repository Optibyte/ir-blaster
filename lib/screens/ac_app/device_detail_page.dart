import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:esp/core/services/auth_service.dart';
import 'dart:async';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:esp/widgets/trends_table.dart';
import 'package:esp/core/config/app_config.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class DeviceDetailPage extends StatefulWidget {
  final String deviceName;
  final String systemId;
  final String systemShortId;

  const DeviceDetailPage({
    Key? key,
    required this.deviceName,
    required this.systemId,
    required this.systemShortId,
  }) : super(key: key);

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage>
    with SingleTickerProviderStateMixin {
  // UI State
  double _setTemperature = 24.0; // Fixed static value
  double _actualTemperature = 0.0;
  String _status = '--';
  int _humidity = 0;
  String _scheduleOn = '--:--';
  String _scheduleOff = '--:--';
  String _lunchOn = '--:--';
  String _lunchOff = '--:--';
  bool _isAuto = false;
  bool _isPowerOn = true; // Tracks the MQTT Power Status

  // Chart & Log State
  final List<_ChartData> _tempHistory = [];
  final List<Map<String, dynamic>> _recentLogs = [];

  // Equipment State
  List<Map<String, dynamic>> _equipmentsData = [];
  List<String> _equipments = [];
  bool _isLoadingEquipments = true;
  bool _isTelemetryLoading = true;
  String _selectedEquipmentName = '';
  String _selectedEquipmentId = '';
  String _selectedEquipmentTypeId = '';
  String _selectedEquipmentShortId = '';
  String _deviceId = ''; // IMEI

  // Stream State
  StreamSubscription? _subscription;
  DateTime _lastUpdateTime = DateTime.now(); // For throttling UI updates

  // Animation State
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _selectedEquipmentName = widget.deviceName;
    _fetchEquipments();

    // Seed initial data for chart
    for (int i = 0; i < 10; i++) {
      _tempHistory.add(
        _ChartData(
          DateTime.now().subtract(Duration(minutes: 10 - i)),
          30 + math.Random().nextDouble() * 5,
        ),
      );
    }
  }

  @override
  void dispose() {
    _closeStream();
    _pulseController?.dispose();
    super.dispose();
  }

  void _closeStream() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _fetchEquipments() async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final url =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/systems/equipment/${widget.systemId}'
        '?companyId=$companyId&siteId=$siteId&bucket=$bucket';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> equipmentList = data['data'];

        if (mounted) {
          setState(() {
            _equipmentsData = List<Map<String, dynamic>>.from(equipmentList);
            _equipments = _equipmentsData
                .map((e) => e['name'] as String? ?? 'Unknown')
                .toList();
            _isLoadingEquipments = false;

            // Auto-select first equipment if not already selected or if current selection is dummy
            if (_equipmentsData.isNotEmpty) {
              final initialIndex = _equipmentsData.indexWhere(
                (e) => e['name'] == widget.deviceName,
              );
              final targetIndex = initialIndex != -1 ? initialIndex : 0;

              final eData = _equipmentsData[targetIndex];
              _onEquipmentSelected(
                eData['equipmentId']?.toString() ?? '',
                eData['name']?.toString() ?? '',
                eData['equipmentTypeId']?.toString() ?? '',
                (eData['shortId'] ?? eData['equipmentShortId'])?.toString() ??
                    '',
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching equipments: $e');
      if (mounted) {
        setState(() => _isLoadingEquipments = false);
      }
    }
  }

  Future<void> _onEquipmentSelected(
    String equipmentId,
    String name,
    String typeId,
    String shortId,
  ) async {
    debugPrint(
      '🔄 SWITCHING EQUIPMENT: ID=$equipmentId, Name=$name, ShortId=$shortId',
    );
    if (_selectedEquipmentId == equipmentId &&
        _selectedEquipmentShortId.isNotEmpty) return;

    _closeStream();

    setState(() {
      _selectedEquipmentId = equipmentId;
      _selectedEquipmentName = name;
      _selectedEquipmentTypeId = typeId;
      _selectedEquipmentShortId = shortId;
      _isLoadingEquipments = true;
      _isTelemetryLoading = true;
      _tempHistory.clear();
      _recentLogs.clear();
    });

    final imei = await _fetchEquipmentImei(equipmentId);

    if (mounted) {
      setState(() {
        _deviceId = imei;
        _isLoadingEquipments = false;
      });

      if (imei.isNotEmpty) {
        _connectToStream(imei);
      } else {
        setState(() => _isTelemetryLoading = false);
      }
    }
  }

  Future<void> _togglePower(bool value) async {
    // Direct MQTT connection from Frontend
    final client = MqttServerClient(
        '13.66.130.236', 'flutter_ac_${DateTime.now().millisecondsSinceEpoch}');
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_ac_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs('demo', 'demo')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMessage;

    // Optimistic UI update
    setState(() => _isPowerOn = value);

    try {
      debugPrint('📡 MQTT [FRONTEND]: Connecting to 13.66.130.236...');
      await client.connect();

      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        debugPrint('✅ MQTT [FRONTEND]: Connected');

        final payload = 'sustainabyte_demo:STATUS_${value ? "ON" : "OFF"}';
        final builder = MqttClientPayloadBuilder();
        builder.addString(payload);

        debugPrint('📤 MQTT [FRONTEND]: Publishing "$payload" to topic "demo"');
        client.publishMessage('demo', MqttQos.atLeastOnce, builder.payload!);

        // Brief delay to ensure message is sent before disconnecting
        await Future.delayed(const Duration(milliseconds: 500));
        client.disconnect();
        debugPrint('🔌 MQTT [FRONTEND]: Disconnected');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('AC Power turned ${value ? 'ON' : 'OFF'} (via MQTT)'),
              backgroundColor: value ? Colors.green : Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        throw Exception(
            'Connection failed with state: ${client.connectionStatus!.state}');
      }
    } catch (e) {
      debugPrint('❌ MQTT [FRONTEND] Error: $e');
      setState(() => _isPowerOn = !value); // Rollback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('MQTT Error: $e'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<String> _fetchEquipmentImei(String equipmentId) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final url =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/equipments/$equipmentId'
        '?companyId=$companyId&siteId=$siteId&bucket=$bucket';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Assuming IMEI is in data['data']['imei'] or similar field
        // Looking at the user's provided JSON, I don't see imei, but they said "take from the imei is an device_id"
        // Let's check the first equipment structure again
        final equipData = data['data'];
        if (equipData is List && equipData.isNotEmpty) {
          return equipData[0]['imei'] ?? equipData[0]['shortId'] ?? '';
        } else if (equipData is Map) {
          return equipData['imei'] ?? equipData['shortId'] ?? '';
        }
      }
    } catch (e) {
      debugPrint('Error fetching IMEI: $e');
    }
    return '';
  }

  Future<void> _connectToStream(String imei) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    // The error "not upgraded to websocket" suggests this is an HTTP Stream (SSE/NDJSON)
    // rather than a true WebSocket. We will use http.Client to listen to the stream.
    final url =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/mqtt/stream?companyid=$companyId&deviceId=$imei';

    debugPrint('🌐 [HTTP Stream] Connecting to: $url');

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'text/event-stream'; // Standard for SSE

      final response = await client.send(request);

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() => _isTelemetryLoading = false);
        }
        _subscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter()) // Handle line-by-line JSON
            .listen(
          (line) {
            if (line.trim().isEmpty) return;
            debugPrint('📥 [HTTP Stream] Data: $line');
            _parseAndMapData(line);
          },
          onError: (error) {
            debugPrint('❌ [HTTP Stream] Error: $error');
          },
          onDone: () {
            debugPrint('🔌 [HTTP Stream] Stream closed');
            client.close();
          },
        );
      } else {
        debugPrint('❌ [HTTP Stream] Connection failed: ${response.statusCode}');
        if (mounted) {
          setState(() => _isTelemetryLoading = false);
        }
      }
    } catch (e) {
      debugPrint('❌ [HTTP Stream] Connection Exception: $e');
      if (mounted) {
        setState(() => _isTelemetryLoading = false);
      }
    }
  }

  void _parseAndMapData(String line) {
    try {
      // Remove "data: " prefix if it's SSE format
      String jsonStr = line;
      if (line.startsWith('data: ')) {
        jsonStr = line.substring(6);
      }

      final data = jsonDecode(jsonStr);

      // Based on log: data -> data -> { time, brand, ac, temp, hum, auto, ... }
      Map<String, dynamic>? payload;

      if (data['data'] != null && data['data']['data'] != null) {
        payload = Map<String, dynamic>.from(data['data']['data']);
      } else if (data['data'] != null) {
        payload = Map<String, dynamic>.from(data['data']);
      }

      if (payload != null && mounted) {
        bool hasChanges = false;

        double newTemp = _actualTemperature;
        if (payload['temp'] != null) {
          newTemp =
              double.tryParse(payload['temp'].toString()) ?? _actualTemperature;
          if ((newTemp - _actualTemperature).abs() > 0.05) hasChanges = true;
        }

        int newHum = _humidity;
        if (payload['hum'] != null) {
          newHum = (double.tryParse(payload['hum'].toString()) ??
                  _humidity.toDouble())
              .toInt();
          if (newHum != _humidity) hasChanges = true;
        }

        String newStatus = _status;
        if (payload['ac'] != null || payload['ACStatus'] != null) {
          newStatus = (payload['ac'] ?? payload['ACStatus']).toString() == 'ON'
              ? 'Active'
              : 'Inactive';
          if (newStatus != _status) hasChanges = true;
        }

        String newSchOn = _scheduleOn;
        if (payload['schedule_on'] != null || payload['scheduleOn'] != null) {
          newSchOn =
              (payload['schedule_on'] ?? payload['scheduleOn']).toString();
          if (newSchOn != _scheduleOn) hasChanges = true;
        }

        String newSchOff = _scheduleOff;
        if (payload['schedule_off'] != null || payload['scheduleOff'] != null) {
          newSchOff =
              (payload['schedule_off'] ?? payload['scheduleOff']).toString();
          if (newSchOff != _scheduleOff) hasChanges = true;
        }

        String newLunchOn = _lunchOn;
        if (payload['lunch_on'] != null || payload['lunchOn'] != null) {
          newLunchOn = (payload['lunch_on'] ?? payload['lunchOn']).toString();
          if (newLunchOn != _lunchOn) hasChanges = true;
        }

        String newLunchOff = _lunchOff;
        if (payload['lunch_off'] != null || payload['lunchOff'] != null) {
          newLunchOff =
              (payload['lunch_off'] ?? payload['lunchOff']).toString();
          if (newLunchOff != _lunchOff) hasChanges = true;
        }

        bool newAuto = _isAuto;
        if (payload['auto'] != null || payload['isAuto'] != null) {
          newAuto = (payload['auto'] ?? payload['isAuto']) == true;
          if (newAuto != _isAuto) hasChanges = true;
        }

        if (_isTelemetryLoading)
          hasChanges = true; // Always update on first data

        final now = DateTime.now();
        final shouldUpdateUI = hasChanges &&
            (now.difference(_lastUpdateTime).inMilliseconds > 500 ||
                _isTelemetryLoading);

        if (shouldUpdateUI) {
          _lastUpdateTime = now;
          setState(() {
            _isTelemetryLoading = false;
            _actualTemperature = newTemp;
            _humidity = newHum;
            _status = newStatus;
            _scheduleOn = newSchOn;
            _scheduleOff = newSchOff;
            _lunchOn = newLunchOn;
            _lunchOff = newLunchOff;
            _isAuto = newAuto;

            // Update Chart Data (Only if temp changed)
            _tempHistory.add(_ChartData(DateTime.now(), _actualTemperature));
            if (_tempHistory.length > 20) _tempHistory.removeAt(0);

            // Update Logs
            _recentLogs.insert(0, {
              'time': payload!['time'] ??
                  DateTime.now().toString().split('.').first,
              'temp': _actualTemperature.toStringAsFixed(1),
              'hum': _humidity,
              'ac': _status == 'Active' ? 'ON' : 'OFF',
            });
            if (_recentLogs.length > 5) _recentLogs.removeLast();
          });
        }
      }
    } catch (e) {
      debugPrint('Error parsing Stream data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : const Color(0xFF1B172E),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _selectedEquipmentName,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : const Color(0xFF1B172E),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_pulseController != null)
            FadeTransition(
              opacity: Tween(begin: 0.3, end: 1.0).animate(
                CurvedAnimation(
                  parent: _pulseController!,
                  curve: Curves.easeInOut,
                ),
              ),
              child: IconButton(
                onPressed: () => _showDataInsights(isDark),
                icon: Icon(
                  Icons.analytics_outlined,
                  color: isDark
                      ? const Color(0xFF6CC042)
                      : const Color(0xFF10B981),
                  size: 24,
                ),
                tooltip: 'Trends',
              ),
            )
          else
            const SizedBox(width: 48),
          const SizedBox(width: 8),
        ],
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildEquipmentTabs(isDark, colorScheme),
                const SizedBox(height: 48),
                RepaintBoundary(
                  child: _ThermostatGauge(
                    setTemp: _setTemperature,
                    actualTemp: _actualTemperature,
                    isDark: isDark,
                    colorScheme: colorScheme,
                    onTap: () {}, // Disabled interaction
                  ),
                ),
                const SizedBox(height: 32),
                _buildDetailStats(isDark, colorScheme),
                const SizedBox(height: 40),
              ],
            ),
          ),
          if (_isLoadingEquipments || _isTelemetryLoading)
            Positioned.fill(child: _buildFullPageSkeleton(isDark)),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildFullPageSkeleton(bool isDark) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: isDark ? const Color(0xFF1B172E) : Colors.white,
      child: SingleChildScrollView(
        physics:
            const NeverScrollableScrollPhysics(), // Prevent scrolling while loading
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Tabs Skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(
                  3,
                  (i) => Container(
                    width: 80,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Gauge Skeleton
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 50),
            // Stats Skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Schedule Skeleton
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Lunch Skeleton
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  const SizedBox(height: 100), // Ensure bottom is covered
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Temperature Trends',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              primaryXAxis: DateTimeAxis(isVisible: false),
              primaryYAxis: NumericAxis(
                isVisible: false,
                minimum: 20,
                maximum: 40,
              ),
              plotAreaBorderWidth: 0,
              series: <CartesianSeries<_ChartData, DateTime>>[
                SplineAreaSeries<_ChartData, DateTime>(
                  dataSource: _tempHistory,
                  xValueMapper: (_ChartData data, _) => data.time,
                  yValueMapper: (_ChartData data, _) => data.temp,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6CC042).withOpacity(0.3),
                      const Color(0xFF6CC042).withOpacity(0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderColor: const Color(0xFF6CC042),
                  borderWidth: 2,
                  animationDuration: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Log',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                children: [
                  _tableHeader('TIME', isDark),
                  _tableHeader('TEMP', isDark),
                  _tableHeader('AC', isDark),
                ],
              ),
              ..._recentLogs.map(
                (log) => TableRow(
                  children: [
                    _tableCell(log['time'].toString().split(' ').last, isDark),
                    _tableCell('${log['temp']}°', isDark),
                    _tableCell(
                      log['ac']?.toString() ?? 'N/A',
                      isDark,
                      color: log['ac'] == 'ON'
                          ? const Color(0xFF6CC042)
                          : Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            color: Colors.white24,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _tableCell(String text, bool isDark, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            color: color ?? (isDark ? Colors.white70 : Colors.black87),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  void _showDataInsights(bool isDark) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';

    // Find the current equipment data for debugging
    final selectedData = _equipmentsData.firstWhere(
      (e) => e['equipmentId']?.toString() == _selectedEquipmentId,
      orElse: () => {},
    );

    debugPrint('🔍 DEBUGGING TRENDS NAVIGATION:');
    debugPrint('🆔 Selected Equipment ID: $_selectedEquipmentId');
    debugPrint('🏷️ Selected Short ID: $_selectedEquipmentShortId');
    debugPrint('📱 Device ID (IMEI): $_deviceId');
    debugPrint('📦 Full Equipment Data: $selectedData');

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _TrendsPage(
          isDark: isDark,
          systemId: widget.systemId,
          systemName: widget.deviceName, // This holds the system name
          systemShortId: widget.systemShortId,
          equipmentId: _selectedEquipmentId,
          equipmentName: _selectedEquipmentName,
          equipmentTypeId: _selectedEquipmentTypeId,
          equipmentShortId: _selectedEquipmentShortId,
          companyId: companyId,
          siteId: siteId,
          bucket: bucket,
        ),
      ),
    );
  }

  Widget _buildEquipmentTabs(bool isDark, ColorScheme colorScheme) {
    if (_equipments.isEmpty) return const SizedBox();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // First two equipments
          ..._equipmentsData.take(2).map(
                (e) => _buildTab(
                  e['name']?.toString() ?? 'N/A',
                  e['equipmentId']?.toString() == _selectedEquipmentId,
                  isDark,
                  colorScheme,
                  e['equipmentId']?.toString() ?? '',
                  e['equipmentTypeId']?.toString() ?? '',
                  e['shortId']?.toString() ?? '',
                ),
              ),

          // More button
          GestureDetector(
            onTap: () => _showAllEquipmentsPopup(isDark, colorScheme),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Text(
                    'More',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.double_arrow_rounded,
                    color: const Color(0xFF6CC042),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
    String label,
    bool isActive,
    bool isDark,
    ColorScheme colorScheme,
    String equipmentId,
    String equipmentTypeId,
    String shortId,
  ) {
    return GestureDetector(
      onTap: () =>
          _onEquipmentSelected(equipmentId, label, equipmentTypeId, shortId),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    const Color(0xFF0EA5E9).withOpacity(0.2),
                    const Color(0xFF0EA5E9).withOpacity(0.05),
                  ],
                )
              : null,
          color: !isActive
              ? (isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.grey.withOpacity(0.1))
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? const Color(0xFF0EA5E9).withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: isActive 
                ? const Color(0xFF0EA5E9) 
                : (isDark ? Colors.white70 : Colors.black54),
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showAllEquipmentsPopup(bool isDark, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Equipment',
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : const Color(0xFF1B172E),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6CC042).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Total: ${_equipmentsData.length}',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF6CC042),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _equipmentsData.length,
            itemBuilder: (context, index) {
              final eData = _equipmentsData[index];
              final String e = eData['name']?.toString() ?? 'Unknown';
              final String id = eData['equipmentId']?.toString() ?? '';
              final isSelected = id == _selectedEquipmentId;
              return ListTile(
                onTap: () {
                  _onEquipmentSelected(
                    id,
                    e,
                    eData['equipmentTypeId']?.toString() ?? '',
                    (eData['shortId'] ?? eData['equipmentShortId'])
                            ?.toString() ??
                        '',
                  );
                  Navigator.pop(context);
                },
                leading: Icon(
                  Icons.ac_unit,
                  color: isSelected 
                      ? const Color(0xFF6CC042) 
                      : (isDark ? Colors.white24 : Colors.black26),
                ),
                title: Text(
                  e,
                  style: GoogleFonts.poppins(
                    color: isSelected 
                        ? (isDark ? Colors.white : const Color(0xFF1B172E)) 
                        : (isDark ? Colors.white60 : Colors.black54),
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Color(0xFF6CC042))
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }

  void _showActualTempPopup(double temp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.3),
      isScrollControlled: true,
      builder: (context) => Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1B172E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border.all(
              color: const Color(0xFF6CC042).withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6CC042).withOpacity(0.1),
              blurRadius: 30,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              Icons.cloud_queue_rounded,
              color: const Color(0xFF6CC042),
              size: 54,
            ),
            const SizedBox(height: 16),
            Text(
              'CURRENT TEMPERATURE',
              style: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${temp.toStringAsFixed(1)}°C',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6CC042).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.water_drop_rounded,
                      color: Color(0xFF6CC042), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'HUMIDITY: $_humidity%',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6CC042),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickControls(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _controlButton(
            icon: Icons.power_settings_new_rounded,
            label: 'POWER',
            isActive: _status == 'Active',
            activeColor: const Color(0xFFEF4444),
            onTap: () => setState(
              () => _status = _status == 'Active' ? 'Inactive' : 'Active',
            ),
            isDark: isDark,
          ),
          _controlButton(
            icon: Icons.ac_unit_rounded,
            label: 'MODE',
            isActive: true,
            activeColor: const Color(0xFF3B82F6),
            onTap: () {},
            isDark: isDark,
          ),
          _controlButton(
            icon: Icons.air_rounded,
            label: 'FAN',
            isActive: true,
            activeColor: const Color(0xFF10B981),
            onTap: () {},
            isDark: isDark,
          ),
          _controlButton(
            icon: Icons.more_horiz_rounded,
            label: 'MORE',
            isActive: false,
            activeColor: Colors.white,
            onTap: () {},
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(0.15)
                  : (isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isActive
                    ? activeColor.withOpacity(0.3)
                    : Colors.white.withOpacity(0.05),
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.2),
                        blurRadius: 15,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive
                  ? activeColor
                  : (isDark ? Colors.white38 : Colors.black38),
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white24 : Colors.black26,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStats(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // 1. Status and Humidity Row
          Row(
            children: [
              Expanded(child: _buildStatusCard(isDark)),
              const SizedBox(width: 16),
              Expanded(child: _buildHumidityCard(isDark)),
            ],
          ),
          const SizedBox(height: 24),

          // 2. Schedule Section
          RepaintBoundary(child: _buildScheduleSection(isDark)),
          const SizedBox(height: 24),

          // 3. Lunch Section
          RepaintBoundary(child: _buildLunchSection(isDark)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isDark) {
    bool isActive = _status == 'Active';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AC STATUS',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white24 : Colors.black45,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _isPowerOn
                      ? Text('ONLINE',
                          style: GoogleFonts.poppins(
                              color: const Color(0xFF6CC042),
                              fontSize: 8,
                              fontWeight: FontWeight.bold))
                      : Text('OFFLINE',
                          style: GoogleFonts.poppins(
                              color: Colors.redAccent,
                              fontSize: 8,
                              fontWeight: FontWeight.bold)),
                ],
              ),
              const Spacer(),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _isPowerOn,
                  onChanged: _togglePower,
                  activeColor: const Color(0xFF6CC042),
                  activeTrackColor: const Color(0xFF6CC042).withOpacity(0.1),
                  inactiveThumbColor: isDark ? Colors.white24 : Colors.grey.shade400,
                  inactiveTrackColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color:
                      _isPowerOn ? const Color(0xFF6CC042) : Colors.redAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isPowerOn
                              ? const Color(0xFF6CC042)
                              : Colors.redAccent)
                          .withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                isActive ? Icons.ac_unit_rounded : Icons.power_off_rounded,
                color: isActive ? const Color(0xFF6CC042) : Colors.white24,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                _isPowerOn ? 'ACTIVE' : 'INACTIVE',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHumidityCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HUMIDITY',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white24 : Colors.black45,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _humidity / 100,
                      strokeWidth: 4,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF0EA5E9),
                      ),
                    ),
                    const Icon(
                      Icons.water_drop_rounded,
                      size: 12,
                      color: Color(0xFF0EA5E9),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '$_humidity%',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(bool isDark) {
    double start = _parseTimeToDouble(_scheduleOn);
    double end = _parseTimeToDouble(_scheduleOff);

    return GestureDetector(
      onTap: () => _showSchedulePicker(isDark),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26213A) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Daily Schedule',
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _isAuto ? _buildAutoBadge() : const SizedBox(),
              ],
            ),
            const SizedBox(height: 24),
            // Sun & Moon Timeline with Pins
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _timePin('00', isDark),
                    _timePin('06', isDark),
                    _timePin('12', isDark),
                    _timePin('18', isDark),
                    _timePin('24', isDark),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    final left = (start / 24) * totalWidth;
                    final width = ((end - start) / 24) * totalWidth;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background Track with Day/Night Hint
                        Container(
                          height: 14,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.05),
                                      Colors.white.withOpacity(0.08),
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      const Color(0xFFE0F2FE), // Light sky blue
                                      const Color(0xFFF1F5F9), // Light grey
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        // Contextual Icons
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(Icons.nights_stay_rounded, 
                                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.2), size: 10),
                              Icon(Icons.wb_sunny_rounded, 
                                  color: isDark ? Colors.white10 : Colors.orange.withOpacity(0.4), size: 10),
                              Icon(Icons.nights_stay_rounded, 
                                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.2), size: 10),
                            ],
                          ),
                        ),
                        // Active Schedule Range
                        Positioned(
                          left: left,
                          width: width.clamp(0, totalWidth - left),
                          child: Container(
                            height: 14,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF6CC042),
                                  Color(0xFF86EFAC),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6CC042).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _timeSimpleLabel('FROM', _scheduleOn, isDark),
                _timeSimpleLabel('TO', _scheduleOff, isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _parseTimeToDouble(String timeStr) {
    if (timeStr == '--:--' || timeStr.isEmpty) return 0.0;
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return 0.0;
      final hr = double.tryParse(parts[0]) ?? 0.0;
      final min = double.tryParse(parts[1]) ?? 0.0;
      return hr + (min / 60.0);
    } catch (e) {
      return 0.0;
    }
  }

  Widget _timeSimpleLabel(String label, String time, bool isDark) {
    return Column(
      crossAxisAlignment:
          label == 'FROM' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white24 : Colors.black45,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          time,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _timePin(String time, bool isDark) {
    return Text(
      time,
      style: GoogleFonts.poppins(
        color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.4),
        fontSize: 8,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildLunchSection(bool isDark) {
    double start = _parseTimeToDouble(_lunchOn);
    double end = _parseTimeToDouble(_lunchOff);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Vertical Indicator
          LayoutBuilder(
            builder: (context, constraints) {
              final totalHeight = 100.0;
              final top = (start / 24) * totalHeight;
              final height = ((end - start) / 24) * totalHeight;

              return Container(
                width: 12,
                height: totalHeight,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: top,
                      height: height.clamp(
                        4.0,
                        totalHeight,
                      ), // Minimum 4px for visibility
                      left: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orangeAccent.withOpacity(0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Lunch Break',
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.restaurant_rounded,
                      color: Colors.orangeAccent.withOpacity(0.5),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _lunchTimeRow('START', _lunchOn),
                const SizedBox(height: 8),
                _lunchTimeRow('END', _lunchOff),
                const SizedBox(height: 12),
                Text(
                  '1 HOUR DURATION',
                  style: GoogleFonts.poppins(
                    color: Colors.orangeAccent,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lunchTimeRow(String label, String time) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          time,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _lunchSimpleLabel(String label, String time, bool isDark) {
    return Column(
      crossAxisAlignment:
          label == 'START' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          time,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6CC042).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'AUTO',
        style: GoogleFonts.poppins(
          color: const Color(0xFF6CC042),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTimeTimeline(
    bool isDark,
    String onTime,
    String offTime,
    String label, {
    Color color = const Color(0xFF6CC042),
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _timeLabel(onTime, 'START', color),
            _timeLabel(offTime, 'END', Colors.redAccent),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(
                left: 40,
                right: 80,
              ), // Mock active range
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.5)],
                ),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white24 : Colors.black45,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _timeLabel(String time, String type, Color color) {
    return Column(
      crossAxisAlignment:
          type == 'START' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          type,
          style: GoogleFonts.poppins(
            color: Colors.white24,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          time,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTimePill(
    String label,
    String hr,
    String min,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$hr:$min',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : const Color(0xFF1B172E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallTimeBox(String hr, String min, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$hr:$min',
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showSchedulePicker(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => _ScheduleControlDialog(
        isDark: isDark,
        initialOn: _scheduleOn,
        initialOff: _scheduleOff,
        onCommand: (type, time) => _publishMqttSchedule(type, time),
        onClear: () => _publishMqttSchedule('SCH_CLEAR', null),
      ),
    );
  }

  Future<void> _publishMqttSchedule(String type, String? time) async {
    final client = MqttServerClient('13.66.130.236',
        'flutter_sch_${DateTime.now().millisecondsSinceEpoch}');
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_sch_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs('demo', 'demo')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMessage;

    try {
      debugPrint('📡 MQTT [SCH]: Connecting...');
      await client.connect();
      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        String payload = 'sustainabyte_demo:$type';
        if (time != null) payload += ':$time';
        final builder = MqttClientPayloadBuilder();
        builder.addString(payload);
        debugPrint('📤 MQTT [SCH]: Publishing "$payload"');
        client.publishMessage('demo', MqttQos.atLeastOnce, builder.payload!);
        await Future.delayed(const Duration(milliseconds: 500));
        client.disconnect();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Command Sent: $type'),
                backgroundColor: const Color(0xFF6CC042),
                behavior: SnackBarBehavior.floating),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ MQTT [SCH] Error: $e');
    }
  }
}

class _ThermostatGauge extends StatelessWidget {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ThermostatGauge({
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              if (isDark)
                BoxShadow(
                  color: _getColorForTemp(actualTemp).withOpacity(0.15),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
            ],
          ),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ThermostatPainter(
                setTemp: setTemp,
                actualTemp: actualTemp,
                isDark: isDark,
                colorScheme: colorScheme,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'SET TEMP',
                      style: GoogleFonts.poppins(
                        color: (isDark ? Colors.white : colorScheme.primary)
                            .withOpacity(0.4),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${setTemp.toInt()}°C',
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : const Color(0xFF1B172E),
                        fontSize: 54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ACTUAL   ${actualTemp.toStringAsFixed(1)}°C',
                      style: GoogleFonts.poppins(
                        color: (isDark ? Colors.white : colorScheme.primary)
                            .withOpacity(0.5),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getColorForTemp(double temp) {
    if (temp < 20) return const Color(0xFFEF4444);
    if (temp < 22) return const Color(0xFFF59E0B);
    if (temp < 26) return const Color(0xFF10B981);
    if (temp < 28) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

class _ThermostatPainter extends CustomPainter {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final ColorScheme colorScheme;

  _ThermostatPainter({
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    double tempToAngle(double temp) => (temp / 40) * sweepAngle + startAngle;

    // 1. Color Ranges Background (Main Track)
    final trackRect = Rect.fromCircle(center: center, radius: radius - 15);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    void drawTrackRange(double start, double end, Color color) {
      final sAngle = tempToAngle(start);
      final swAngle = ((end - start) / 40) * sweepAngle;
      trackPaint.color = color.withOpacity(0.15);
      canvas.drawArc(trackRect, sAngle, swAngle, false, trackPaint);
    }

    drawTrackRange(0, 20, const Color(0xFFEF4444));
    drawTrackRange(20, 22, const Color(0xFFFBBF24));
    drawTrackRange(22, 26, const Color(0xFF6CC042));
    drawTrackRange(26, 28, const Color(0xFFFBBF24));
    drawTrackRange(28, 40, const Color(0xFFEF4444));

    // 2. Full Background Track (The "missing" circle)
    final fullTrackPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawCircle(center, radius - 15, fullTrackPaint);

    // 2.5 Range Boundary Dots (Small color indicators)
    final dotPoints = [20.0, 22.0, 26.0, 28.0];
    for (final p in dotPoints) {
      final angle = tempToAngle(p);
      final dotPos = Offset(
        center.dx + (radius - 15) * math.cos(angle),
        center.dy + (radius - 15) * math.sin(angle),
      );
      final dotColor = _getColorForTemp(p);

      // Shadow for dot
      canvas.drawCircle(
        dotPos,
        4,
        Paint()..color = Colors.black.withOpacity(0.5),
      );
      // Colored dot
      canvas.drawCircle(dotPos, 3, Paint()..color = dotColor);
    }

    // 2.6 Partial Base Track (270 degrees)
    final basePaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.05)
          : colorScheme.primary.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(trackRect, startAngle, sweepAngle, false, basePaint);

    // 3. Active Arc with Glow (Representing Actual Temp now)
    final activeColor = _getColorForTemp(actualTemp);
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = activeColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..strokeCap = StrokeCap.round;

    final currentSweep = (actualTemp / 40) * sweepAngle;
    canvas.drawArc(trackRect, startAngle, currentSweep, false, glowPaint);
    canvas.drawArc(trackRect, startAngle, currentSweep, false, activePaint);

    // 4. Handle (representing the indicator point)
    final handleAngle = currentSweep + startAngle;
    final handlePos = Offset(
      center.dx + (radius - 15) * math.cos(handleAngle),
      center.dy + (radius - 15) * math.sin(handleAngle),
    );

    canvas.drawCircle(
      handlePos,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(handlePos, 6, Paint()..color = Colors.white);
    canvas.drawCircle(handlePos, 4, Paint()..color = activeColor);

    // 5. Radial Ticks
    for (int i = 0; i <= 60; i++) {
      final angle = (i / 60) * sweepAngle + startAngle;
      final tickTemp = (i / 60) * 40;
      final isActive = tickTemp <= actualTemp;
      final tickPaint = Paint()
        ..color = isActive
            ? activeColor
            : (isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1))
        ..strokeWidth = 1.5;
      final innerR = radius - 45;
      final outerR = radius - 30;
      canvas.drawLine(
        Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        ),
        Offset(
          center.dx + outerR * math.cos(angle),
          center.dy + outerR * math.sin(angle),
        ),
        tickPaint,
      );
    }

    // 6. Labels for Ranges
    final labelPoints = [0, 20, 22, 26, 28, 40];
    for (final p in labelPoints) {
      final angle = tempToAngle(p.toDouble());
      final labelR = radius + 15;
      final textPos = Offset(
        center.dx + labelR * math.cos(angle),
        center.dy + labelR * math.sin(angle),
      );

      final textSpan = TextSpan(
        text: '$p',
        style: GoogleFonts.poppins(
          color: Colors.white60,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          textPos.dx - textPainter.width / 2,
          textPos.dy - textPainter.height / 2,
        ),
      );
    }
  }

  Color _getColorForTemp(double temp) {
    if (temp < 20) return const Color(0xFFEF4444);
    if (temp < 22) return const Color(0xFFF59E0B);
    if (temp < 26) return const Color(0xFF10B981);
    if (temp < 28) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  bool shouldRepaint(_ThermostatPainter oldDelegate) =>
      oldDelegate.setTemp != setTemp || oldDelegate.actualTemp != actualTemp;
}

class _ChartData {
  _ChartData(this.time, this.temp);
  final DateTime time;
  final double temp;
}

class _ScheduleArcPainter extends CustomPainter {
  final double startHr;
  final double endHr;
  final bool isDark;

  _ScheduleArcPainter({
    required this.startHr,
    required this.endHr,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const fullStart = math.pi;
    const fullSweep = math.pi;

    // 1. Background Arc (24h)
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, fullStart, fullSweep, false, bgPaint);

    // 2. Active Range Arc
    final activeStart = fullStart + (startHr / 24) * fullSweep;
    final activeSweep = ((endHr - startHr) / 24) * fullSweep;

    final activePaint = Paint()
      ..color = const Color(0xFF6CC042)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = const Color(0xFF6CC042).withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, activeStart, activeSweep, false, glowPaint);
    canvas.drawArc(rect, activeStart, activeSweep, false, activePaint);

    // 3. Labels
    _drawLabel(canvas, '00', center, radius + 15, fullStart);
    _drawLabel(canvas, '12', center, radius + 15, fullStart + fullSweep / 2);
    _drawLabel(canvas, '24', center, radius + 15, fullStart + fullSweep);
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center,
    double r,
    double angle,
  ) {
    final pos = Offset(
      center.dx + r * math.cos(angle),
      center.dy + r * math.sin(angle),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.poppins(
          color: Colors.white24,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ScheduleArcPainter old) =>
      old.startHr != startHr || old.endHr != endHr;
}

// Background parser for chart data to prevent UI thread blocking
List<_ChartData> _parseChartDataInBackground(String responseBody) {
  try {
    final data = jsonDecode(responseBody);
    final List<dynamic> params = data['data']?['parameters'] ?? [];
    List<dynamic> points = [];
    if (params.isNotEmpty) {
      points = params[0]['values'] ?? [];
    }

    int step = 1;
    if (points.length > 150) {
      step = points.length ~/ 150;
    }

    final List<_ChartData> result = [];
    for (int i = 0; i < points.length; i += step) {
      final p = points[i];
      final timeStr = p['time']?.toString() ?? DateTime.now().toString();
      final val = double.tryParse(p['value']?.toString() ?? '0.0') ?? 0.0;
      result.add(_ChartData(DateTime.parse(timeStr).toLocal(), val));
    }
    return result;
  } catch (e) {
    return [];
  }
}

class _TrendsPage extends StatefulWidget {
  final bool isDark;
  final String systemId;
  final String systemName;
  final String systemShortId;
  final String equipmentId;
  final String equipmentName;
  final String equipmentTypeId;
  final String equipmentShortId;
  final String companyId;
  final String siteId;
  final String bucket;

  const _TrendsPage({
    required this.isDark,
    required this.systemId,
    required this.systemName,
    required this.systemShortId,
    required this.equipmentId,
    required this.equipmentName,
    required this.equipmentTypeId,
    required this.equipmentShortId,
    required this.companyId,
    required this.siteId,
    required this.bucket,
  });

  @override
  State<_TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<_TrendsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<dynamic> _parameters = [];
  String? _selectedParamId;
  List<_ChartData> _chartData = [];
  bool _isLoading = true;
  bool _isChartLoading = false;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
    end: DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
  );

  @override
  void initState() {
    super.initState();
    debugPrint(
      '📊 TRENDS OPENED WITH: ID=${widget.equipmentId}, ShortId=${widget.equipmentShortId}, TypeId=${widget.equipmentTypeId}',
    );
    _fetchParameters();
  }

  Future<void> _fetchParameters() async {
    final token = await AuthService.getCookieHeader() ?? '';
    final url =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/systems/parameters/${widget.equipmentTypeId}'
        '?companyId=${widget.companyId}&siteId=${widget.siteId}&bucket=${widget.bucket}';

    debugPrint('📊 FETCH PARAMETERS URL: $url');
    debugPrint('🔑 TOKEN STATUS: ${token.isNotEmpty ? "PRESET" : "MISSING"}');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      debugPrint('📥 RESPONSE STATUS: ${response.statusCode}');
      debugPrint('📦 RESPONSE BODY: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _parameters = data['data'] ?? [];
          if (_parameters.isNotEmpty) {
            // Smart auto-select: Try to find a temperature or status parameter first
            final smartIndex = _parameters.indexWhere((p) {
              final name = p['name']?.toString().toLowerCase() ?? '';
              return name.contains('temp') ||
                  name.contains('status') ||
                  name.contains('on/off');
            });
            _selectedParamId = _parameters[smartIndex != -1 ? smartIndex : 0]
                    ['shortId']
                ?.toString();
            _fetchChartData();
          }
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error fetching parameters: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchChartData() async {
    if (_selectedParamId == null) return;

    setState(() => _isChartLoading = true);
    final token = await AuthService.getCookieHeader() ?? '';

    final startTime = DateTime(
      _dateRange.start.year,
      _dateRange.start.month,
      _dateRange.start.day,
      0,
      0,
      0,
    ).toUtc().toIso8601String();
    final endTime = DateTime(
      _dateRange.end.year,
      _dateRange.end.month,
      _dateRange.end.day,
      23,
      59,
      59,
    ).toUtc().toIso8601String();

    final url =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/parameters/chart-data'
        '?startTime=$startTime&endTime=$endTime'
        '&parameterShortIds=$_selectedParamId'
        '&systemId=${widget.systemId}'
        '&equipmentShortId=${widget.equipmentShortId}'
        '&bucket=${widget.bucket}&companyId=${widget.companyId}&siteId=${widget.siteId}';

    debugPrint('📈 FETCH CHART URL: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      debugPrint('📊 CHART STATUS: ${response.statusCode}');

      if (response.statusCode == 200) {
        final points = _parseChartDataInBackground(response.body);

        if (mounted) {
          setState(() {
            _chartData = points;
            _isChartLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching chart data: $e');
      if (mounted) setState(() => _isChartLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: widget.isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF6CC042),
                    onPrimary: Colors.white,
                    surface: Color(0xFF1B172E),
                    onSurface: Colors.white,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF6CC042),
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dateRange = picked);
      _fetchChartData();
    }
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM dd').format(date);
  }

  IconData _getPickerIcon() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final start = DateTime(
      _dateRange.start.year,
      _dateRange.start.month,
      _dateRange.start.day,
    );
    final end = DateTime(
      _dateRange.end.year,
      _dateRange.end.month,
      _dateRange.end.day,
    );

    if (start == end) {
      if (start == today) return Icons.today_rounded;
      if (start == yesterday) return Icons.history_rounded;
    }
    return Icons.calendar_today_rounded;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = widget.isDark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              'Analytics & Trends',
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.systemName,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF6CC042),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white54 : Colors.black54,
                    size: 12,
                  ),
                ),
                Text(
                  widget.equipmentName,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? _buildFullPageTrendsSkeleton(isDark)
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedParamId,
                              dropdownColor: isDark
                                  ? const Color(0xFF2D264D)
                                  : Colors.white,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF6CC042),
                              ),
                              style: GoogleFonts.poppins(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              items: _parameters
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p['shortId']?.toString(),
                                      child: Text(
                                        p['name']?.toString() ?? 'Unknown',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedParamId = val);
                                  _fetchChartData();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6CC042).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF6CC042).withOpacity(0.3),
                            ),
                          ),
                          child: Icon(
                            _getPickerIcon(),
                            color: const Color(0xFF6CC042),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 300,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: _isChartLoading
                        ? _buildChartSkeleton(isDark)
                        : _chartData.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.query_stats_rounded,
                                      color: Colors.white.withOpacity(0.1),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No Data Available',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white.withOpacity(0.2),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : SfCartesianChart(
                                margin: EdgeInsets.zero,
                                plotAreaBorderWidth: 0,
                                primaryXAxis: DateTimeAxis(
                                  dateFormat: DateFormat('h:mm a'),
                                  majorGridLines:
                                      const MajorGridLines(width: 0),
                                  axisLine: const AxisLine(width: 0),
                                  labelStyle: GoogleFonts.poppins(
                                    color: Colors.white24,
                                    fontSize: 9,
                                  ),
                                ),
                                primaryYAxis: NumericAxis(
                                  majorGridLines: MajorGridLines(
                                    width: 1,
                                    color: Colors.white.withOpacity(0.05),
                                    dashArray: const [5, 5],
                                  ),
                                  axisLine: const AxisLine(width: 0),
                                  labelStyle: GoogleFonts.poppins(
                                    color: Colors.white24,
                                    fontSize: 9,
                                  ),
                                ),
                                series: <CartesianSeries<_ChartData, DateTime>>[
                                  AreaSeries<_ChartData, DateTime>(
                                    dataSource: _chartData,
                                    xValueMapper: (_ChartData data, _) =>
                                        data.time,
                                    yValueMapper: (_ChartData data, _) =>
                                        data.temp,
                                    color: const Color(
                                      0xFFD4145A,
                                    ), // Pink/Magenta from image
                                    borderColor: const Color(0xFFFF2D55),
                                    borderWidth: 2,
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFFD4145A)
                                            .withOpacity(0.4),
                                        const Color(0xFFD4145A)
                                            .withOpacity(0.0),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    animationDuration: 0,
                                  ),
                                ],
                                trackballBehavior: TrackballBehavior(
                                  enable: true,
                                  activationMode: ActivationMode.singleTap,
                                  tooltipSettings: InteractiveTooltip(
                                    enable: true,
                                    format: 'point.x : point.y',
                                    color: const Color(0xFFD4145A),
                                    textStyle: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  const SizedBox(height: 24),
                  TrendsTable(
                    isDark: isDark,
                    systemId: widget.systemId,
                    systemShortId: widget.systemShortId,
                    equipmentShortId: widget.equipmentShortId,
                    companyId: widget.companyId,
                    siteId: widget.siteId,
                    bucket: widget.bucket,
                    dateRange: _dateRange,
                    parameters: _parameters,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(String label, String val, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              val,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullPageTrendsSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // Dropdown Row Skeleton
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Chart Box Skeleton
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: _buildChartSkeleton(isDark),
          ),
          const SizedBox(height: 24),
          // Info Cards Row Skeleton
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              5,
              (index) => Container(
                width: 40,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceControlPage extends StatefulWidget {
  final String equipmentName;
  final double initialTemp;
  final double actualTemp;

  const _DeviceControlPage({
    required this.equipmentName,
    required this.initialTemp,
    required this.actualTemp,
  });

  @override
  State<_DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<_DeviceControlPage> {
  double _setTemp = 0.0;
  double _actualTemp = 0.0;
  double _humidity = 45.0;
  bool _isScheduleEnabled = true;
  bool _isLunchEnabled = true;
  TimeOfDay _scheduleStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _scheduleEndTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _lunchStartTime = const TimeOfDay(hour: 12, minute: 30);
  TimeOfDay _lunchEndTime = const TimeOfDay(hour: 13, minute: 30);

  @override
  void initState() {
    super.initState();
    _setTemp = widget.initialTemp;
    _actualTemp = widget.actualTemp;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = const Color(0xFF6CC042);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Controls - ${widget.equipmentName}',
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Gauge Section
            _InteractiveThermostatGauge(
              setTemp: _setTemp,
              actualTemp: _actualTemp,
              isDark: isDark,
              colorScheme: colorScheme,
              onTempChanged: (newTemp) {
                // Interaction disabled by parent
              },
            ),
            const SizedBox(height: 10),
            // Plus/Minus Buttons below gauge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _circleButton(Icons.remove_rounded, isDark, () {
                  setState(() => _actualTemp = math.max(0, _actualTemp - 0.5));
                }, size: 56),
                const SizedBox(width: 40),
                _circleButton(Icons.add_rounded, isDark, () {
                  setState(() => _actualTemp = math.min(40, _actualTemp + 0.5));
                }, size: 56),
              ],
            ),
            const SizedBox(height: 25),

            // Humidity Control
            _buildControlCard(
              title: 'HUMIDITY',
              value: '${_humidity.toInt()}%',
              icon: Icons.water_drop_rounded,
              color: Colors.blueAccent,
              isDark: isDark,
              onIncrement: () =>
                  setState(() => _humidity = math.min(100, _humidity + 5)),
              onDecrement: () =>
                  setState(() => _humidity = math.max(0, _humidity - 5)),
            ),
            const SizedBox(height: 15),

            // Daily Schedule
            _buildTimeCard(
              title: 'DAILY SCHEDULE',
              startTime: _scheduleStartTime,
              endTime: _scheduleEndTime,
              isEnabled: _isScheduleEnabled,
              color: const Color(0xFFF59E0B),
              isDark: isDark,
              onToggle: (val) => setState(() => _isScheduleEnabled = val),
              onStartTimeTap: () => _selectTime(true, true),
              onEndTimeTap: () => _selectTime(true, false),
            ),
            const SizedBox(height: 15),

            // Lunch Break
            _buildTimeCard(
              title: 'LUNCH BREAK',
              startTime: _lunchStartTime,
              endTime: _lunchEndTime,
              isEnabled: _isLunchEnabled,
              color: primaryColor,
              isDark: isDark,
              onToggle: (val) => setState(() => _isLunchEnabled = val),
              onStartTimeTap: () => _selectTime(false, true),
              onEndTimeTap: () => _selectTime(false, false),
            ),
            const SizedBox(height: 25),

            // SET Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Save to backend if needed
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'SET',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.6), size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  _circleButton(Icons.remove, isDark, onDecrement),
                  const SizedBox(width: 12),
                  _circleButton(Icons.add, isDark, onIncrement),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard({
    required String title,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required bool isEnabled,
    required Color color,
    required bool isDark,
    required ValueChanged<bool> onToggle,
    required VoidCallback onStartTimeTap,
    required VoidCallback onEndTimeTap,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Switch.adaptive(
                value: isEnabled,
                onChanged: onToggle,
                activeColor: color,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timePickerButton(
                  'START',
                  startTime.format(context),
                  isDark,
                  onStartTimeTap,
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: textColor.withOpacity(0.1),
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              Expanded(
                child: _timePickerButton(
                  'END',
                  endTime.format(context),
                  isDark,
                  onEndTimeTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timePickerButton(
      String label, String time, bool isDark, VoidCallback onTap) {
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: textColor.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, bool isDark, VoidCallback onTap,
      {double size = 40}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
          ),
        ),
        child: Icon(icon,
            color: isDark ? Colors.white : Colors.black87, size: size * 0.5),
      ),
    );
  }

  Future<void> _selectTime(bool isSchedule, bool isStart) async {
    final initialTime = isSchedule
        ? (isStart ? _scheduleStartTime : _scheduleEndTime)
        : (isStart ? _lunchStartTime : _lunchEndTime);

    final TimeOfDay? picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (context) => _CustomTimePickerDialog(initialTime: initialTime),
    );

    if (picked != null) {
      setState(() {
        if (isSchedule) {
          if (isStart)
            _scheduleStartTime = picked;
          else
            _scheduleEndTime = picked;
        } else {
          if (isStart)
            _lunchStartTime = picked;
          else
            _lunchEndTime = picked;
        }
      });
    }
  }
}

class _CustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  const _CustomTimePickerDialog({required this.initialTime});

  @override
  State<_CustomTimePickerDialog> createState() =>
      _CustomTimePickerDialogState();
}

class _CustomTimePickerDialogState extends State<_CustomTimePickerDialog> {
  late int _hour;
  late int _minute;
  late String _period;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hourOfPeriod == 0
        ? 12
        : widget.initialTime.hourOfPeriod;
    _minute = widget.initialTime.minute;
    _period = widget.initialTime.period == DayPeriod.am ? 'AM' : 'PM';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFF6CC042);
    final bgColor = isDark ? const Color(0xFF1B172E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.menu, color: textColor.withOpacity(0.6)),
                  onPressed: () {},
                ),
                const Spacer(),
                Text(
                  'Set Time',
                  style: GoogleFonts.poppins(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 30),

            // Analog Clock (Decorative)
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: textColor.withOpacity(0.1), width: 8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Hour Marks
                  for (int i = 1; i <= 12; i++)
                    Transform.rotate(
                      angle: (i * 30) * math.pi / 180,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 2,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          color: textColor.withOpacity(0.2),
                        ),
                      ),
                    ),
                  // Hands (Approximate based on selected time)
                  Transform.rotate(
                    angle: ((_hour % 12 + _minute / 60) * 30) * math.pi / 180,
                    child: Container(
                      width: 4,
                      height: 50,
                      decoration: BoxDecoration(
                        color: textColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      margin: const EdgeInsets.only(bottom: 50),
                    ),
                  ),
                  Transform.rotate(
                    angle: (_minute * 6) * math.pi / 180,
                    child: Container(
                      width: 2,
                      height: 70,
                      decoration: BoxDecoration(
                        color: textColor.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(1),
                      ),
                      margin: const EdgeInsets.only(bottom: 70),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Time Selectors
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _selector(
                  List.generate(12, (i) => (i + 1).toString().padLeft(2, '0')),
                  _hour.toString().padLeft(2, '0'),
                  (val) => setState(() => _hour = int.parse(val!)),
                  isDark,
                ),
                _selector(
                  List.generate(60, (i) => i.toString().padLeft(2, '0')),
                  _minute.toString().padLeft(2, '0'),
                  (val) => setState(() => _minute = int.parse(val!)),
                  isDark,
                ),
                _selector(
                  ['AM', 'PM'],
                  _period,
                  (val) => setState(() => _period = val!),
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Set Time Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  int finalHour = _hour % 12;
                  if (_period == 'PM') finalHour += 12;
                  Navigator.pop(
                      context, TimeOfDay(hour: finalHour, minute: _minute));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(
                      0xFF2D6A74), // Match screenshot's teal-ish color
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  'Set Time',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                    color: textColor.withOpacity(0.5), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selector(List<String> items, String value,
      ValueChanged<String?> onChanged, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<String>(
        value: value,
        items: items
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: onChanged,
        underline: const SizedBox(),
        style: GoogleFonts.poppins(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        icon: Icon(Icons.arrow_drop_down,
            color: isDark ? Colors.white38 : Colors.black38),
        dropdownColor: isDark ? const Color(0xFF2A244D) : Colors.white,
      ),
    );
  }
}

class _InteractiveThermostatGauge extends StatelessWidget {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final ColorScheme colorScheme;
  final ValueChanged<double> onTempChanged;

  const _InteractiveThermostatGauge({
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.colorScheme,
    required this.onTempChanged,
  });

  Color _getColorForTemp(double temp) {
    if (temp < 20) return const Color(0xFFEF4444);
    if (temp < 22) return const Color(0xFFF59E0B);
    if (temp < 26) return const Color(0xFF10B981);
    if (temp < 28) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  void _handlePan(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    double angle = math.atan2(dy, dx);
    if (angle < 0) angle += 2 * math.pi;

    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    double relativeAngle = angle - startAngle;
    if (relativeAngle < 0) relativeAngle += 2 * math.pi;

    if (relativeAngle > sweepAngle) {
      if (relativeAngle > sweepAngle + (2 * math.pi - sweepAngle) / 2) {
        relativeAngle = 0;
      } else {
        relativeAngle = sweepAngle;
      }
    }

    double newTemp = (relativeAngle / sweepAngle) * 40;
    newTemp = newTemp.clamp(16.0, 30.0).roundToDouble();

    onTempChanged(newTemp);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (isDark)
            BoxShadow(
              color: _getColorForTemp(setTemp).withOpacity(0.15),
              blurRadius: 40,
              spreadRadius: 5,
            ),
        ],
      ),
      child: IgnorePointer(
        ignoring: true, // User cannot handle the circle, only plus/minus
        child: CustomPaint(
          size: const Size(320, 320),
          painter: _InteractiveThermostatPainter(
            setTemp: setTemp,
            actualTemp: actualTemp,
            isDark: isDark,
            colorScheme: colorScheme,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SET TEMP',
                  style: GoogleFonts.poppins(
                    color: (isDark ? Colors.white : colorScheme.primary)
                        .withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${setTemp.toInt()}°C',
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : const Color(0xFF1B172E),
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getColorForTemp(actualTemp).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getColorForTemp(actualTemp).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ACTUAL',
                        style: GoogleFonts.poppins(
                          color: _getColorForTemp(actualTemp),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${actualTemp.toStringAsFixed(1)}°C',
                        style: GoogleFonts.poppins(
                          color:
                              isDark ? Colors.white : const Color(0xFF1B172E),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InteractiveThermostatPainter extends CustomPainter {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final ColorScheme colorScheme;

  _InteractiveThermostatPainter({
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.colorScheme,
  });

  Color _getColorForTemp(double temp) {
    if (temp < 20) return const Color(0xFFEF4444);
    if (temp < 22) return const Color(0xFFF59E0B);
    if (temp < 26) return const Color(0xFF10B981);
    if (temp < 28) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    double tempToAngle(double temp) => (temp / 40) * sweepAngle + startAngle;

    final trackRect = Rect.fromCircle(center: center, radius: radius - 15);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    void drawTrackRange(double start, double end, Color color) {
      final sAngle = tempToAngle(start);
      final swAngle = ((end - start) / 40) * sweepAngle;
      trackPaint.color = color.withOpacity(0.15);
      canvas.drawArc(trackRect, sAngle, swAngle, false, trackPaint);
    }

    drawTrackRange(0, 20, const Color(0xFFEF4444));
    drawTrackRange(20, 22, const Color(0xFFFBBF24));
    drawTrackRange(22, 26, const Color(0xFF6CC042));
    drawTrackRange(26, 28, const Color(0xFFFBBF24));
    drawTrackRange(28, 40, const Color(0xFFEF4444));

    final fullTrackPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawCircle(center, radius - 15, fullTrackPaint);

    final dotPoints = [20.0, 22.0, 26.0, 28.0];
    for (final p in dotPoints) {
      final angle = tempToAngle(p);
      final dotPos = Offset(
        center.dx + (radius - 15) * math.cos(angle),
        center.dy + (radius - 15) * math.sin(angle),
      );
      final dotColor = _getColorForTemp(p);
      canvas.drawCircle(
        dotPos,
        4,
        Paint()..color = Colors.black.withOpacity(0.5),
      );
      canvas.drawCircle(dotPos, 3, Paint()..color = dotColor);
    }

    final basePaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.05)
          : colorScheme.primary.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(trackRect, startAngle, sweepAngle, false, basePaint);

    // Active Arc for ACTUAL TEMP
    final activeColor = _getColorForTemp(actualTemp);
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = activeColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..strokeCap = StrokeCap.round;

    final currentSweep = (actualTemp / 40) * sweepAngle;
    canvas.drawArc(trackRect, startAngle, currentSweep, false, glowPaint);
    canvas.drawArc(trackRect, startAngle, currentSweep, false, activePaint);

    // Handle for ACTUAL TEMP
    final handleAngle = currentSweep + startAngle;
    final handlePos = Offset(
      center.dx + (radius - 15) * math.cos(handleAngle),
      center.dy + (radius - 15) * math.sin(handleAngle),
    );

    canvas.drawCircle(
      handlePos,
      12, // Bigger handle for grabbing
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(handlePos, 10, Paint()..color = Colors.white);
    canvas.drawCircle(handlePos, 6, Paint()..color = activeColor);

    // Radial Ticks (Up to ACTUAL TEMP)
    for (int i = 0; i <= 60; i++) {
      final angle = (i / 60) * sweepAngle + startAngle;
      final tickTemp = (i / 60) * 40;
      final isActive = tickTemp <= actualTemp;
      final tickPaint = Paint()
        ..color = isActive
            ? activeColor
            : (isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1))
        ..strokeWidth = 1.5;
      final innerR = radius - 45;
      final outerR = radius - 30;
      canvas.drawLine(
        Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        ),
        Offset(
          center.dx + outerR * math.cos(angle),
          center.dy + outerR * math.sin(angle),
        ),
        tickPaint,
      );
    }

    final labelPoints = [0, 20, 22, 26, 28, 40];
    for (final p in labelPoints) {
      final angle = tempToAngle(p.toDouble());
      final labelR = radius + 15;
      final textPos = Offset(
        center.dx + labelR * math.cos(angle),
        center.dy + labelR * math.sin(angle),
      );

      final textSpan = TextSpan(
        text: '$p',
        style: GoogleFonts.poppins(
          color: Colors.white60,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          textPos.dx - textPainter.width / 2,
          textPos.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveThermostatPainter oldDelegate) {
    return oldDelegate.setTemp != setTemp ||
        oldDelegate.actualTemp != actualTemp ||
        oldDelegate.isDark != isDark;
  }
}

class _ScheduleControlDialog extends StatelessWidget {
  final bool isDark;
  final String initialOn;
  final String initialOff;
  final Function(String type, String time) onCommand;
  final VoidCallback onClear;

  const _ScheduleControlDialog({
    required this.isDark,
    required this.initialOn,
    required this.initialOff,
    required this.onCommand,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1B172E),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
                color: const Color(0xFF6CC042).withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6CC042).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Color(0xFF6CC042),
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text("Daily Schedule",
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              Text("Manage your AC timing",
                  style: GoogleFonts.poppins(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 32),
              _buildTimeRow(context, "START TIME", initialOn, "SCH_ON"),
              const SizedBox(height: 16),
              _buildTimeRow(context, "END TIME", initialOff, "SCH_OFF"),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    onClear();
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    "CLEAR ALL SCHEDULES",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("CLOSE",
                    style: GoogleFonts.poppins(
                        color: Colors.white24,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRow(
      BuildContext context, String label, String current, String type) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
            Text(current,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        ElevatedButton(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
              builder: (context, child) {
                return Theme(
                  data: isDark
                      ? ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF6CC042),
                              onPrimary: Colors.white,
                              surface: Color(0xFF1B172E),
                              onSurface: Colors.white),
                        )
                      : ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(
                              primary: Color(0xFF6CC042))),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              final formatted =
                  "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
              onCommand(type, formatted);
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6CC042).withOpacity(0.1),
            foregroundColor: const Color(0xFF6CC042),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("SET"),
        ),
      ],
    );
  }
}
