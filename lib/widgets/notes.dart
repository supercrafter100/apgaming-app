import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../theme.dart';

// Notes staff keep about someone, shown the way the website's reservations page shows them.

const _amber = Color(0xFFFCD34D);

Color noteColor(NoteType type) => switch (type) {
  NoteType.note => HubColors.blue,
  NoteType.warning => _amber,
  NoteType.block => HubColors.danger,
};

IconData noteIcon(NoteType type) => switch (type) {
  NoteType.note => Icons.sticky_note_2_outlined,
  NoteType.warning => Icons.warning_amber_rounded,
  NoteType.block => Icons.block_rounded,
};

String noteLabel(NoteType type) => switch (type) {
  NoteType.note => 'Notitie',
  NoteType.warning => 'Waarschuwing',
  NoteType.block => 'Blokkade',
};

final _noteDate = DateFormat('d MMM y, HH:mm', 'nl_BE');

String formatNoteDate(DateTime moment) => _noteDate.format(moment);

/// "Tot 26 nov. 2026, 18:00 · nog 3 dagen", or "Geen einddatum".
String describeNoteExpiry(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return 'Geen einddatum';
  final left = expiresAt.difference(now ?? DateTime.now());
  final hours = (left.inMinutes / 60).ceil();
  final days = (hours / 24).ceil();
  final remaining = hours < 24 ? 'nog $hours uur' : 'nog $days ${days == 1 ? 'dag' : 'dagen'}';
  return 'Tot ${formatNoteDate(expiresAt)} · $remaining';
}

/// "1 blokkade, 2 waarschuwingen", most serious first.
String summarizeNotes(List<ActiveNote> notes) {
  const words = {
    NoteType.block: ('blokkade', 'blokkades'),
    NoteType.warning: ('waarschuwing', 'waarschuwingen'),
    NoteType.note: ('notitie', 'notities'),
  };
  return [
    for (final type in [NoteType.block, NoteType.warning, NoteType.note])
      if (notes.where((n) => n.type == type).length case final count when count > 0)
        '$count ${count == 1 ? words[type]!.$1 : words[type]!.$2}',
  ].join(', ');
}

/// A small flag next to someone's name, coloured by their most serious note. Tapping it shows the notes.
class NoteFlag extends StatelessWidget {
  const NoteFlag({super.key, required this.notes, required this.name, this.label});

  final List<ActiveNote> notes;
  final String name;

  /// Text next to the icon, for a wider chip such as in the day's heads-up strip.
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    final type = notes.first.type;
    final color = noteColor(type);
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '${summarizeNotes(notes)} over $name',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showNotesSheet(context, name: name, notes: notes),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 5 : 10, vertical: label == null ? 2 : 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(noteIcon(type), size: label == null ? 15 : 16, color: color),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label!,
                    style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else if (notes.length > 1) ...[
                const SizedBox(width: 3),
                Text(
                  '${notes.length}',
                  style: text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One note: its type, how long it still counts, the text and who wrote it.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note});

  final ActiveNote note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = noteColor(note.type);
    final isNote = note.type == NoteType.note;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isNote ? HubColors.surface : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isNote ? HubColors.border : color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(noteIcon(note.type), size: 13, color: color),
                    const SizedBox(width: 4),
                    Text(
                      noteLabel(note.type).toUpperCase(),
                      style: text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 13, color: HubColors.textMuted),
                  const SizedBox(width: 4),
                  // Wraps on a narrow phone instead of running off the card
                  Flexible(
                    child: Text(
                      describeNoteExpiry(note.expiresAt),
                      style: text.labelSmall?.copyWith(color: HubColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(note.content, style: text.bodyMedium),
          const SizedBox(height: 8),
          Text(
            '${note.authorName ?? 'Onbekend'} · ${formatNoteDate(note.createdAt)}',
            style: text.labelSmall?.copyWith(color: HubColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Red banner for someone who is blocked from the site.
class BlockedBanner extends StatelessWidget {
  const BlockedBanner({super.key, this.message = 'Deze persoon is geblokkeerd en kan niet inloggen.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HubColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HubColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_rounded, color: HubColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: HubColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The notes that still count for someone, under a heading; nothing when there are none.
class NotesSection extends StatelessWidget {
  const NotesSection({super.key, required this.notes});

  final List<ActiveNote> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ACTIEVE NOTITIES', style: text.labelSmall?.copyWith(color: HubColors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        for (final note in notes) ...[NoteCard(note: note), const SizedBox(height: 8)],
      ],
    );
  }
}

Future<void> showNotesSheet(BuildContext context, {required String name, required List<ActiveNote> notes}) {
  HapticFeedback.selectionClick();
  final blocked = notes.any((n) => n.type == NoteType.block);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
          Text(
            summarizeNotes(notes),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: HubColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (blocked) ...[
            const BlockedBanner(
              message: 'Deze persoon is geblokkeerd en kan niet inloggen. Een bestaande reservatie blijft wel staan.',
            ),
            const SizedBox(height: 12),
          ],
          for (final note in notes) ...[NoteCard(note: note), const SizedBox(height: 8)],
        ],
      ),
    ),
  );
}
