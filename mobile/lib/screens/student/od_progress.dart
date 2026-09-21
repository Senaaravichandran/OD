import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../theme.dart';

/// The approval chain, drawn as a stepper.
///
///   Submitted -> Advisor review -> HOD review -> Approved
///
/// A rejection turns the step where it happened red and stops the line there,
/// so it is obvious who declined rather than just that something failed.
class OdProgress extends StatelessWidget {
  const OdProgress({super.key, required this.request});

  final ODRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;

    final advisorDone = !r.isPendingAdvisor;
    final advisorRejected = r.isRejectedByAdvisor;
    final hodReached = r.isPendingHod || r.isApproved || r.isRejectedByHod;
    final hodRejected = r.isRejectedByHod;

    return Column(
      children: [
        Row(
          children: [
            _Node(
              label: 'Submitted',
              state: _NodeState.done,
              icon: Icons.upload_file_rounded,
            ),
            _Link(active: advisorDone, failed: advisorRejected),
            _Node(
              label: 'Advisor',
              state: advisorRejected
                  ? _NodeState.failed
                  : advisorDone
                      ? _NodeState.done
                      : _NodeState.current,
              icon: Icons.person_search_rounded,
            ),
            _Link(active: hodReached && !advisorRejected, failed: hodRejected),
            _Node(
              label: 'HOD',
              state: hodRejected
                  ? _NodeState.failed
                  : r.isApproved
                      ? _NodeState.done
                      : advisorRejected
                          ? _NodeState.blocked
                          : hodReached
                              ? _NodeState.current
                              : _NodeState.blocked,
              icon: Icons.verified_user_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Caption(request: r),
      ],
    );
  }
}

enum _NodeState { done, current, blocked, failed }

class _Node extends StatelessWidget {
  const _Node({required this.label, required this.state, required this.icon});

  final String label;
  final _NodeState state;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (state) {
      _NodeState.done => (AppTheme.success, Colors.white),
      _NodeState.current => (AppTheme.warning, Colors.white),
      _NodeState.failed => (AppTheme.danger, Colors.white),
      _NodeState.blocked => (const Color(0xFFE2E8F0), AppTheme.muted),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(
            state == _NodeState.done
                ? Icons.check_rounded
                : state == _NodeState.failed
                    ? Icons.close_rounded
                    : icon,
            size: 17,
            color: fg,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 64,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: state == _NodeState.blocked ? FontWeight.w500 : FontWeight.w700,
              color: state == _NodeState.blocked ? AppTheme.muted : AppTheme.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.active, required this.failed});

  final bool active;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2.5,
        margin: const EdgeInsets.only(bottom: 22),
        color: failed
            ? AppTheme.danger.withValues(alpha: 0.4)
            : active
                ? AppTheme.success
                : const Color(0xFFE2E8F0),
      ),
    );
  }
}

/// One line saying what is happening now, in plain words.
class _Caption extends StatelessWidget {
  const _Caption({required this.request});

  final ODRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final (text, color) = switch (r.status) {
      'PENDING_ADVISOR' => ('Waiting for ${r.advisorName} to review', AppTheme.warning),
      'APPROVED_BY_ADVISOR' => ('Recommended by ${r.advisorName}. Waiting for HOD sanction.', AppTheme.primary),
      'APPROVED' => ('Sanctioned. You can submit your result once the event is over.', AppTheme.success),
      'REJECTED_ADVISOR' => ('Not approved by ${r.advisorName}', AppTheme.danger),
      'REJECTED_HOD' => ('Not sanctioned by the HOD', AppTheme.danger),
      _ => (r.statusDisplay, AppTheme.muted),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.tint(color),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
