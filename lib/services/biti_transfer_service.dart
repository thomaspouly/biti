import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/biti_profile.dart';
import 'biti_storage.dart';

// ---------------------------------------------------------------------------
// UUIDs GATT partagés (identiques sur les deux téléphones)
// ---------------------------------------------------------------------------

/// Service « BITI-TRANSFER » (advertising + filtre de scan).
const String kBitiTransferServiceUuid = '12345678-1234-1234-1234-123456789abc';

/// Caractéristique : données (write depuis le central, notify depuis le périphérique).
const String kBitiTransferCharacteristicUuid =
    '12345678-1234-1234-1234-111111111111';

/// Caractéristique : accusé de réception (write depuis le central récepteur).
const String kBitiAckCharacteristicUuid =
    '12345678-1234-1234-1234-222222222222';

/// Caractéristique : négociation du rôle (timestamp aléatoire, write).
const String kBitiRoleCharacteristicUuid =
    '12345678-1234-1234-1234-333333333333';

// ---------------------------------------------------------------------------
// États exposés au Bloc / UI
// ---------------------------------------------------------------------------

/// Rôle choisi par l’utilisateur (l’autre téléphone doit choisir le rôle complémentaire).
enum BitiTransferUserRole {
  /// Chercher un appareil en « Accueillir » et envoyer son profil.
  send,

  /// S’annoncer en « Accueillir » et recevoir le profil distant.
  receive,
}

/// Phase courante du transfert BLE.
enum BitiTransferPhase {
  idle,
  searching,
  connecting,
  negotiating,
  sending,
  receiving,
  success,
  error,
}

/// État immuable diffusé sur [BitiTransferService.stateStream].
@immutable
class BitiTransferState {
  const BitiTransferState({
    required this.phase,
    this.message,
    this.chunksDone = 0,
    this.chunksTotal = 0,
    this.receivedProfile,
  });

  const BitiTransferState.idle([this.message])
    : phase = BitiTransferPhase.idle,
      chunksDone = 0,
      chunksTotal = 0,
      receivedProfile = null;

  const BitiTransferState.searching()
    : phase = BitiTransferPhase.searching,
      message = null,
      chunksDone = 0,
      chunksTotal = 0,
      receivedProfile = null;

  const BitiTransferState.connecting()
    : phase = BitiTransferPhase.connecting,
      message = null,
      chunksDone = 0,
      chunksTotal = 0,
      receivedProfile = null;

  const BitiTransferState.negotiating()
    : phase = BitiTransferPhase.negotiating,
      message = null,
      chunksDone = 0,
      chunksTotal = 0,
      receivedProfile = null;

  const BitiTransferState.sending({
    required this.chunksDone,
    required this.chunksTotal,
  }) : phase = BitiTransferPhase.sending,
       message = null,
       receivedProfile = null;

  const BitiTransferState.receiving({
    required this.chunksDone,
    required this.chunksTotal,
  }) : phase = BitiTransferPhase.receiving,
       message = null,
       receivedProfile = null;

  const BitiTransferState.success({this.receivedProfile})
    : phase = BitiTransferPhase.success,
      message = null,
      chunksDone = 0,
      chunksTotal = 0;

  const BitiTransferState.error(this.message)
    : phase = BitiTransferPhase.error,
      chunksDone = 0,
      chunksTotal = 0,
      receivedProfile = null;

  final BitiTransferPhase phase;
  final String? message;
  final int chunksDone;
  final int chunksTotal;
  final BitiProfile? receivedProfile;
}

/// Service BLE : advertising + scan, connexion, négociation, transfert chunké.
class BitiTransferService {
  BitiTransferService()
    : _central = CentralManager(),
      _peripheral = PeripheralManager();

  final CentralManager _central;
  final PeripheralManager _peripheral;
  final StreamController<BitiTransferState> _controller =
      StreamController<BitiTransferState>.broadcast();

  Stream<BitiTransferState> get stateStream => _controller.stream;

  static final UUID _svc = UUID.fromString(kBitiTransferServiceUuid);
  static final UUID _uuidTransfer = UUID.fromString(
    kBitiTransferCharacteristicUuid,
  );
  static final UUID _uuidAck = UUID.fromString(kBitiAckCharacteristicUuid);
  static final UUID _uuidRole = UUID.fromString(kBitiRoleCharacteristicUuid);

  /// Références des caractéristiques locales (pour [notifyCharacteristic]).
  GATTCharacteristic? _localTransfer;
  late GATTCharacteristic? _localAck;
  late GATTCharacteristic? _localRole;

  bool _busy = false;
  bool _disposed = false;
  Timer? _timeout;
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  Peripheral? _remotePeripheral;
  Central? _remoteCentral;

  BitiTransferUserRole? _userRole;

  /// Rôle courant (null hors session). Exposé au bloc pour les libellés UI.
  BitiTransferUserRole? get activeUserRole => _userRole;

  /// iOS / macOS : le [PeripheralManager] Darwin n’expose pas
  /// [PeripheralManager.connectionStateChanged] ; on démarre la session GATT
  /// périphérique au premier [characteristicWriteRequested] d’un central.
  bool _darwinPeripheralBootstrapDone = false;

  GATTCharacteristic? _cTransfer;
  GATTCharacteristic? _cAck;
  GATTCharacteristic? _cRole;

  BitiProfile? _profileToSend;
  Uint8List? _negotiationLocalU64;
  Uint8List? _negotiationPeerU64;

  Completer<void>? _negotiationDone;
  Completer<void>? _ackCompleter;
  Completer<void>? _assemblyCompleter;

  final Map<int, Uint8List> _chunkMap = <int, Uint8List>{};

  /// Permissions + Bluetooth, puis scan GAP uniquement (l’autre doit être en [startReceive]).
  Future<void> startSend(BitiProfile currentProfile) async {
    if (_disposed) return;
    if (_busy) return;
    _userRole = BitiTransferUserRole.send;
    _profileToSend = currentProfile;
    await _cancelSubscriptionsOnly();
    _busy = true;

    try {
      if (!await _transferCommonSetup()) {
        return;
      }

      await _central.startDiscovery(serviceUUIDs: <UUID>[_svc]);
      _emit(const BitiTransferState.searching());

      _timeout?.cancel();
      _timeout = Timer(const Duration(seconds: 30), () {
        if (!_busy) return;
        unawaited(_onTimeout());
      });

      _subs.add(_central.discovered.listen(_onDiscovered));
    } on Object catch (e, st) {
      debugPrint('BitiTransferService.startSend: $e\n$st');
      _emit(BitiTransferState.error('Échec du démarrage : $e'));
      await _cleanupSession();
      _busy = false;
    }
  }

  /// Permissions + Bluetooth, puis annonce GAP uniquement (l’autre doit être en [startSend]).
  Future<void> startReceive() async {
    if (_disposed) return;
    if (_busy) return;
    _userRole = BitiTransferUserRole.receive;
    _profileToSend = null;
    await _cancelSubscriptionsOnly();
    _busy = true;

    try {
      if (!await _transferCommonSetup()) {
        return;
      }

      await _registerGattService();
      await _peripheral.startAdvertising(
        Advertisement(name: 'Biti', serviceUUIDs: <UUID>[_svc]),
      );
      _emit(const BitiTransferState.searching());

      _timeout?.cancel();
      _timeout = Timer(const Duration(seconds: 30), () {
        if (!_busy) return;
        unawaited(_onTimeout());
      });

      _subs.add(
        _peripheral.characteristicWriteRequested.listen(_onPeripheralWrite),
      );
      if (!_isDarwinBle) {
        _subs.add(
          _peripheral.connectionStateChanged.listen(_onPeripheralConnection),
        );
      }
    } on Object catch (e, st) {
      debugPrint('BitiTransferService.startReceive: $e\n$st');
      _emit(BitiTransferState.error('Échec du démarrage : $e'));
      await _cleanupSession();
      _busy = false;
    }
  }

  Future<bool> _transferCommonSetup() async {
    final bool okPerms = await _ensurePermissions();
    if (!okPerms) {
      _emit(
        const BitiTransferState.error(
          'Permissions Bluetooth ou localisation refusées. Ouvrez les réglages pour les activer.',
        ),
      );
      _busy = false;
      return false;
    }

    try {
      await _central.authorize();
      await _peripheral.authorize();
    } on Object {
      // Optionnel selon plateforme.
    }

    if (_central.state != BluetoothLowEnergyState.poweredOn ||
        _peripheral.state != BluetoothLowEnergyState.poweredOn) {
      _emit(
        const BitiTransferState.error(
          'Bluetooth désactivé. Activez le Bluetooth puis réessayez.',
        ),
      );
      _busy = false;
      return false;
    }
    return true;
  }

  Future<void> cancel() async {
    await _cleanupSession();
    if (!_disposed) {
      _emit(const BitiTransferState.idle());
    }
    _busy = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancel();
    await _controller.close();
  }

  static Future<void> openSystemSettings() => openAppSettings();

  // --- Permissions -----------------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    if (kIsWeb) {
      return true;
    }
    // iOS / macOS : Core Location via Geolocator (demande système fiable) ;
    // Bluetooth reste sur permission_handler. Sur iOS, permission_handler peut
    // être compilé sans stratégie Location si les macros du Pod ne sont pas
    // appliquées au pod permission_handler_apple.
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await _requestAppleForegroundLocation();
      await _requestPermissionIfNeeded(Permission.bluetooth);
      final Map<Permission, PermissionStatus> statuses =
          <Permission, PermissionStatus>{
            Permission.locationWhenInUse:
                await Permission.locationWhenInUse.status,
            Permission.bluetooth: await Permission.bluetooth.status,
          };
      return _permissionsAllOk(statuses);
    }

    final List<Permission> ordered = _androidTransferPermissionsOrdered();
    for (final Permission p in ordered) {
      await _requestPermissionIfNeeded(p);
    }
    final Map<Permission, PermissionStatus> statuses =
        <Permission, PermissionStatus>{
          for (final Permission p in ordered) p: await p.status,
        };
    return _permissionsAllOk(statuses);
  }

  /// Localisation « pendant l’utilisation » (Core Location) sur iOS / macOS.
  Future<void> _requestAppleForegroundLocation() async {
    LocationPermission g = await Geolocator.checkPermission();
    debugPrint('LocationPermission: $g');
    if (g == LocationPermission.denied) {
      g = await Geolocator.requestPermission();
    }
  }

  /// Android : runtime 12+ (éviter Permission.bluetooth → manifeste BLUETOOTH).
  List<Permission> _androidTransferPermissionsOrdered() {
    return <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ];
  }

  Future<void> _requestPermissionIfNeeded(Permission permission) async {
    PermissionStatus status = await permission.status;
    if (status.isGranted || status.isLimited) {
      return;
    }
    if (status.isPermanentlyDenied) {
      return;
    }
    status = await permission.request();
    if (status.isGranted || status.isLimited || status.isPermanentlyDenied) {
      return;
    }
    if (status.isDenied) {
      await permission.request();
    }
  }

  bool _permissionsAllOk(Map<Permission, PermissionStatus> statuses) {
    final bool ok = statuses.entries.every(
      (MapEntry<Permission, PermissionStatus> e) =>
          e.value.isGranted || e.value.isLimited,
    );
    if (!ok) {
      for (final MapEntry<Permission, PermissionStatus> e in statuses.entries) {
        if (!e.value.isGranted && !e.value.isLimited) {
          debugPrint(
            'BitiTransfer: permission manquante ou refusée — ${e.key} → ${e.value}',
          );
        }
      }
    }
    return ok;
  }

  // --- GATT local -------------------------------------------------------------------

  Future<void> _registerGattService() async {
    await _peripheral.removeAllServices();

    _localTransfer = GATTCharacteristic.mutable(
      uuid: _uuidTransfer,
      properties: const <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
        GATTCharacteristicProperty.notify,
      ],
      permissions: const <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: const <GATTDescriptor>[],
    );
    _localAck = GATTCharacteristic.mutable(
      uuid: _uuidAck,
      properties: const <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
      ],
      permissions: const <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: const <GATTDescriptor>[],
    );
    _localRole = GATTCharacteristic.mutable(
      uuid: _uuidRole,
      properties: const <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
      ],
      permissions: const <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: const <GATTDescriptor>[],
    );

    final GATTService service = GATTService(
      uuid: _svc,
      isPrimary: true,
      includedServices: const <GATTService>[],
      characteristics: <GATTCharacteristic>[
        _localTransfer!,
        _localAck!,
        _localRole!,
      ],
    );
    await _peripheral.addService(service);
  }

  // --- Découverte (central) ---------------------------------------------------------

  Future<void> _onDiscovered(DiscoveredEventArgs e) async {
    if (_userRole == BitiTransferUserRole.receive) return;
    if (!_busy || _remotePeripheral != null) return;
    try {
      await _central.stopDiscovery();
      _emit(const BitiTransferState.connecting());
      _remotePeripheral = e.peripheral;
      await _central.connect(e.peripheral);
      await _afterConnectedAsCentral();
    } on Object catch (err, st) {
      debugPrint('discovered/connect: $err\n$st');
      _emit(BitiTransferState.error('Connexion impossible : $err'));
      await _cleanupSession();
      _busy = false;
    }
  }

  Future<void> _afterConnectedAsCentral() async {
    await _peripheral.stopAdvertising();
    await _central.stopDiscovery();
    _timeout?.cancel();

    final List<GATTService> services = await _central.discoverGATT(
      _remotePeripheral!,
    );
    final (GATTCharacteristic, GATTCharacteristic, GATTCharacteristic)?
    triplet = _resolveCharacteristics(services);
    if (triplet == null) {
      _emit(
        const BitiTransferState.error(
          'Service Biti introuvable sur l’appareil distant.',
        ),
      );
      await _cleanupSession();
      _busy = false;
      return;
    }
    _cTransfer = triplet.$1;
    _cAck = triplet.$2;
    _cRole = triplet.$3;

    try {
      await _central.requestMTU(_remotePeripheral!, mtu: 512);
    } on Object {
      /* */
    }

    await _central.setCharacteristicNotifyState(
      _remotePeripheral!,
      _cTransfer!,
      state: true,
    );

    _subs.add(
      _central.characteristicNotified.listen((
        GATTCharacteristicNotifiedEventArgs args,
      ) {
        if (args.peripheral != _remotePeripheral) return;
        if (args.characteristic.uuid != _uuidTransfer) return;
        _onCentralTransferNotify(args.value);
      }),
    );

    try {
      await _runCentralSession();
    } on Object catch (e, st) {
      debugPrint('_runCentralSession: $e\n$st');
      _emit(BitiTransferState.error('$e'));
    } finally {
      await _cleanupSession();
      _busy = false;
    }
  }

  // --- Connexion entrante (périphérique) ---------------------------------------------

  bool get _isDarwinBle =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _onPeripheralConnection(
    CentralConnectionStateChangedEventArgs e,
  ) async {
    if (!_busy) return;
    if (e.state == ConnectionState.connected) {
      _remoteCentral ??= e.central;
      if (_remotePeripheral == null) {
        _emit(const BitiTransferState.connecting());
        await _peripheral.stopAdvertising();
        await _central.stopDiscovery();
        _timeout?.cancel();
        try {
          await _runPeripheralSession();
        } on Object catch (err, st) {
          debugPrint('_runPeripheralSession: $err\n$st');
          _emit(BitiTransferState.error('$err'));
        } finally {
          await _cleanupSession();
          _busy = false;
        }
      }
    }
  }

  /// Darwin uniquement : équivalent de [_onPeripheralConnection] après le
  /// premier write GATT (pas de flux `connectionStateChanged` côté périphérique).
  Future<void> _darwinPeripheralAfterFirstContact() async {
    try {
      await _peripheral.stopAdvertising();
      await _central.stopDiscovery();
      _timeout?.cancel();
    } on Object catch (e, st) {
      debugPrint('BitiTransfer Darwin stopAdv/discovery: $e\n$st');
    }
    try {
      await _awaitPeripheralNegotiationAndExchange();
    } on Object catch (err, st) {
      debugPrint('_awaitPeripheralNegotiationAndExchange: $err\n$st');
      _emit(BitiTransferState.error('$err'));
    } finally {
      await _cleanupSession();
      _busy = false;
    }
  }

  // --- Écritures GATT côté périphérique ----------------------------------------------

  Future<void> _onPeripheralWrite(
    GATTCharacteristicWriteRequestedEventArgs e,
  ) async {
    if (_userRole == BitiTransferUserRole.receive &&
        _isDarwinBle &&
        _busy &&
        _remotePeripheral == null &&
        !_darwinPeripheralBootstrapDone) {
      _darwinPeripheralBootstrapDone = true;
      _remoteCentral = e.central;
      _emit(const BitiTransferState.connecting());
      _beginPeripheralNegotiationPhase();
      unawaited(_darwinPeripheralAfterFirstContact());
    }
    try {
      if (e.characteristic.uuid == _uuidRole) {
        await _onRoleWriteFromCentral(e);
      } else if (e.characteristic.uuid == _uuidTransfer) {
        await _onTransferWriteFromCentral(e);
      } else if (e.characteristic.uuid == _uuidAck) {
        if (!(_ackCompleter?.isCompleted ?? true)) {
          _ackCompleter?.complete();
        }
        await _peripheral.respondWriteRequest(e.request);
      } else {
        await _peripheral.respondWriteRequest(e.request);
      }
    } on Object catch (err) {
      await _peripheral.respondWriteRequestWithError(
        e.request,
        error: GATTError.writeNotPermitted,
      );
      debugPrint('peripheral write: $err');
    }
  }

  Future<void> _onRoleWriteFromCentral(
    GATTCharacteristicWriteRequestedEventArgs e,
  ) async {
    final Uint8List v = e.request.value;
    await _peripheral.respondWriteRequest(e.request);
    if (v.length < 8) return;
    _negotiationPeerU64 = Uint8List.sublistView(v, 0, 8);
    final Uint8List local = _negotiationLocalU64 ?? _randomU64();
    _negotiationLocalU64 = local;
    final Uint8List out = Uint8List(9)..[0] = 0x01;
    out.setRange(1, 9, local);
    if (_remoteCentral != null && _localTransfer != null) {
      await _peripheral.notifyCharacteristic(
        _remoteCentral!,
        _localTransfer!,
        value: out,
      );
    }
    if (!(_negotiationDone?.isCompleted ?? true)) {
      _negotiationDone?.complete();
    }
  }

  Future<void> _onTransferWriteFromCentral(
    GATTCharacteristicWriteRequestedEventArgs e,
  ) async {
    final Uint8List v = e.request.value;
    await _peripheral.respondWriteRequest(e.request);
    if (v.isEmpty) return;
    if (v[0] == 0x11 && v.length >= 7) {
      _chunkMap.clear();
      return;
    }
    if (v[0] == 0x10 && v.length >= 6) {
      final ByteData bd = ByteData.sublistView(v, 0, 6);
      final int idx = bd.getUint16(1);
      final int total = bd.getUint16(3);
      final Uint8List payload = Uint8List.sublistView(v, 5);
      _chunkMap[idx] = payload;
      _emit(
        BitiTransferState.receiving(
          chunksDone: _chunkMap.length,
          chunksTotal: total,
        ),
      );
      if (_chunkMap.length == total) {
        if (!(_assemblyCompleter?.isCompleted ?? true)) {
          _assemblyCompleter?.complete();
        }
      }
    }
  }

  void _onCentralTransferNotify(Uint8List value) {
    if (value.isEmpty) return;
    final int tag = value[0];
    if (tag == 0x01 && value.length >= 9) {
      _negotiationPeerU64 = Uint8List.sublistView(value, 1, 9);
      if (!(_negotiationDone?.isCompleted ?? true)) {
        _negotiationDone?.complete();
      }
      return;
    }
    if (tag == 0xFF) {
      if (!(_ackCompleter?.isCompleted ?? true)) {
        _ackCompleter?.complete();
      }
      return;
    }
    if (tag == 0x11 && value.length >= 7) {
      _chunkMap.clear();
      return;
    }
    if (tag == 0x10 && value.length >= 6) {
      final ByteData bd = ByteData.sublistView(value, 0, 6);
      final int idx = bd.getUint16(1);
      final int total = bd.getUint16(3);
      final Uint8List payload = Uint8List.sublistView(value, 5);
      _chunkMap[idx] = payload;
      _emit(
        BitiTransferState.receiving(
          chunksDone: _chunkMap.length,
          chunksTotal: total,
        ),
      );
      if (_chunkMap.length == total) {
        if (!(_assemblyCompleter?.isCompleted ?? true)) {
          _assemblyCompleter?.complete();
        }
      }
    }
  }

  // --- Sessions ---------------------------------------------------------------------

  /// Nous avons initié la connexion (GAP central).
  Future<void> _runCentralSession() async {
    _negotiationLocalU64 = _randomU64();
    _negotiationPeerU64 = null;
    _emit(const BitiTransferState.negotiating());
    _negotiationDone = Completer<void>();

    await _writeWithRetries(
      () => _central.writeCharacteristic(
        _remotePeripheral!,
        _cRole!,
        value: _negotiationLocalU64!,
        type: GATTCharacteristicWriteType.withResponse,
      ),
    );

    await _negotiationDone!.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('Négociation'),
    );

    await _exchangePayloadAfterNegotiation(isCentralInitiator: true);
  }

  void _beginPeripheralNegotiationPhase() {
    _negotiationLocalU64 = _randomU64();
    _negotiationPeerU64 = null;
    _emit(const BitiTransferState.negotiating());
    _negotiationDone = Completer<void>();
  }

  Future<void> _awaitPeripheralNegotiationAndExchange() async {
    await _negotiationDone!.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('Négociation'),
    );
    await _exchangePayloadAfterNegotiation(isCentralInitiator: false);
  }

  /// Un central distant s’est connecté à notre GATT (GAP périphérique).
  Future<void> _runPeripheralSession() async {
    _beginPeripheralNegotiationPhase();
    await _awaitPeripheralNegotiationAndExchange();
  }

  /// Compare les timestamps : le plus petit (unsigned) devient émetteur.
  Future<void> _exchangePayloadAfterNegotiation({
    required bool isCentralInitiator,
  }) async {
    final Uint8List a = _negotiationLocalU64!;
    final Uint8List? b = _negotiationPeerU64;
    if (b == null || b.length < 8) {
      throw StateError('Négociation incomplète');
    }
    final int cmp = _compareU64(a, b);
    final bool iAmEmitter;
    if (_userRole == BitiTransferUserRole.send) {
      iAmEmitter = true;
    } else if (_userRole == BitiTransferUserRole.receive) {
      iAmEmitter = false;
    } else {
      iAmEmitter =
          cmp < 0 ||
          (cmp == 0 && isCentralInitiator); // égalité : l’initiateur envoie
    }

    if (iAmEmitter) {
      await _sendJsonPayload(isCentral: isCentralInitiator);
      await _waitForAck(isCentralEmitter: isCentralInitiator);
      await BitiStorage.removeProfileById(_profileToSend!.id);
      _emit(const BitiTransferState.success());
    } else {
      await _receiveJsonPayload(isCentral: isCentralInitiator);
      final Uint8List jsonBytes = _mergeChunks();
      final BitiProfile received = BitiProfile.fromJson(
        jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>,
      );
      await BitiStorage.appendReceivedProfile(received);
      await _sendAck(isCentralReceiver: isCentralInitiator);
      _emit(BitiTransferState.success(receivedProfile: received));
    }
  }

  static const int _kMaxPayload = 507; // 512 - en-tête 5 octets pour 0x10

  Future<void> _sendJsonPayload({required bool isCentral}) async {
    final Uint8List json = Uint8List.fromList(
      utf8.encode(jsonEncode(_profileToSend!.toJson())),
    );
    final int total = (json.length / _kMaxPayload).ceil();
    final Uint8List meta = Uint8List(8);
    meta[0] = 0x11;
    final ByteData m = ByteData.sublistView(meta);
    m.setUint32(1, json.length);
    m.setUint16(5, total);

    await _emitFrame(meta, isCentral: isCentral);
    for (int i = 0; i < total; i++) {
      final int start = i * _kMaxPayload;
      final int end = min(start + _kMaxPayload, json.length);
      final Uint8List piece = Uint8List.sublistView(json, start, end);
      final Uint8List frame = Uint8List(5 + piece.length);
      frame[0] = 0x10;
      final ByteData h = ByteData.sublistView(frame, 0, 5);
      h.setUint16(1, i);
      h.setUint16(3, total);
      frame.setRange(5, frame.length, piece);
      await _emitFrame(frame, isCentral: isCentral);
      _emit(BitiTransferState.sending(chunksDone: i + 1, chunksTotal: total));
    }
  }

  Future<void> _emitFrame(Uint8List frame, {required bool isCentral}) async {
    if (isCentral) {
      await _writeWithRetries(
        () => _central.writeCharacteristic(
          _remotePeripheral!,
          _cTransfer!,
          value: frame,
          type: GATTCharacteristicWriteType.withResponse,
        ),
      );
    } else {
      await _writeWithRetries(
        () => _peripheral.notifyCharacteristic(
          _remoteCentral!,
          _localTransfer!,
          value: frame,
        ),
      );
    }
  }

  Future<void> _receiveJsonPayload({required bool isCentral}) async {
    _chunkMap.clear();
    _assemblyCompleter = Completer<void>();
    await _assemblyCompleter!.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException('Réception incomplète'),
    );
  }

  Uint8List _mergeChunks() {
    final List<int> keys = _chunkMap.keys.toList()..sort();
    final BytesBuilder bb = BytesBuilder(copy: false);
    for (final int k in keys) {
      bb.add(_chunkMap[k]!);
    }
    return bb.takeBytes();
  }

  Future<void> _waitForAck({required bool isCentralEmitter}) async {
    _ackCompleter = Completer<void>();
    await _ackCompleter!.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException('ACK manquant'),
    );
  }

  Future<void> _sendAck({required bool isCentralReceiver}) async {
    final Uint8List ack = Uint8List.fromList(<int>[0xFF]);
    if (isCentralReceiver) {
      await _writeWithRetries(
        () => _central.writeCharacteristic(
          _remotePeripheral!,
          _cAck!,
          value: ack,
          type: GATTCharacteristicWriteType.withResponse,
        ),
      );
    } else {
      await _writeWithRetries(
        () => _peripheral.notifyCharacteristic(
          _remoteCentral!,
          _localTransfer!,
          value: ack,
        ),
      );
    }
  }

  Future<void> _writeWithRetries(Future<void> Function() op) async {
    Object? last;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await op();
        return;
      } on Object catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 90 * (attempt + 1)));
      }
    }
    throw last ?? StateError('Écriture BLE');
  }

  Future<void> _onTimeout() async {
    if (!_busy) return;
    if (_userRole == BitiTransferUserRole.receive) {
      _emit(
        const BitiTransferState.error(
          'Aucun envoi reçu. L’autre téléphone doit choisir « Envoyer » et être à proximité.',
        ),
      );
    } else {
      _emit(
        const BitiTransferState.error(
          'Aucun Biti trouvé. L’autre téléphone doit choisir « Accueillir » et être à proximité.',
        ),
      );
    }
    await _cleanupSession();
    _busy = false;
  }

  Future<void> _cancelSubscriptionsOnly() async {
    for (final StreamSubscription<dynamic> s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  Future<void> _cleanupSession() async {
    _timeout?.cancel();
    _timeout = null;
    await _cancelSubscriptionsOnly();
    try {
      await _central.stopDiscovery();
    } on Object {
      /* */
    }
    try {
      await _peripheral.stopAdvertising();
    } on Object {
      /* */
    }
    if (_remotePeripheral != null) {
      try {
        await _central.disconnect(_remotePeripheral!);
      } on Object {
        /* */
      }
    }
    if (_remoteCentral != null) {
      try {
        await _peripheral.disconnect(_remoteCentral!);
      } on Object {
        /* Darwin : disconnect périphérique non supporté. */
      }
    }
    _remotePeripheral = null;
    _remoteCentral = null;
    _darwinPeripheralBootstrapDone = false;
    _userRole = null;
    _cTransfer = null;
    _cAck = null;
    _cRole = null;
    _chunkMap.clear();
    _negotiationDone = null;
    _ackCompleter = null;
    _assemblyCompleter = null;
    _negotiationPeerU64 = null;
    _negotiationLocalU64 = null;
  }

  void _emit(BitiTransferState s) {
    if (!_controller.isClosed) {
      _controller.add(s);
    }
  }

  (GATTCharacteristic, GATTCharacteristic, GATTCharacteristic)?
  _resolveCharacteristics(List<GATTService> services) {
    for (final GATTService s in services) {
      if (s.uuid != _svc) continue;
      GATTCharacteristic? t, a, r;
      for (final GATTCharacteristic c in s.characteristics) {
        if (c.uuid == _uuidTransfer) t = c;
        if (c.uuid == _uuidAck) a = c;
        if (c.uuid == _uuidRole) r = c;
      }
      if (t != null && a != null && r != null) {
        return (t, a, r);
      }
    }
    return null;
  }

  static Uint8List _randomU64() {
    final Random rng = Random.secure();
    final Uint8List out = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  static int _compareU64(Uint8List a, Uint8List b) {
    for (int i = 0; i < 8; i++) {
      final int d = a[i] - b[i];
      if (d != 0) return d;
    }
    return 0;
  }
}
