import 'dart:async';

import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'nfc_pair.dart';
import 'smart_qr.dart';
import 'toast.dart';

/// 局域网快速配对页:碰一碰(NFC)或扫一扫(二维码),免 PIN。
///
/// 原理:配对载荷(设备地址 + 一次性 tap 令牌 + 证书指纹)经物理通道
/// 传递,物理在场即最强认证,故无需 PIN 核对。窗口 2 分钟,令牌一次性。
class QuickPairPage extends StatefulWidget {
  const QuickPairPage({super.key, required this.engine});
  final LittleLawEngine engine;

  @override
  State<QuickPairPage> createState() => _QuickPairPageState();
}

class _QuickPairPageState extends State<QuickPairPage> {
  String? _payload;
  int _remainSeconds = 0;
  Timer? _countdown;
  String _status = '';
  bool _busy = false;
  bool _nfcAvailable = false;

  @override
  void initState() {
    super.initState();
    NfcPairManager.isAvailable()
        .then((v) => mounted ? setState(() => _nfcAvailable = v) : null);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _setStatus(String s) => setState(() => _status = s);

  /// 展示我的配对码(二维码 + Android 同时开启 NFC 广播)。
  Future<void> _showMyCode() async {
    setState(() => _busy = true);
    try {
      final payload = await NfcPairManager.enableTapToPair(widget.engine);
      setState(() {
        _payload = payload;
        _remainSeconds = 120;
        _status = '配对窗口已开启(2 分钟)。对方扫码或用 NFC 碰本机即可配对';
      });
      _countdown?.cancel();
      _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _remainSeconds--);
        if (_remainSeconds <= 0) {
          t.cancel();
          NfcPairManager.disableTapToPair();
          setState(() {
            _payload = null;
            _status = '配对窗口已关闭';
          });
        }
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 扫对方二维码配对。
  Future<void> _scanToPair() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanPage()),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await widget.engine.pairViaLanOob(result);
      _setStatus(r.accepted
          ? '已与 ${r.peerInfo?.deviceName ?? "对方"} 完成配对'
          : '配对失败: ${r.message}');
      showToast(
        r.accepted ? '已与 ${r.peerInfo?.deviceName ?? "对方"} 完成配对' : '配对失败: ${r.message}',
        type: r.accepted ? ToastType.success : ToastType.error,
      );
    } catch (e) {
      _setStatus('配对失败: $e');
      showToast('配对失败: $e', type: ToastType.error);
    } finally {
      setState(() => _busy = false);
    }
  }

  /// NFC 一碰配对(本机作读卡器,读取对方 HCE 广播)。
  Future<void> _nfcPair() async {
    setState(() {
      _busy = true;
      _status = '请将本机靠近对方手机背部…';
    });
    try {
      final r = await NfcPairManager.readAndPair(widget.engine);
      _setStatus(r.accepted
          ? '已与 ${r.peerInfo?.deviceName ?? "对方"} 完成配对'
          : '配对失败: ${r.message}');
      showToast(
        r.accepted ? '已与 ${r.peerInfo?.deviceName ?? "对方"} 完成配对' : '配对失败: ${r.message}',
        type: r.accepted ? ToastType.success : ToastType.error,
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('碰一碰 / 扫一扫配对')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('免 PIN 快速配对(同一局域网)'),
              subtitle: Text('载荷经物理通道(二维码/NFC)传递并含一次性令牌,'
                  '配对窗口 2 分钟,令牌用后即焚。'),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _showMyCode,
                icon: const Icon(Icons.qr_code),
                label: const Text('展示我的配对码'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _scanToPair,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫对方码配对'),
              ),
              if (_nfcAvailable)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _nfcPair,
                  icon: const Icon(Icons.nfc),
                  label: const Text('NFC 一碰配对'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_status.isNotEmpty)
            Center(
              child: Text(_status,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          if (_payload != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Text('剩余 ${_remainSeconds}s',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Center(
              child: SmartQrView(data: _payload!, size: 260),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text('Android 手机也可直接 NFC 触碰本机背部配对',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ],
      ),
    );
  }
}

class _QrScanPage extends StatelessWidget {
  const _QrScanPage();

  @override
  Widget build(BuildContext context) {
    var done = false;
    return Scaffold(
      appBar: AppBar(title: const Text('扫描对方配对码')),
      body: MobileScanner(
        onDetect: (capture) {
          if (done) return;
          for (final code in capture.barcodes) {
            final raw = code.rawValue;
            if (raw != null && raw.startsWith('LLT1.')) {
              done = true;
              Navigator.of(context).pop(raw);
              return;
            }
          }
        },
      ),
    );
  }
}
