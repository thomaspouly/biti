import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/biti_transfer_bloc.dart';
import '../models/biti_profile.dart';
import '../services/biti_transfer_service.dart';

/// Deux actions « Accueillir » / « Envoyer » branchées sur [BitiTransferBloc].
///
/// Intégration typique :
/// ```dart
/// BlocProvider(
///   create: (_) => BitiTransferBloc(),
///   child: BitiTransferActions(currentProfile: profil),
/// )
/// ```
///
/// [currentProfile] peut être `null` (aucun Biti) : le bouton Envoyer est alors désactivé.
class BitiTransferActions extends StatelessWidget {
  const BitiTransferActions({super.key, this.currentProfile});

  final BitiProfile? currentProfile;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BitiTransferBloc, BitiTransferBlocState>(
      builder: (BuildContext context, BitiTransferBlocState state) {
        return _BitiTransferActionsBody(state: state, profile: currentProfile);
      },
    );
  }
}

class _BitiTransferActionsBody extends StatelessWidget {
  const _BitiTransferActionsBody({required this.state, required this.profile});

  final BitiTransferBlocState state;
  final BitiProfile? profile;

  @override
  Widget build(BuildContext context) {
    final BitiTransferPhase p = state.phase;

    if (p == BitiTransferPhase.idle) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.read<BitiTransferBloc>().add(
                const BitiTransferReceiveStarted(),
              ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Accueillir'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: profile == null
                  ? null
                  : () {
                      final BitiProfile p = profile!;
                      context.read<BitiTransferBloc>().add(
                        BitiTransferSendStarted(p),
                      );
                    },
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Envoyer'),
            ),
          ),
        ],
      );
    }

    if (p == BitiTransferPhase.searching) {
      final bool receiving = state.transferRole == BitiTransferUserRole.receive;
      return _statusRow(
        child: const CircularProgressIndicator(strokeWidth: 2),
        text: receiving
            ? 'En attente d’un envoi… (l’autre doit choisir Envoyer)'
            : 'Recherche d’un Biti… (l’autre doit choisir Accueillir)',
      );
    }

    if (p == BitiTransferPhase.connecting) {
      return _statusRow(
        child: const CircularProgressIndicator(strokeWidth: 2),
        text: 'Connexion…',
      );
    }

    if (p == BitiTransferPhase.negotiating) {
      return _statusRow(
        child: const CircularProgressIndicator(strokeWidth: 2),
        text: 'Préparation du transfert…',
      );
    }

    if (p == BitiTransferPhase.sending) {
      final double v = state.chunksTotal > 0
          ? state.chunksDone / state.chunksTotal
          : 0;
      final int pct = (v * 100).round().clamp(0, 100);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LinearProgressIndicator(value: v > 0 ? v : null),
          const SizedBox(height: 8),
          Text('Envoi du Biti… $pct %'),
          TextButton(
            onPressed: () => context.read<BitiTransferBloc>().add(
              const BitiTransferCancelled(),
            ),
            child: const Text('Annuler'),
          ),
        ],
      );
    }

    if (p == BitiTransferPhase.receiving) {
      final double v = state.chunksTotal > 0
          ? state.chunksDone / state.chunksTotal
          : 0;
      final int pct = (v * 100).round().clamp(0, 100);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LinearProgressIndicator(value: v > 0 ? v : null),
          const SizedBox(height: 8),
          Text('Réception d’un Biti… $pct %'),
          TextButton(
            onPressed: () => context.read<BitiTransferBloc>().add(
              const BitiTransferCancelled(),
            ),
            child: const Text('Annuler'),
          ),
        ],
      );
    }

    if (p == BitiTransferPhase.success) {
      return Row(
        children: <Widget>[
          Icon(Icons.check_circle, color: Colors.green.shade600),
          const SizedBox(width: 8),
          const Expanded(child: Text('Transfert réussi !')),
        ],
      );
    }

    if (p == BitiTransferPhase.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.message ?? 'Erreur',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TextButton(
                onPressed: () => _openSettings(context),
                child: const Text('Réglages'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.read<BitiTransferBloc>().add(
                  const BitiTransferReceiveStarted(),
                ),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Accueillir'),
              ),
              FilledButton.icon(
                onPressed: profile == null
                    ? null
                    : () => context.read<BitiTransferBloc>().add(
                        BitiTransferSendStarted(profile!),
                      ),
                icon: const Icon(Icons.upload_rounded),
                label: const Text('Envoyer'),
              ),
            ],
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _openSettings(BuildContext context) async {
    await BitiTransferService.openSystemSettings();
  }
}

Widget _statusRow({required Widget child, required String text}) {
  return Row(
    children: <Widget>[
      SizedBox(width: 24, height: 24, child: child),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  );
}
