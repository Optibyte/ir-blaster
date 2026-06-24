import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';

class ACControlPage extends StatefulWidget {
  const ACControlPage({super.key});
  @override
  State<ACControlPage> createState() => _ACControlPageState();
}

class _ACControlPageState extends State<ACControlPage>
    with SingleTickerProviderStateMixin {
  final MqttService _mqtt = MqttService();
  late AnimationController _pulseCtrl;

  // Local UI state (updated from MQTT snapshots)
  bool _isConnected = false;
  bool _isActive = false;
  bool _isPowerOn = false;
  int _setTemp = 24;
  int _currentTemp = 0;
  int _humidity = 0;
  bool _irOnLearned = true;
  bool _irOffLearned = true;

  // Schedules
  String _schOn1 = 'DISABLED', _schOff1 = 'DISABLED';
  String _schOn2 = 'DISABLED', _schOff2 = 'DISABLED';
  String _schOn3 = 'DISABLED', _schOff3 = 'DISABLED';
  String _schOn4 = 'DISABLED', _schOff4 = 'DISABLED';
  String _schOn5 = 'DISABLED', _schOff5 = 'DISABLED';
  String _lunchOn = 'DISABLED', _lunchOff = 'DISABLED';

  // Pending command feedback
  bool _pendingPower = false;
  bool _pendingTemp = false;

  StreamSubscription? _stateSub;
  StreamSubscription? _responseSub;
  StreamSubscription? _connSub;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _stateSub = _mqtt.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isActive = state.isActive;
        _isPowerOn = state.isPowerOn;
        if (!_pendingTemp) _setTemp = state.setTemp;
        _currentTemp = state.currentTemp;
        _humidity = state.humidity;
        _irOnLearned = state.irOnLearned;
        _irOffLearned = state.irOffLearned;
        _schOn1 = state.schOn1; _schOff1 = state.schOff1;
        _schOn2 = state.schOn2; _schOff2 = state.schOff2;
        _schOn3 = state.schOn3; _schOff3 = state.schOff3;
        _schOn4 = state.schOn4; _schOff4 = state.schOff4;
        _schOn5 = state.schOn5; _schOff5 = state.schOff5;
        _lunchOn = state.lunchOn; _lunchOff = state.lunchOff;
        _pendingPower = false;
      });
    });

    _responseSub = _mqtt.responseStream.listen((resp) {
      if (!mounted) return;
      if (resp.type == SirisResponseType.acOnDone) {
        setState(() { _isPowerOn = true; _pendingPower = false; });
        _showSnack('AC turned ON', Colors.green);
      } else if (resp.type == SirisResponseType.acOffDone) {
        setState(() { _isPowerOn = false; _pendingPower = false; });
        _showSnack('AC turned OFF', Colors.redAccent);
      } else if (resp.type == SirisResponseType.tempSet) {
        setState(() => _pendingTemp = false);
        _showSnack('Temperature set to ${resp.detail ?? _setTemp}°C', Colors.blue);
      } else if (resp.type == SirisResponseType.tempError) {
        setState(() => _pendingTemp = false);
        _showSnack('Temperature error: ${resp.detail}', Colors.red);
      } else if (resp.type == SirisResponseType.scheduleSet) {
        _showSnack('Schedule updated', Colors.amber);
      } else if (resp.type == SirisResponseType.scheduleCleared) {
        _showSnack('Schedule cleared', Colors.orange);
      } else if (resp.type == SirisResponseType.scheduleError) {
        _showSnack('Schedule error: ${resp.detail}', Colors.red);
      } else if (resp.type == SirisResponseType.cmdRejected) {
        _showSnack('Command rejected: device not active', Colors.red);
      } else if (resp.type == SirisResponseType.cmdError) {
        _showSnack('Command error: ${resp.detail}', Colors.red);
      }
    });

    final connected = await _mqtt.connect();
    if (mounted) setState(() => _isConnected = connected);
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _responseSub?.cancel();
    _connSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── MQTT Actions (RULE 7: only on explicit user action) ───────────────

  void _togglePower() {
    if (!_isActive) { _showSnack('Device is INACTIVE', Colors.red); return; }
    if (!_irOnLearned || !_irOffLearned) {
      _showSnack('IR signals not learned on device', Colors.orange); return;
    }
    setState(() => _pendingPower = true);
    if (_isPowerOn) { _mqtt.turnAcOff(); } else { _mqtt.turnAcOn(); }
  }

  void _incrementTemp() {
    if (!_isActive) return;
    if (_setTemp >= 30) return;
    setState(() { _setTemp++; _pendingTemp = true; });
    _mqtt.setTemperature(_setTemp);
  }

  void _decrementTemp() {
    if (!_isActive) return;
    if (_setTemp <= 16) return;
    setState(() { _setTemp--; _pendingTemp = true; });
    _mqtt.setTemperature(_setTemp);
  }

  Future<void> _pickScheduleTime(int slot, bool isOn) async {
    if (!_isActive) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6CC042), surface: Color(0xFF131122),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF131122),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    if (isOn) { _mqtt.setScheduleOn(slot, time); }
    else { _mqtt.setScheduleOff(slot, time); }
  }

  Future<void> _pickLunchTime(bool isOn) async {
    if (!_isActive) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6CC042), surface: Color(0xFF131122),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF131122),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    if (isOn) { _mqtt.setLunchOn(time); } else { _mqtt.setLunchOff(time); }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = const Color(0xFF6CC042);
    final accent = const Color(0xFF0EA5E9);
    final card = isDark ? const Color(0xFF2A244D) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1B172E);
    final dim = text.withOpacity(0.4);
    final border = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header + Connection Status ─────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CONTROL PANEL', style: GoogleFonts.poppins(
              color: dim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text('AC Remote', style: GoogleFonts.poppins(
              color: text, fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
          Column(children: [
            _connectionBadge(primary, text, isDark),
            const SizedBox(height: 6),
            _statusBadge(primary),
          ]),
        ]),

        // ── IR Warning ────────────────────────────────────────────────
        if (!_irOnLearned || !_irOffLearned) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'IR signals not learned. AC commands may not work.',
                style: GoogleFonts.poppins(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
              )),
            ]),
          ),
        ],

        const SizedBox(height: 24),

        // ── Temperature Circle ────────────────────────────────────────
        Center(child: _buildTempCircle(primary, text, isDark)),

        const SizedBox(height: 32),

        // ── Power Button ──────────────────────────────────────────────
        Center(child: _buildPowerButton(primary, isDark)),

        const SizedBox(height: 32),

        // ── Target Temp + Humidity Row ─────────────────────────────────
        Row(children: [
          Expanded(child: _buildTempControl(accent, card, text, border)),
          const SizedBox(width: 16),
          Expanded(child: _buildHumidityCard(card, text, border)),
        ]),

        const SizedBox(height: 24),

        // ── Schedule Section ──────────────────────────────────────────
        _buildScheduleSection(card, text, border, primary, dim),
      ]),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────

  Widget _connectionBadge(Color primary, Color text, bool isDark) {
    final connected = _isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (connected ? primary : Colors.red).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          color: connected ? primary : Colors.red, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(connected ? 'MQTT' : 'OFFLINE',
          style: GoogleFonts.poppins(
            color: connected ? primary : Colors.red,
            fontSize: 9, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _statusBadge(Color primary) {
    final active = _isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (active ? primary : Colors.grey).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(active ? 'ACTIVE' : 'INACTIVE',
        style: GoogleFonts.poppins(
          color: active ? primary : Colors.grey,
          fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildTempCircle(Color primary, Color text, bool isDark) {
    final color = _isPowerOn ? primary : Colors.grey;
    return Container(
      width: 240, height: 240,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? const Color(0xFF2A244D).withOpacity(0.5) : Colors.white,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.12), blurRadius: 40, spreadRadius: 8),
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03), width: 2),
      ),
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(width: 200, height: 200, child: CircularProgressIndicator(
          value: _currentTemp / 50,
          strokeWidth: 10, strokeCap: StrokeCap.round,
          backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        )),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('CURRENT', style: GoogleFonts.poppins(
            color: text.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_currentTemp', style: GoogleFonts.poppins(
              color: text, fontSize: 56, fontWeight: FontWeight.w900, height: 1)),
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text('°C', style: GoogleFonts.poppins(color: color, fontSize: 20, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(_isPowerOn ? 'RUNNING' : 'OFF',
                style: GoogleFonts.poppins(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _buildPowerButton(Color primary, bool isDark) {
    final color = _isPowerOn ? primary : Colors.redAccent;
    return GestureDetector(
      onTap: _isActive ? _togglePower : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isActive ? color.withOpacity(0.15) : Colors.grey.withOpacity(0.1),
          border: Border.all(color: _isActive ? color : Colors.grey, width: 2.5),
          boxShadow: _isActive ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 16)] : [],
        ),
        child: _pendingPower
            ? const Padding(padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(Icons.power_settings_new_rounded,
                color: _isActive ? color : Colors.grey, size: 32),
      ),
    );
  }

  Widget _buildTempControl(Color accent, Color card, Color text, Color border) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.thermostat_rounded, color: accent.withOpacity(0.6), size: 18),
          const SizedBox(width: 8),
          Text('TARGET TEMP', style: GoogleFonts.poppins(
            color: text.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Text('$_setTemp°C', style: GoogleFonts.poppins(
          color: text, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _circleBtn(Icons.remove, () => _decrementTemp(), text),
          _circleBtn(Icons.add, () => _incrementTemp(), text),
        ]),
      ]),
    );
  }

  Widget _buildHumidityCard(Color card, Color text, Color border) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.water_drop_rounded, color: Colors.indigoAccent.withOpacity(0.6), size: 18),
          const SizedBox(width: 8),
          Text('HUMIDITY', style: GoogleFonts.poppins(
            color: text.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Text('$_humidity%', style: GoogleFonts.poppins(
          color: text, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Text('Live reading', style: GoogleFonts.poppins(
          color: text.withOpacity(0.3), fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildScheduleSection(Color card, Color text, Color border, Color primary, Color dim) {
    final slots = [
      _SlotData(1, _schOn1, _schOff1),
      _SlotData(2, _schOn2, _schOff2),
      _SlotData(3, _schOn3, _schOff3),
      _SlotData(4, _schOn4, _schOff4),
      _SlotData(5, _schOn5, _schOff5),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('SCHEDULES', style: GoogleFonts.poppins(
          color: dim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        GestureDetector(
          onTap: _isActive ? () { _mqtt.clearAllSchedules(); _showSnack('Clearing all schedules...', Colors.orange); } : null,
          child: Text('Clear All', style: GoogleFonts.poppins(
            color: _isActive ? Colors.redAccent : Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 12),

      // Slot cards
      ...slots.map((s) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildSlotCard(s, card, text, border, primary),
      )),

      // Lunch slot
      const SizedBox(height: 8),
      Text('LUNCH BREAK', style: GoogleFonts.poppins(
        color: dim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 12),
      _buildLunchCard(card, text, border, primary),
    ]);
  }

  Widget _buildSlotCard(_SlotData s, Color card, Color text, Color border, Color primary) {
    final isEnabled = s.on != 'DISABLED' || s.off != 'DISABLED';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isEnabled ? primary.withOpacity(0.3) : border),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: (isEnabled ? primary : Colors.grey).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text('${s.slot}', style: GoogleFonts.poppins(
            color: isEnabled ? primary : Colors.grey, fontSize: 14, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Slot ${s.slot}', style: GoogleFonts.poppins(
            color: text, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(children: [
            _timeChip('ON', s.on, Colors.green, () => _pickScheduleTime(s.slot, true)),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: text.withOpacity(0.15), size: 14),
            const SizedBox(width: 8),
            _timeChip('OFF', s.off, Colors.redAccent, () => _pickScheduleTime(s.slot, false)),
          ]),
        ])),
        if (isEnabled)
          GestureDetector(
            onTap: _isActive ? () { _mqtt.clearScheduleSlot(s.slot); } : null,
            child: Icon(Icons.close_rounded, color: Colors.red.withOpacity(0.5), size: 18),
          ),
      ]),
    );
  }

  Widget _buildLunchCard(Color card, Color text, Color border, Color primary) {
    final isEnabled = _lunchOn != 'DISABLED' || _lunchOff != 'DISABLED';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isEnabled ? Colors.amber.withOpacity(0.3) : border),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.restaurant_rounded, color: Colors.amber, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Lunch Break', style: GoogleFonts.poppins(
            color: text, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(children: [
            _timeChip('ON', _lunchOn, Colors.green, () => _pickLunchTime(true)),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: text.withOpacity(0.15), size: 14),
            const SizedBox(width: 8),
            _timeChip('OFF', _lunchOff, Colors.redAccent, () => _pickLunchTime(false)),
          ]),
        ])),
        if (isEnabled)
          GestureDetector(
            onTap: _isActive ? () { _mqtt.clearLunchSlot(); } : null,
            child: Icon(Icons.close_rounded, color: Colors.red.withOpacity(0.5), size: 18),
          ),
      ]),
    );
  }

  Widget _timeChip(String label, String time, Color color, VoidCallback onTap) {
    final display = time == 'DISABLED' ? '--:--' : time;
    return GestureDetector(
      onTap: _isActive ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label ', style: GoogleFonts.poppins(
            color: color.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w700)),
          Text(display, style: GoogleFonts.poppins(
            color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, Color text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _isActive ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _isActive ? (isDark ? Colors.white70 : Colors.black87) : Colors.grey, size: 20),
      ),
    );
  }
}

class _SlotData {
  final int slot;
  final String on;
  final String off;
  _SlotData(this.slot, this.on, this.off);
}
