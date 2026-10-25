import 'package:flutter/material.dart';

import 'app.dart';
import 'cloudflare_repository.dart';
import 'glass_ui.dart';
import 'models.dart';
import 'screens.dart';

class WorkersAiScreen extends StatefulWidget {
  const WorkersAiScreen({super.key});
  @override
  State<WorkersAiScreen> createState() => _WorkersAiScreenState();
}

class _WorkersAiScreenState extends State<WorkersAiScreen> {
  final input = TextEditingController();
  bool invitation = false, consent = false, busy = false, reviewed = false;
  String? answer, error, personId;
  Map<String, dynamic>? draft;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _run(CloudflareFamilyRepository repo) async {
    setState(() {
      busy = true;
      error = null;
      answer = null;
      draft = null;
      reviewed = false;
    });
    try {
      if (invitation) {
        final result = await repo.suggestInvitation(
          input.text,
          consent: consent,
        );
        if (mounted) setState(() => draft = result);
      } else {
        final result = await repo.askGuide(input.text, consent: consent);
        if (mounted) setState(() => answer = result);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final remote = repo is CloudflareFamilyRepository ? repo : null;
    return Scaffold(
      appBar: AppBar(title: const Text('AI補助')),
      body: PageBody(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('準備を確認'),
                icon: Icon(Icons.checklist_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('案内状の文字'),
                icon: Icon(Icons.description_outlined),
              ),
            ],
            selected: {invitation},
            onSelectionChanged: busy
                ? null
                : (selection) => setState(() {
                    invitation = selection.first;
                    input.clear();
                    consent = false;
                    answer = null;
                    draft = null;
                    error = null;
                  }),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: input,
                    enabled: !busy,
                    maxLength: invitation ? 6000 : 1200,
                    minLines: 4,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: invitation ? '案内状から読み取った文字' : '確認したいこと',
                      hintText: invitation
                          ? '開催日・時刻・会場が分かる部分を入力'
                          : '例：三回忌に参列する前に確認すること',
                    ),
                    onChanged: (_) => setState(() {
                      consent = false;
                      draft = null;
                      answer = null;
                      reviewed = false;
                    }),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                    title: const Text('上の入力内容をCloudflare Workers AIへ送信する'),
                    subtitle: const Text(
                      '家族の登録情報や写真は自動で送信しません。不要な氏名・住所・連絡先は入力から除いてください。',
                    ),
                  ),
                  if (remote == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text('デモではAIへの送信は行いません。'),
                    ),
                  FilledButton.icon(
                    onPressed:
                        remote == null ||
                            busy ||
                            !consent ||
                            input.text.trim().isEmpty
                        ? null
                        : () => _run(remote),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(invitation ? '予定の候補を抽出' : '確認する'),
                  ),
                ],
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: GlassCard(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassSkeleton(height: 22, width: 150),
                      SizedBox(height: 16),
                      GlassSkeleton(),
                      SizedBox(height: 10),
                      GlassSkeleton(),
                      SizedBox(height: 10),
                      GlassSkeleton(width: 220),
                    ],
                  ),
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (answer != null)
            GlassEntrance(
              child: GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: SelectableText(answer!),
                ),
              ),
            ),
          if (draft != null)
            GlassEntrance(
              child: GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '抽出した候補',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      for (final entry in {
                        '題名': draft!['title'],
                        '開催日': draft!['date'],
                        '時刻': draft!['time'],
                        '会場': draft!['place'],
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text('${entry.key}：${entry.value ?? '確認が必要'}'),
                        ),
                      for (final note
                          in (draft!['uncertainties'] as List? ?? []))
                        Text('・$note'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: personId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '対象人物'),
                        items: repo.people
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => personId = v),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: reviewed,
                        onChanged: (v) => setState(() => reviewed = v ?? false),
                        title: const Text('案内状の原本と候補を照合した'),
                      ),
                      FilledButton(
                        onPressed:
                            !reviewed || personId == null || repo.viewerMode
                            ? null
                            : () {
                                final event = MemorialEvent(
                                  id: 'ai-draft-${DateTime.now().microsecondsSinceEpoch}',
                                  title: draft!['title'] as String? ?? '法要',
                                  type: '法事・法要',
                                  subjectPersonId: personId!,
                                  status: EventStatus.planned,
                                  date: DateTime.tryParse(
                                    draft!['date'] as String? ?? '',
                                  ),
                                  notes: [
                                    if (draft!['time'] != null)
                                      '時刻：${draft!['time']}',
                                    if (draft!['place'] != null)
                                      '会場：${draft!['place']}',
                                  ].join('\n'),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EventEditScreen(event: event),
                                  ),
                                );
                              },
                        child: const Text('予定の入力画面へ'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (answer != null || draft != null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'AIの回答は確認用の候補です。宗派・地域・家庭によって異なるため、案内状や寺院・主催者への確認を優先してください。',
              ),
            ),
        ],
      ),
    );
  }
}
