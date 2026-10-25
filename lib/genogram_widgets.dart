import 'package:flutter/material.dart';

import 'models.dart';

/// A compact, touch-friendly genogram. It deliberately shows only the nearby
/// generations; choosing a new centre is how a large family tree is explored.
class GenogramBoard extends StatelessWidget {
  const GenogramBoard({
    super.key,
    required this.people,
    required this.relationships,
    required this.centerId,
    required this.onSelect,
  });

  final List<Person> people;
  final List<PersonRelationship> relationships;
  final String centerId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final center = people.firstWhere((person) => person.id == centerId);
    final byId = {for (final person in people) person.id: person};
    final visible = <String>{centerId};
    final positions = <String, Offset>{centerId: const Offset(420, 320)};

    List<String> linked(
      RelationshipKind kind,
      bool Function(PersonRelationship) match,
    ) => relationships
        .where((edge) => edge.kind == kind && match(edge))
        .map(
          (edge) => edge.fromPersonId == centerId
              ? edge.toPersonId
              : edge.fromPersonId,
        )
        .where(byId.containsKey)
        .toSet()
        .toList();

    final parents = relationships
        .where(
          (edge) =>
              edge.kind == RelationshipKind.parentChild &&
              edge.toPersonId == centerId,
        )
        .map((edge) => edge.fromPersonId)
        .where(byId.containsKey)
        .toList();
    final children = relationships
        .where(
          (edge) =>
              edge.kind == RelationshipKind.parentChild &&
              edge.fromPersonId == centerId,
        )
        .map((edge) => edge.toPersonId)
        .where(byId.containsKey)
        .toList();
    final partners =
        linked(
          RelationshipKind.spouse,
          (edge) =>
              edge.fromPersonId == centerId || edge.toPersonId == centerId,
        )..addAll(
          linked(
            RelationshipKind.partner,
            (edge) =>
                edge.fromPersonId == centerId || edge.toPersonId == centerId,
          ),
        );
    final parentIds = parents.toSet();
    final siblings = relationships
        .where(
          (edge) =>
              edge.kind == RelationshipKind.parentChild &&
              parentIds.contains(edge.fromPersonId) &&
              edge.toPersonId != centerId,
        )
        .map((edge) => edge.toPersonId)
        .where(byId.containsKey)
        .toSet()
        .toList();
    final social = relationships
        .where(
          (edge) =>
              edge.fromPersonId == centerId || edge.toPersonId == centerId,
        )
        .where(
          (edge) => !const {
            RelationshipKind.parentChild,
            RelationshipKind.adoptedParentChild,
            RelationshipKind.stepParentChild,
            RelationshipKind.spouse,
            RelationshipKind.partner,
            RelationshipKind.sibling,
          }.contains(edge.kind),
        )
        .map(
          (edge) => edge.fromPersonId == centerId
              ? edge.toPersonId
              : edge.fromPersonId,
        )
        .where(byId.containsKey)
        .toSet()
        .toList();

    void positionRow(
      List<String> ids,
      double y, {
      double start = 220,
      double span = 400,
    }) {
      for (var index = 0; index < ids.length; index++) {
        final x =
            (ids.length == 1 ? 420 : start + span * index / (ids.length - 1))
                .toDouble();
        positions[ids[index]] = Offset(x, y);
        visible.add(ids[index]);
      }
    }

    positionRow(parents, 90);
    positionRow(siblings, 320, start: 120, span: 170);
    positionRow(children, 550);
    positionRow(partners.take(1).toList(), 320, start: 650, span: 0);
    positionRow(social, 400, start: 90, span: 690);

    final visibleEdges = relationships
        .where(
          (edge) =>
              visible.contains(edge.fromPersonId) &&
              visible.contains(edge.toPersonId),
        )
        .toList();
    return SizedBox(
      height: 670,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: const Color(0xFFFFFBF8),
          child: InteractiveViewer(
            minScale: .65,
            maxScale: 2.4,
            boundaryMargin: const EdgeInsets.all(100),
            child: SizedBox(
              width: 840,
              height: 650,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RelationshipLines(positions, visibleEdges),
                    ),
                  ),
                  for (final id in visible)
                    if (positions[id] != null)
                      Positioned(
                        left: positions[id]!.dx - 66,
                        top: positions[id]!.dy - 40,
                        width: 132,
                        child: _PersonNode(
                          person: byId[id]!,
                          isCenter: id == center.id,
                          onTap: () => onSelect(id),
                        ),
                      ),
                  const Positioned(
                    left: 18,
                    top: 16,
                    child: _GuideLabel(
                      icon: Icons.zoom_in,
                      label: '指で拡大・移動できます',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonNode extends StatelessWidget {
  const _PersonNode({
    required this.person,
    required this.isCenter,
    required this.onTap,
  });
  final Person person;
  final bool isCenter;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: isCenter
        ? Theme.of(context).colorScheme.primaryContainer
        : Colors.white,
    borderRadius: BorderRadius.circular(16),
    elevation: isCenter ? 3 : 1,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              child: Text(
                person.initials.isEmpty
                    ? person.name.characters.first
                    : person.initials,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              person.lifeStatus == LifeStatus.deceased
                  ? '故人'
                  : person.relationship,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GuideLabel extends StatelessWidget {
  const _GuideLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
}

class _RelationshipLines extends CustomPainter {
  const _RelationshipLines(this.positions, this.edges);
  final Map<String, Offset> positions;
  final List<PersonRelationship> edges;
  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final from = positions[edge.fromPersonId];
      final to = positions[edge.toPersonId];
      if (from == null || to == null) continue;
      final isBlood = {
        RelationshipKind.parentChild,
        RelationshipKind.adoptedParentChild,
        RelationshipKind.stepParentChild,
      }.contains(edge.kind);
      final paint = Paint()
        ..color = isBlood ? const Color(0xFFC76E7D) : const Color(0xFF6D8793)
        ..strokeWidth = isBlood ? 2.4 : 1.8
        ..style = PaintingStyle.stroke;
      if (!isBlood) paint.strokeCap = StrokeCap.round;
      final path = Path()..moveTo(from.dx, from.dy);
      if (isBlood) {
        final middle = (from.dy + to.dy) / 2;
        path.lineTo(from.dx, middle);
        path.lineTo(to.dx, middle);
        path.lineTo(to.dx, to.dy);
      } else {
        path.lineTo(to.dx, to.dy);
      }
      canvas.drawPath(path, paint);
      if (edge.kind == RelationshipKind.spouse ||
          edge.kind == RelationshipKind.partner) {
        final midpoint = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        canvas.drawCircle(
          midpoint,
          4,
          Paint()..color = const Color(0xFFE6A36E),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RelationshipLines old) =>
      !identical(old.positions, positions) || !identical(old.edges, edges);
}
