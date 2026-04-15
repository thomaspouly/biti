import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/biti_profile.dart';
import '../services/biti_transfer_service.dart';

// ---------------------------------------------------------------------------
// Événements
// ---------------------------------------------------------------------------

sealed class BitiTransferBlocEvent {
  const BitiTransferBlocEvent();
}

/// Lance un envoi : scan GAP (l’autre appareil doit être en « Accueillir »).
@immutable
final class BitiTransferSendStarted extends BitiTransferBlocEvent {
  const BitiTransferSendStarted(this.profile) : super();
  final BitiProfile profile;
}

/// Lance une réception : annonce GAP (l’autre doit être en « Envoyer »).
@immutable
final class BitiTransferReceiveStarted extends BitiTransferBlocEvent {
  const BitiTransferReceiveStarted() : super();
}

/// Annule scan / connexion / transfert en cours.
@immutable
final class BitiTransferCancelled extends BitiTransferBlocEvent {
  const BitiTransferCancelled() : super();
}

@immutable
final class _BitiTransferServiceStateSync extends BitiTransferBlocEvent {
  const _BitiTransferServiceStateSync(this.state) : super();
  final BitiTransferState state;
}

// ---------------------------------------------------------------------------
// État du Bloc (miroir du service + profil reçu pour l’intégration app)
// ---------------------------------------------------------------------------

@immutable
class BitiTransferBlocState {
  const BitiTransferBlocState({
    required this.phase,
    this.message,
    this.chunksDone = 0,
    this.chunksTotal = 0,
    this.receivedProfile,
    this.transferRole,
  });

  const BitiTransferBlocState.initial()
    : phase = BitiTransferPhase.idle,
      message = null,
      chunksDone = 0,
      chunksTotal = 0,
      receivedProfile = null,
      transferRole = null;

  final BitiTransferPhase phase;
  final String? message;
  final int chunksDone;
  final int chunksTotal;

  /// Non null uniquement après réception réussie (récepteur) : à relire côté app
  /// pour recharger [LifecycleService] / UI si besoin.
  final BitiProfile? receivedProfile;

  /// Rôle choisi pour la session en cours (libellés « Accueillir » / « Envoyer »).
  final BitiTransferUserRole? transferRole;

  BitiTransferBlocState copyWith({
    BitiTransferPhase? phase,
    String? message,
    int? chunksDone,
    int? chunksTotal,
    BitiProfile? receivedProfile,
    BitiTransferUserRole? transferRole,
    bool clearReceived = false,
  }) {
    return BitiTransferBlocState(
      phase: phase ?? this.phase,
      message: message,
      chunksDone: chunksDone ?? this.chunksDone,
      chunksTotal: chunksTotal ?? this.chunksTotal,
      receivedProfile: clearReceived
          ? null
          : (receivedProfile ?? this.receivedProfile),
      transferRole: transferRole ?? this.transferRole,
    );
  }

  static BitiTransferBlocState fromService(
    BitiTransferState s, {
    BitiTransferUserRole? transferRole,
  }) {
    return BitiTransferBlocState(
      phase: s.phase,
      message: s.message,
      chunksDone: s.chunksDone,
      chunksTotal: s.chunksTotal,
      receivedProfile: s.receivedProfile,
      transferRole: transferRole,
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

/// Bloc dédié au transfert BLE — n’impacte pas les autres Blocs de l’app.
class BitiTransferBloc
    extends Bloc<BitiTransferBlocEvent, BitiTransferBlocState> {
  BitiTransferBloc({BitiTransferService? service})
    : _service = service ?? BitiTransferService(),
      super(const BitiTransferBlocState.initial()) {
    on<BitiTransferSendStarted>(_onSendStarted);
    on<BitiTransferReceiveStarted>(_onReceiveStarted);
    on<BitiTransferCancelled>(_onCancelled);
    on<_BitiTransferServiceStateSync>(_onServiceState);

    _serviceSub = _service.stateStream.listen(
      (BitiTransferState s) => add(_BitiTransferServiceStateSync(s)),
    );
  }

  final BitiTransferService _service;
  StreamSubscription<BitiTransferState>? _serviceSub;

  BitiTransferUserRole? _pendingTransferRole;

  Future<void> _onSendStarted(
    BitiTransferSendStarted event,
    Emitter<BitiTransferBlocState> emit,
  ) async {
    _pendingTransferRole = BitiTransferUserRole.send;
    await _service.startSend(event.profile);
  }

  Future<void> _onReceiveStarted(
    BitiTransferReceiveStarted event,
    Emitter<BitiTransferBlocState> emit,
  ) async {
    _pendingTransferRole = BitiTransferUserRole.receive;
    await _service.startReceive();
  }

  Future<void> _onCancelled(
    BitiTransferCancelled event,
    Emitter<BitiTransferBlocState> emit,
  ) async {
    await _service.cancel();
  }

  void _onServiceState(
    _BitiTransferServiceStateSync event,
    Emitter<BitiTransferBlocState> emit,
  ) {
    if (event.state.phase == BitiTransferPhase.idle) {
      _pendingTransferRole = null;
    }
    emit(
      BitiTransferBlocState.fromService(
        event.state,
        transferRole: _pendingTransferRole,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _serviceSub?.cancel();
    await _service.dispose();
    return super.close();
  }
}
