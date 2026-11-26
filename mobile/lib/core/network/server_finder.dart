import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Progress of a search: how many addresses have been tried out of [total].
typedef FindProgress = void Function(int done, int total);

/// Looks for the NeuroSense server on the phone's Wi-Fi. Returns the server's
/// host (for example "192.168.1.178"), or null when none answered.
typedef ServerFinder = Future<String?> Function(FindProgress onProgress);

/// Overridden in tests so no real network is touched.
final serverFinderProvider = Provider<ServerFinder>((ref) => findServerOnWifi);

/// True when this device can search its network (not in a browser).
bool get canFindServer => !kIsWeb;

/// The phone's private IPv4 networks, as "a.b.c" prefixes of a /24.
Future<List<String>> localPrefixes() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
  final prefixes = <String>{};
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (isPrivateIpv4(address.address)) {
        prefixes.add(address.address.substring(0, address.address.lastIndexOf('.')));
      }
    }
  }
  return prefixes.toList();
}

/// 10.x, 172.16–31.x and 192.168.x: the ranges home and campus Wi-Fi use.
bool isPrivateIpv4(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// True when [body] is what NeuroSense's /health returns ({"status":"ok","model":…}),
/// so another device that happens to use port 8000 is not mistaken for it.
bool looksLikeNeuroSense(Object? body) => body is Map && body['status'] == 'ok' && body.containsKey('model');

/// Tries every address of each prefix (x.x.x.1 to .254) and returns the first
/// host whose [probe] succeeds. Runs [parallel] probes at a time.
Future<String?> scanHosts(
  List<String> prefixes,
  Future<bool> Function(String host) probe, {
  FindProgress? onProgress,
  int parallel = 48,
}) async {
  final hosts = [for (final p in prefixes) for (var i = 1; i <= 254; i++) '$p.$i'];
  var next = 0, done = 0;
  String? found;
  Future<void> worker() async {
    while (found == null && next < hosts.length) {
      final host = hosts[next++];
      bool ok;
      try {
        ok = await probe(host);
      } catch (_) {
        ok = false;
      }
      if (ok) found ??= host;
      onProgress?.call(++done, hosts.length);
    }
  }

  await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
  return found;
}

/// The real search: the phone's Wi-Fi network(s), port 8000, GET /health.
Future<String?> findServerOnWifi(FindProgress onProgress) async {
  if (!canFindServer) return null;
  final prefixes = await localPrefixes();
  if (prefixes.isEmpty) return null;
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 900),
    receiveTimeout: const Duration(milliseconds: 900),
    responseType: ResponseType.json,
  ));
  try {
    return await scanHosts(prefixes, (host) async {
      final response = await dio.get<Object?>('http://$host:8000/health');
      return looksLikeNeuroSense(response.data);
    }, onProgress: onProgress);
  } finally {
    dio.close(force: true);
  }
}
