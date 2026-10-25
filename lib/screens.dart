import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'attachment_models.dart';
import 'attachment_widgets.dart';
import 'genogram_widgets.dart';
import 'glass_ui.dart';
import 'cloudflare_repository.dart';
import 'local_reminders.dart';
import 'invitation_draft.dart';
import 'invitation_ocr.dart';
import 'models.dart';
import 'repository.dart';
import 'workers_ai_screen.dart';

const _gap = SizedBox(height: 12);

String dateLabel(DateTime? date) =>
    date == null ? '日付未設定' : '${date.year}年${date.month}月${date.day}日';
String yen(int value) =>
    '¥${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int index = 0;
  late final AnimationController tabMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  void selectTab(int value) {
    if (value == index) return;
    setState(() => index = value);
    if (!MediaQuery.disableAnimationsOf(context)) {
      tabMotion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    tabMotion.dispose();
    super.dispose();
  }

  static const labels = ['ホーム', '家系図', '記録', '人物'];
  static const icons = [
    Icons.home_outlined,
    Icons.account_tree_outlined,
    Icons.event_note_outlined,
    Icons.people_outline,
  ];
  static const selectedIcons = [
    Icons.home_rounded,
    Icons.account_tree_rounded,
    Icons.event_note_rounded,
    Icons.people_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final dueSoonCount = memorialEventsWithinDays(
      repo.confirmedEvents,
      DateTime.now(),
    );
    final pages = const [
      HomeScreen(),
      FamilyTreeScreen(),
      RecordsScreen(),
      PeopleScreen(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = FadeTransition(
      opacity: CurvedAnimation(parent: tabMotion, curve: Curves.easeOut),
      child: IndexedStack(index: index, children: pages),
    );
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F0FC),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.family_restroom_rounded,
                size: 20,
                color: Color(0xFF3165A8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '家族の記憶',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'AI補助',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkersAiScreen()),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          if (dueSoonCount > 0)
            IconButton(
              tooltip: '7日以内の予定 $dueSoonCount件',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('まもなくの法要・予定'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final event in repo.confirmedEvents.where((event) {
                          final date = event.date;
                          if (date == null ||
                              event.status != EventStatus.planned) {
                            return false;
                          }
                          final today = DateTime.now();
                          final start = DateTime(
                            today.year,
                            today.month,
                            today.day,
                          );
                          final day = DateTime(date.year, date.month, date.day);
                          return !day.isBefore(start) &&
                              day.isBefore(start.add(const Duration(days: 8)));
                        }))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(event.title),
                            subtitle: Text(dateLabel(event.date)),
                            leading: const Icon(Icons.event_available_outlined),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('閉じる'),
                    ),
                  ],
                ),
              ),
              icon: Badge(
                label: Text('$dueSoonCount'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          IconButton(
            tooltip: '家族と設定',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                GlassSurface(
                  radius: 0,
                  child: NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: selectTab,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationRailDestination(
                          icon: Icon(icons[i]),
                          selectedIcon: Icon(selectedIcons[i]),
                          label: Text(labels[i]),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: GlassSurface(
                  radius: 28,
                  child: NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: selectTab,
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationDestination(
                          icon: Icon(icons[i]),
                          selectedIcon: Icon(selectedIcons[i]),
                          label: labels[i],
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
    children: [
      Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++)
                GlassEntrance(order: i, child: children[i]),
            ],
          ),
        ),
      ),
    ],
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Row(
      children: [
        Container(
          width: 7,
          height: 22,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        trailing ?? const SizedBox.shrink(),
      ],
    ),
  );
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    if (!repo.isDemo) return const SizedBox.shrink();
    return GlassCard(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined),
            SizedBox(width: 12),
            Expanded(child: Text('デモ：架空の青葉家を表示しています。この端末での操作は家族へ共有されません。')),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final upcoming = repo.confirmedEvents
        .where((e) => e.status == EventStatus.planned)
        .toList();
    return PageBody(
      children: [
        const DemoBanner(),
        _gap,
        const _HomeHero(),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final cards = [
              _ActionCard(
                icon: Icons.person_search_outlined,
                title: '誰だっけ？',
                subtitle: '顔・呼び名・故人との関係で探す',
                color: const Color(0xFFFFE3E9),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PersonSearchScreen()),
                ),
              ),
              _ActionCard(
                icon: Icons.history_outlined,
                title: '前回どうした？',
                subtitle: '会場・費用・参加者をすぐ確認',
                color: const Color(0xFFE2F3EE),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PreviousRecordsScreen(),
                  ),
                ),
              ),
            ];
            return box.maxWidth >= 620
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(
                    children: [cards[0], const SizedBox(height: 12), cards[1]],
                  );
          },
        ),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.auto_awesome_outlined,
          title: '年のそなえ',
          subtitle: 'お盆・彼岸・贈答・亡くなった直後の準備を確認',
          color: const Color(0xFFFFF0C9),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AnnualGuideScreen()),
          ),
        ),
        const SizedBox(height: 20),
        SectionTitle(
          '次の予定',
          trailing: TextButton(
            onPressed: () =>
                _showInfo(context, '予定の追加', '記録タブの「追加」から、種類・対象人物・日付を入力できます。'),
            child: const Text('追加方法'),
          ),
        ),
        if (upcoming.isEmpty)
          const _EmptyCard(
            icon: Icons.event_available_outlined,
            text: '確定した予定はありません',
            action: '法要候補を確認してください',
          )
        else
          for (final event in upcoming) EventCard(event: event),
        const SectionTitle('未確認の法要候補'),
        if (repo.candidates.isEmpty)
          const _EmptyCard(
            icon: Icons.check_circle_outline,
            text: '未確認の候補はありません',
            action: '家族で確認した予定がここから移動します',
          )
        else
          for (final event in repo.candidates) CandidateCard(event: event),
        const SectionTitle('最近の記録'),
        for (final event in repo.confirmedEvents.take(2))
          EventCard(event: event),
      ],
    );
  }
}

class AnnualGuideScreen extends StatelessWidget {
  const AnnualGuideScreen({super.key});

  static const _guides = [
    (
      '亡くなった直後',
      'まず記録すること',
      [
        '没年月日・戒名／法名・宗派・菩提寺を残す',
        '連絡する親族、呼び方、窓口担当を整理する',
        '領収書・案内状・遺骨や位牌の保管場所を写真と一緒に残す',
      ],
    ),
    (
      '春・秋のお彼岸',
      '墓参りの前に確認',
      [
        '寺院の彼岸会、墓参りの可否と日時を確認する',
        '供花・供物のルール、駐車場、家族の集合方法を決める',
        '前回の写真・費用・来客対応を見返す',
      ],
    ),
    (
      'お盆・新盆',
      '地域と寺院への確認が先',
      [
        '盆の時期は7月・8月・旧暦など地域で異なります',
        '初めて迎えるお盆は新盆の可能性があります。寺院へ確認する',
        '読経、来客、墓参り、会食の有無と担当を家族で決める',
      ],
    ),
    (
      '年忌法要',
      '候補日を予定へ確定',
      [
        '一周忌、三回忌、七回忌などは候補日として確認する',
        '寺院・会場・参加者・お布施は前回記録から下書きにする',
        '宗派・地域・家庭で異なるため、候補を自動確定しない',
      ],
    ),
    (
      'お中元・お歳暮・年始',
      '前回どうした？を使う',
      [
        '相手ごとに送る／送らない、予算、品物、送付先を確認する',
        '地域ごとの時期や表書きは、相手側の慣習を確認する',
        '品物・領収書・反応を次回のために残す',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('年のそなえ')),
    body: PageBody(
      children: [
        GlassCard(
          color: const Color(0xFFFFF4D6),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'これは一般的な準備の案内です。宗派・菩提寺・地域・ご家庭の慣習で異なるため、日程や内容は必ず確認してから予定にしてください。',
              style: TextStyle(height: 1.55),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SectionTitle('年間のやること'),
        for (final guide in _guides)
          GlassCard(
            child: ExpansionTile(
              leading: const Icon(Icons.checklist_rounded),
              title: Text(
                guide.$1,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(guide.$2),
              children: [
                for (final task in guide.$3)
                  ListTile(
                    leading: const Icon(Icons.circle_outlined, size: 20),
                    title: Text(task),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        const SectionTitle('法要のマナーTIPS'),
        const GlassCard(
          color: Color(0xFFFFF4D6),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              '地域・宗派・ご家庭で異なります。迷ったら施主や菩提寺へ確認し、案内状の指定を優先してください。金額は一律の正解を表示せず、家族の過去記録を参考にできます。',
            ),
          ),
        ),
        for (final tip in _memorialEtiquetteTips)
          GlassCard(
            child: ExpansionTile(
              leading: const Icon(Icons.lightbulb_outline_rounded),
              title: Text(
                tip.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(tip.body, style: const TextStyle(height: 1.55)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(tip.url),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text('出典：${tip.source}'),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('ホームの法要候補へ戻る'),
        ),
      ],
    ),
  );
}

class _EtiquetteTip {
  const _EtiquetteTip(this.title, this.body, this.source, this.url);
  final String title;
  final String body;
  final String source;
  final String url;
}

const _memorialEtiquetteTips = <_EtiquetteTip>[
  _EtiquetteTip(
    '香典袋の墨色',
    '通夜・葬儀では薄墨が使われることがあります。法要では濃墨が一般的とされますが、「四十九日まで／以降」の区切りは地域や考え方で異なる例があります。案内状・施主・菩提寺の指定を優先してください。',
    '中本葬祭（葬祭ディレクター解説）',
    'https://nakamoto.jp/questions-from-customers/kouden_usuzumi/',
  ),
  _EtiquetteTip(
    'お布施・御車代・御膳料',
    '全国一律に決まった金額はありません。宗派・寺院・地域・法要内容・これまでのお付き合いで異なるため、分からないときは寺院へ事前に尋ねて構いません。前回の家族記録も参考にし、今回の案内と寺院の説明で確認しましょう。',
    '浄土真宗本願寺派 徳正寺 FAQ',
    'https://www.tokushoji.jp/faq',
  ),
  _EtiquetteTip(
    '服装と「平服」',
    '案内状の指定を優先します。「平服」は普段着を意味しない場合がありますが、法要の回忌や寺院によって案内は異なります。迷ったら施主へ確認し、自己判断で礼装の要否を決めないようにしましょう。',
    '興正寺 FAQ / 自然寺の法事マナー',
    'https://www.koushoji.or.jp/faq/faq-31/',
  ),
];

class _HomeHero extends StatelessWidget {
  const _HomeHero();

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(22),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                RepositoryScope.of(context).familyName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                  color: const Color(0xFF25334A),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '${RepositoryScope.of(context).people.length}人 ・ ${RepositoryScope.of(context).confirmedEvents.length}件の記録',
                style: const TextStyle(height: 1.5, color: Color(0xFF606F83)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x143165A8),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.family_restroom_rounded,
            size: 38,
            color: Color(0xFF3165A8),
          ),
        ),
      ],
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GlassCard(
    color: color,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0x14000000), blurRadius: 10),
                ],
              ),
              child: Icon(icon, color: const Color(0xFFC65369)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF4D3C43),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF6E5E65)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFC65369)),
          ],
        ),
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.text,
    required this.action,
  });
  final IconData icon;
  final String text;
  final String action;
  @override
  Widget build(BuildContext context) => GlassCard(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          _gap,
          Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(action, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.person, {super.key, this.radius = 24});
  final Person person;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    width: radius * 2,
    height: radius * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: person.lifeStatus == LifeStatus.deceased
            ? const [Color(0xFFEDE7E2), Color(0xFFDCD4CE)]
            : const [Color(0xFFFFE2E8), Color(0xFFFFF0D9)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    alignment: Alignment.center,
    child: Text(
      person.initials.isEmpty ? person.name.characters.first : person.initials,
      style: TextStyle(
        fontSize: radius * .7,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF6A4853),
      ),
    ),
  );
}

class PersonCard extends StatelessWidget {
  const PersonCard({super.key, required this.person, this.showLastMet = false});
  final Person person;
  final bool showLastMet;
  @override
  Widget build(BuildContext context) => GlassCard(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PersonDetailScreen(personId: person.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PersonAvatar(person),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    [
                      person.relationship,
                      if (person.nickname.isNotEmpty) person.nickname,
                    ].join(' ・ '),
                  ),
                  if (person.lifeStatus == LifeStatus.deceased)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '故人　${person.died}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                  if (showLastMet && person.lastMet.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(person.lastMet),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event});
  final MemorialEvent event;
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final place = repo.place(event.placeId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventDetailScreen(eventId: event.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _StatusChip(event.status),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(dateLabel(event.date)),
                    if (place != null) Text(place.name),
                    if (event.total > 0) Text('合計 ${yen(event.total)}'),
                    if (event.participants.isNotEmpty)
                      Text('${event.participants.length}名'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final EventStatus status;
  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      EventStatus.planned => '予定',
      EventStatus.completed => '実施済み',
      EventStatus.cancelled => '中止',
    };
    return Chip(visualDensity: VisualDensity.compact, label: Text(label));
  }
}

class CandidateCard extends StatelessWidget {
  const CandidateCard({super.key, required this.event});
  final MemorialEvent event;
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        color: const Color(0xFFFFF3D9),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF392F1D),
                ),
              ),
              Text(
                '${dateLabel(event.date)}（候補）',
                style: const TextStyle(color: Color(0xFF4D412B)),
              ),
              const SizedBox(height: 6),
              const Text(
                '宗派・地域・寺院によって異なります。必ず菩提寺や家族に確認してください。',
                style: TextStyle(color: Color(0xFF4D412B)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: repo.viewerMode
                        ? null
                        : () async {
                            try {
                              await repo.confirmCandidate(event);
                              try {
                                await LocalReminderService.instance.sync(
                                  repo.confirmedEvents,
                                );
                              } catch (_) {
                                // The shared save succeeded; reminders can be
                                // retried from Settings without claiming that
                                // the event save failed.
                              }
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('予定に追加しました。日付と通知を確認してください。'),
                                ),
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '保存できませんでした。通信状態を確認して再試行してください。',
                                  ),
                                ),
                              );
                            }
                          },
                    child: const Text('予定に追加'),
                  ),
                  TextButton(
                    onPressed: repo.viewerMode
                        ? null
                        : () async {
                            try {
                              await repo.dismissCandidate(event);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('変更できませんでした。再試行してください。'),
                                ),
                              );
                            }
                          },
                    child: const Text('今回は表示しない'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showInfo(BuildContext context, String title, String text) =>
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );

class FamilyTreeScreen extends StatelessWidget {
  const FamilyTreeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    if (repo.people.isEmpty) {
      return PageBody(
        children: const [
          SectionTitle('家系図を始める'),
          _EmptyCard(
            icon: Icons.person_add_alt_1_outlined,
            text: '人物がまだ登録されていません',
            action: '「人物」タブから、まず中心にする人を登録してください。',
          ),
        ],
      );
    }
    final center = repo.person(repo.centerPersonId);
    return PageBody(
      children: [
        const SectionTitle('家族関係図'),
        Text(
          '${center.name}を中心に、親子は赤線、配偶・友人・町内会などは青線で表示します。人物をタップすると中心を切り替えます。',
        ),
        const SizedBox(height: 12),
        GenogramBoard(
          people: repo.people,
          relationships: repo.relationships,
          centerId: center.id,
          onSelect: repo.setCenter,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: repo.viewerMode
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RelationshipEditScreen(),
                  ),
                ),
          icon: const Icon(Icons.add_link),
          label: const Text('人物どうしの関係を登録'),
        ),
        const SizedBox(height: 8),
        const Text(
          '血縁以外は「関係者帳」に登録し、大学時代の友人・町内会・会社などのつながりを追加できます。住所・連絡先は本人の了承を得た必要最小限だけ保存します。',
        ),
      ],
    );
  }
}

class RelationshipEditScreen extends StatefulWidget {
  const RelationshipEditScreen({super.key});
  @override
  State<RelationshipEditScreen> createState() => _RelationshipEditScreenState();
}

class _RelationshipEditScreenState extends State<RelationshipEditScreen> {
  final formKey = GlobalKey<FormState>();
  String? fromId;
  String? toId;
  RelationshipKind kind = RelationshipKind.parentChild;
  final label = TextEditingController();
  final notes = TextEditingController();
  @override
  void dispose() {
    label.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final people = repo.people;
    fromId ??= repo.centerPersonId;
    toId ??= people.where((person) => person.id != fromId).firstOrNull?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('人物どうしの関係を登録')),
      body: Form(
        key: formKey,
        child: PageBody(
          children: [
            const Text('親子の場合は「親」を先に選びます。友人・町内会・会社などは、関係の名前を自由に付けられます。'),
            _gap,
            DropdownButtonFormField<String>(
              initialValue: fromId,
              decoration: const InputDecoration(labelText: '起点となる人物'),
              items: people
                  .map(
                    (person) => DropdownMenuItem(
                      value: person.id,
                      child: Text(person.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => fromId = value),
            ),
            _gap,
            DropdownButtonFormField<String>(
              initialValue: toId,
              decoration: const InputDecoration(labelText: '相手の人物'),
              items: people
                  .where((person) => person.id != fromId)
                  .map(
                    (person) => DropdownMenuItem(
                      value: person.id,
                      child: Text(person.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => toId = value),
            ),
            _gap,
            DropdownButtonFormField<RelationshipKind>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: '関係の種類'),
              items: const [
                DropdownMenuItem(
                  value: RelationshipKind.parentChild,
                  child: Text('親 → 子'),
                ),
                DropdownMenuItem(
                  value: RelationshipKind.spouse,
                  child: Text('配偶者'),
                ),
                DropdownMenuItem(
                  value: RelationshipKind.sibling,
                  child: Text('きょうだい'),
                ),
                DropdownMenuItem(
                  value: RelationshipKind.acquaintance,
                  child: Text('友人・知人'),
                ),
                DropdownMenuItem(
                  value: RelationshipKind.workRelated,
                  child: Text('会社・仕事'),
                ),
                DropdownMenuItem(
                  value: RelationshipKind.other,
                  child: Text('その他（自由入力）'),
                ),
              ],
              onChanged: (value) => setState(() => kind = value!),
            ),
            _gap,
            TextFormField(
              controller: label,
              decoration: const InputDecoration(
                labelText: '表示する関係名（任意）',
                hintText: '例：大学時代の友人、町内会、父方のいとこ',
              ),
            ),
            _gap,
            TextFormField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '関係のメモ（任意）'),
            ),
            _gap,
            FilledButton.icon(
              onPressed: people.length < 2 ? null : _save,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('関係を保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (fromId == null || toId == null || fromId == toId) return;
    try {
      await RepositoryScope.of(context).saveRelationship(
        PersonRelationship(
          id: 'relationship-${DateTime.now().microsecondsSinceEpoch}',
          fromPersonId: fromId!,
          toPersonId: toId!,
          kind: kind,
          label: label.text.trim(),
          notes: notes.text.trim(),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存できませんでした。通信状態を確認して再試行してください。')),
        );
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }
}

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  PersonKind kind = PersonKind.family;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final results = repo.searchPeople(query, kind: kind);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageBody(
        children: [
          SegmentedButton<PersonKind>(
            segments: const [
              ButtonSegment(
                value: PersonKind.family,
                label: Text('家族・親族'),
                icon: Icon(Icons.account_tree_outlined),
              ),
              ButtonSegment(
                value: PersonKind.contact,
                label: Text('関係者帳'),
                icon: Icon(Icons.badge_outlined),
              ),
            ],
            selected: {kind},
            onSelectionChanged: (value) => setState(() => kind = value.first),
          ),
          const SizedBox(height: 14),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '名前・呼び名・関係・会った場面で検索',
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 14),
          Text(
            '${results.length}人',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          if (results.isEmpty)
            const _EmptyCard(
              icon: Icons.person_search_outlined,
              text: '該当する人物はいません',
              action: '言葉を短くするか、新しい人物を追加してください',
            )
          else
            for (final p in results)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PersonCard(
                  person: p,
                  showLastMet: kind == PersonKind.contact,
                ),
              ),
        ],
      ),
      floatingActionButton: repo.viewerMode
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-person',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PersonEditScreen(initialKind: kind),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('人物を追加'),
            ),
    );
  }
}

class PersonSearchScreen extends StatefulWidget {
  const PersonSearchScreen({super.key});
  @override
  State<PersonSearchScreen> createState() => _PersonSearchScreenState();
}

class _PersonSearchScreenState extends State<PersonSearchScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final results = repo.searchPeople(query, kind: PersonKind.contact);
    return Scaffold(
      appBar: AppBar(title: const Text('誰だっけ？')),
      body: PageBody(
        children: [
          const Text('名前が分からなくても、故人との関係や会った行事で探せます。'),
          _gap,
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '例：たなか、父の従兄、三回忌',
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 14),
          for (final p in results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PersonCard(person: p, showLastMet: true),
            ),
        ],
      ),
    );
  }
}

class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({super.key, required this.personId});
  final String personId;
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final p = repo.person(personId);
    final relatedEvents = repo.events
        .where(
          (e) =>
              e.subjectPersonId == p.id ||
              e.participants.any((x) => x.name == p.name),
        )
        .where((e) => !e.isCandidate)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('人物情報'),
        actions: [
          if (!repo.viewerMode)
            IconButton(
              tooltip: '編集',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PersonEditScreen(person: p)),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: PageBody(
        children: [
          Center(child: PersonAvatar(p, radius: 42)),
          const SizedBox(height: 10),
          Text(
            p.name,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(p.kana, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          _DetailBlock(
            title: '関係',
            rows: {
              'あなたから見た関係': p.relationship,
              if (p.nickname.isNotEmpty) '呼び名': p.nickname,
              if (p.howToAddress.isNotEmpty) 'どう呼べばよいか': p.howToAddress,
              if (p.lastMet.isNotEmpty) '最後に会った場面': p.lastMet,
              if (p.phone.isNotEmpty) '電話番号': p.phone,
              if (p.email.isNotEmpty) 'メール': p.email,
              if (p.address.isNotEmpty) '住所': p.address,
            },
          ),
          if (p.lifeStatus == LifeStatus.deceased)
            _DetailBlock(
              title: '故人の情報',
              rows: {
                '没年月日': p.died.isEmpty ? '不明' : p.died,
                '戒名・法名': p.posthumousName.isEmpty ? '未登録' : p.posthumousName,
                '宗教形式・宗派': p.religion.isEmpty ? '未登録' : p.religion,
              },
            ),
          if (p.notes.isNotEmpty)
            _DetailBlock(title: '会う前のヒント', rows: {'メモ': p.notes}),
          if (p.lifeStatus == LifeStatus.living)
            _DetailBlock(
              title: '本人への説明',
              rows: {'了承確認': p.consentConfirmed ? '確認済み（デモ）' : '未確認'},
            ),
          AttachmentSection(
            repository: repo,
            targetType: AttachmentTargetType.person,
            targetId: p.id,
          ),
          if (p.placeIds.isNotEmpty) ...[
            const SectionTitle('関連する場所'),
            for (final id in p.placeIds) PlaceCard(place: repo.place(id)!),
          ],
          if (relatedEvents.isNotEmpty) ...[
            const SectionTitle('関連する記録'),
            for (final event in relatedEvents) EventCard(event: event),
          ],
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.rows});
  final String title;
  final Map<String, String> rows;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const Divider(),
            for (final row in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.key,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(row.value),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class PersonEditScreen extends StatefulWidget {
  const PersonEditScreen({
    super.key,
    this.person,
    this.initialKind = PersonKind.family,
  });
  final Person? person;
  final PersonKind initialKind;
  @override
  State<PersonEditScreen> createState() => _PersonEditScreenState();
}

class _PersonEditScreenState extends State<PersonEditScreen> {
  final formKey = GlobalKey<FormState>();
  late PersonKind kind;
  late LifeStatus life;
  late TextEditingController name;
  late TextEditingController kana;
  late TextEditingController relation;
  late TextEditingController nickname;
  late TextEditingController born;
  late TextEditingController died;
  late TextEditingController posthumous;
  late TextEditingController religion;
  late TextEditingController lastMet;
  late TextEditingController addressAs;
  late TextEditingController phone;
  late TextEditingController email;
  late TextEditingController address;
  late TextEditingController notes;
  bool consent = false;
  @override
  void initState() {
    super.initState();
    final p = widget.person;
    kind = p?.kind ?? widget.initialKind;
    life = p?.lifeStatus ?? LifeStatus.living;
    name = TextEditingController(text: p?.name);
    kana = TextEditingController(text: p?.kana);
    relation = TextEditingController(text: p?.relationship);
    nickname = TextEditingController(text: p?.nickname);
    born = TextEditingController(text: p?.born);
    died = TextEditingController(text: p?.died);
    posthumous = TextEditingController(text: p?.posthumousName);
    religion = TextEditingController(text: p?.religion);
    lastMet = TextEditingController(text: p?.lastMet);
    addressAs = TextEditingController(text: p?.howToAddress);
    phone = TextEditingController(text: p?.phone);
    email = TextEditingController(text: p?.email);
    address = TextEditingController(text: p?.address);
    notes = TextEditingController(text: p?.notes);
    consent = p?.consentConfirmed ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      name,
      kana,
      relation,
      nickname,
      born,
      died,
      posthumous,
      religion,
      lastMet,
      addressAs,
      phone,
      email,
      address,
      notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.person == null ? '人物を追加' : '人物を編集')),
    body: Form(
      key: formKey,
      child: PageBody(
        children: [
          DropdownButtonFormField<PersonKind>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: '登録先'),
            items: const [
              DropdownMenuItem(
                value: PersonKind.family,
                child: Text('家族・親族（家系図）'),
              ),
              DropdownMenuItem(value: PersonKind.contact, child: Text('関係者帳')),
            ],
            onChanged: (value) => setState(() => kind = value!),
          ),
          _gap,
          TextFormField(
            controller: name,
            decoration: const InputDecoration(
              labelText: '氏名 *',
              hintText: '架空データだけを入力',
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '氏名を入力してください' : null,
          ),
          _gap,
          TextFormField(
            controller: kana,
            decoration: const InputDecoration(labelText: 'ふりがな'),
          ),
          _gap,
          TextFormField(
            controller: relation,
            decoration: const InputDecoration(
              labelText: '自分・中心人物との関係 *',
              hintText: '例：父の従兄',
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '関係を入力してください' : null,
          ),
          _gap,
          TextFormField(
            controller: nickname,
            decoration: const InputDecoration(labelText: '呼び名'),
          ),
          _gap,
          TextFormField(
            controller: born,
            decoration: const InputDecoration(
              labelText: '生年月日',
              hintText: '1985年 / 1985年4月 / 1985年4月12日',
            ),
          ),
          _gap,
          DropdownButtonFormField<LifeStatus>(
            initialValue: life,
            decoration: const InputDecoration(labelText: '生存状態'),
            items: const [
              DropdownMenuItem(value: LifeStatus.living, child: Text('存命')),
              DropdownMenuItem(value: LifeStatus.deceased, child: Text('故人')),
              DropdownMenuItem(value: LifeStatus.unknown, child: Text('不明')),
            ],
            onChanged: (value) => setState(() => life = value!),
          ),
          _gap,
          if (life == LifeStatus.deceased) ...[
            TextFormField(
              controller: died,
              decoration: const InputDecoration(
                labelText: '没年月日',
                hintText: '年だけ・年月だけでも可',
              ),
            ),
            _gap,
            TextFormField(
              controller: posthumous,
              decoration: const InputDecoration(labelText: '戒名・法名'),
            ),
            _gap,
            TextFormField(
              controller: religion,
              decoration: const InputDecoration(labelText: '宗教形式・宗派'),
            ),
            _gap,
          ],
          if (kind == PersonKind.contact) ...[
            TextFormField(
              controller: addressAs,
              decoration: const InputDecoration(labelText: 'どう呼べばよいか'),
            ),
            _gap,
            TextFormField(
              controller: lastMet,
              decoration: const InputDecoration(labelText: '最後に会った場面'),
            ),
            _gap,
          ],
          TextFormField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '電話番号（任意）'),
          ),
          _gap,
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'メールアドレス（任意）'),
          ),
          _gap,
          TextFormField(
            controller: address,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '住所（任意）'),
          ),
          _gap,
          TextFormField(
            controller: notes,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '話題・注意事項・メモ'),
          ),
          _gap,
          if (life == LifeStatus.living)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: (value) => setState(() => consent = value ?? false),
              title: const Text('本人へ登録内容を説明し、了承を確認した'),
              subtitle: const Text('電話・メール・LINE等の登録は必要最小限にしてください。'),
            ),
          GlassCard(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('マイナンバー、口座・カード、パスワード、不要な医療情報は入力しないでください。'),
            ),
          ),
          _gap,
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存する'),
          ),
        ],
      ),
    ),
  );
  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    if (life == LifeStatus.living && !consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('存命の方は、説明・了承確認にチェックしてから保存してください。')),
      );
      return;
    }
    final repo = RepositoryScope.of(context);
    final old = widget.person;
    try {
      await repo.savePerson(
        Person(
          id: old?.id ?? 'person-${DateTime.now().microsecondsSinceEpoch}',
          name: name.text.trim(),
          kana: kana.text.trim(),
          relationship: relation.text.trim(),
          kind: kind,
          lifeStatus: life,
          nickname: nickname.text.trim(),
          born: born.text.trim(),
          died: died.text.trim(),
          posthumousName: posthumous.text.trim(),
          religion: religion.text.trim(),
          lastMet: lastMet.text.trim(),
          howToAddress: addressAs.text.trim(),
          notes: notes.text.trim(),
          phone: phone.text.trim(),
          email: email.text.trim(),
          address: address.text.trim(),
          initials: name.text.trim().characters.first,
          placeIds: old?.placeIds ?? const [],
          consentConfirmed: consent,
          version: old?.version ?? 1,
          deceasedVersion: old?.deceasedVersion,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存できませんでした。内容と通信状態を確認してください。')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(repo.isDemo ? 'この起動中のデモデータへ保存しました。' : '家族の共有データへ保存しました。'),
      ),
    );
  }
}

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  String filter = 'すべて';
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final list = repo.confirmedEvents
        .where((e) => filter == 'すべて' || e.type == filter)
        .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageBody(
        children: [
          if (!repo.viewerMode)
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '届いた法要の案内状を撮影し、日時や会場を予定にできます。読み取り内容は確認してから保存します。',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InvitationCaptureScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('案内状を撮影して予定を作る'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: filter,
            decoration: const InputDecoration(labelText: '行事種別で絞り込む'),
            items: [
              'すべて',
              '法事・法要',
              '新盆・初盆',
              'お中元・お歳暮',
              '葬儀',
              '墓参り',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (value) => setState(() => filter = value!),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const _EmptyCard(
              icon: Icons.event_note_outlined,
              text: 'この条件の記録はありません',
              action: '別の種類を選ぶか、記録を追加してください',
            )
          else
            for (final e in list) EventCard(event: e),
        ],
      ),
      floatingActionButton: repo.viewerMode
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-event',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EventEditScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('記録を追加'),
            ),
    );
  }
}

class InvitationCaptureScreen extends StatefulWidget {
  const InvitationCaptureScreen({super.key});

  @override
  State<InvitationCaptureScreen> createState() =>
      _InvitationCaptureScreenState();
}

class _InvitationCaptureScreenState extends State<InvitationCaptureScreen> {
  final picker = ImagePicker();
  final title = TextEditingController(text: '法要のご案内');
  final date = TextEditingController();
  final time = TextEditingController();
  final place = TextEditingController();
  final memo = TextEditingController();
  XFile? photo;
  Future<Uint8List>? photoBytes;
  String? personId;
  bool reviewed = false;
  bool busy = false;

  @override
  void dispose() {
    for (final controller in [title, date, time, place, memo]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    final selected = await picker.pickImage(
      source: source,
      imageQuality: 92,
      requestFullMetadata: false,
    );
    if (selected == null || !mounted) return;
    setState(() {
      photo = selected;
      photoBytes = selected.readAsBytes();
      busy = true;
      reviewed = false;
    });
    try {
      if (invitationOcrSupported) {
        final text = await recognizeInvitation(selected.path);
        final draft = parseInvitationText(text);
        if (draft.date != null) date.text = _isoDate(draft.date!);
        if (draft.time != null) time.text = draft.time!;
        if (draft.place != null) place.text = draft.place!;
        if (text.trim().isEmpty) {
          _message('文字を読み取れませんでした。写真を見ながら入力してください。');
        } else {
          _message('読み取り候補を入力しました。日付・時刻・会場を写真と照合してください。');
        }
      } else {
        _message('この画面では自動読取に対応していません。写真を見ながら入力してください。');
      }
    } catch (_) {
      _message('文字を読み取れませんでした。写真を見ながら入力してください。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _isoDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final familyPeople = repo.people;
    personId ??= familyPeople.isEmpty ? null : familyPeople.first.id;
    return Scaffold(
      appBar: AppBar(title: const Text('法要案内状から予定を作る')),
      body: PageBody(
        children: [
          GlassCard(
            color: const Color(0xFFFFF4D6),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '案内状には氏名・住所が含まれる場合があります。読み取りは端末内で行い、保存する前に候補を確認してください。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (photo != null)
            FutureBuilder<Uint8List>(
              future: photoBytes,
              builder: (context, snapshot) => snapshot.hasData
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(
                        snapshot.data!,
                        height: 190,
                        fit: BoxFit.cover,
                      ),
                    )
                  : snapshot.hasError
                  ? const SizedBox(
                      height: 90,
                      child: Center(child: Text('写真を読み込めませんでした。選び直してください。')),
                    )
                  : const GlassSkeleton(height: 190, radius: 18),
            )
          else
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F2),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Icon(
                  Icons.mail_outline_rounded,
                  size: 46,
                  color: Color(0xFFC65369),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => _capture(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('カメラで撮る'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('写真を選ぶ'),
              ),
              if (busy)
                Semantics(
                  label: '案内状を処理中',
                  liveRegion: true,
                  child: const GlassSkeleton(width: 96, height: 28),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (familyPeople.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: personId,
              decoration: const InputDecoration(labelText: '対象の故人 *'),
              items: familyPeople
                  .map(
                    (person) => DropdownMenuItem(
                      value: person.id,
                      child: Text('${person.name}（${person.relationship}）'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                personId = value;
                reviewed = false;
              }),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            onChanged: (_) => setState(() => reviewed = false),
            decoration: const InputDecoration(labelText: '予定名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: date,
            keyboardType: TextInputType.datetime,
            onChanged: (_) => setState(() => reviewed = false),
            decoration: const InputDecoration(
              labelText: '日付 *',
              hintText: '例：2027-05-18',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: time,
            onChanged: (_) => setState(() => reviewed = false),
            decoration: const InputDecoration(
              labelText: '時刻（任意）',
              hintText: '例：10:30',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: place,
            maxLines: 2,
            onChanged: (_) => setState(() => reviewed = false),
            decoration: const InputDecoration(labelText: '会場・住所（任意）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: memo,
            maxLines: 3,
            onChanged: (_) => setState(() => reviewed = false),
            decoration: const InputDecoration(labelText: 'メモ（任意）'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: reviewed,
            title: const Text('写真と照合し、予定内容を確認しました'),
            onChanged: (value) => setState(() => reviewed = value ?? false),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy || !reviewed ? null : () => _save(repo),
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('確認した内容で予定に保存'),
          ),
          const SizedBox(height: 12),
          const Text(
            '予定日時は日付として登録されます。時刻・会場は予定のメモに保存されます。通知は端末設定で有効にしてください。',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _save(FamilyRepository repo) async {
    final parsedDate = DateTime.tryParse(date.text.trim());
    if (photo == null ||
        parsedDate == null ||
        personId == null ||
        title.text.trim().isEmpty) {
      _message('写真・対象の故人・予定名・日付を確認してください。日付はYYYY-MM-DD形式です。');
      return;
    }
    setState(() => busy = true);
    final notes = [
      if (time.text.trim().isNotEmpty) '時刻：${time.text.trim()}',
      if (place.text.trim().isNotEmpty) '会場：${place.text.trim()}',
      if (memo.text.trim().isNotEmpty) memo.text.trim(),
      '招待状の写真から入力。原本と照合済み。',
    ].join('\n');
    final event = MemorialEvent(
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      title: title.text.trim(),
      type: '法事・法要',
      subjectPersonId: personId!,
      status: EventStatus.planned,
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      notes: notes,
    );
    late final String savedEventId;
    try {
      savedEventId = await repo.saveNewEvent(event);
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      _message('予定を保存できませんでした。通信状態と入力内容を確認してください。');
      return;
    }

    var attachmentSaved = repo.isDemo;
    var reminderSyncSucceeded = repo.isDemo;
    if (!repo.isDemo) {
      try {
        await repo.addImageAttachment(
          targetType: AttachmentTargetType.event,
          targetId: savedEventId,
          sourceBytes: await photo!.readAsBytes(),
          caption: '法要案内状',
        );
        attachmentSaved = true;
      } catch (_) {
        attachmentSaved = false;
      }
      try {
        await LocalReminderService.instance.sync(repo.confirmedEvents);
        reminderSyncSucceeded = true;
      } catch (_) {
        reminderSyncSucceeded = false;
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    final message = repo.isDemo
        ? 'デモの予定に追加しました。写真はデモ環境には保存していません。'
        : !attachmentSaved
        ? '予定は保存しましたが写真を添付できませんでした。予定詳細から写真を追加してください。'
        : !reminderSyncSucceeded
        ? '予定と写真を保存しました。通知を同期できなかったため端末設定を確認してください。'
        : '予定と案内状の写真を保存しました。';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class PreviousRecordsScreen extends StatelessWidget {
  const PreviousRecordsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('前回どうした？')),
      body: PageBody(
        children: [
          const Text('対象の故人・相手を選ぶと、会場、費用、参加者をまとめて確認できます。'),
          _gap,
          for (final p in repo.people.where(
            (p) => repo.confirmedEvents.any((e) => e.subjectPersonId == p.id),
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                child: ExpansionTile(
                  leading: PersonAvatar(p),
                  title: Text(p.name),
                  subtitle: Text(p.relationship),
                  children: [
                    for (final e in repo.confirmedEvents.where(
                      (e) => e.subjectPersonId == p.id,
                    ))
                      ListTile(
                        title: Text(e.title),
                        subtitle: Text(
                          '${dateLabel(e.date)} ・ ${yen(e.total)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EventDetailScreen(eventId: e.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final e = repo.events.firstWhere((x) => x.id == eventId);
    final p = repo.person(e.subjectPersonId);
    final place = repo.place(e.placeId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('記録の詳細'),
        actions: [
          if (!repo.viewerMode)
            IconButton(
              tooltip: '編集',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EventEditScreen(event: e)),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: PageBody(
        children: [
          Wrap(
            spacing: 8,
            children: [
              _StatusChip(e.status),
              Chip(label: Text(e.type)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            e.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text('${p.name} ・ ${dateLabel(e.date)}'),
          const SizedBox(height: 14),
          _DetailBlock(
            title: '概要',
            rows: {
              '対象': p.name,
              '日付': dateLabel(e.date),
              if (place != null) '会場': place.name,
              if (e.host.isNotEmpty) '施主・担当': e.host,
              if (e.notes.isNotEmpty) '当日の記録': e.notes,
            },
          ),
          _DetailBlock(
            title: '費用',
            rows: {
              for (final x in e.expenses)
                x.label: x.amount == null
                    ? '未入力'
                    : '${yen(x.amount!)}${x.payer.isEmpty ? '' : '（${x.payer}）'}',
              '合計': yen(e.total),
            },
          ),
          _DetailBlock(
            title: '参加者 ${e.participants.length}名',
            rows: {
              for (final x in e.participants)
                x.name: '${x.relationshipAtTime} ・ ${x.attendance ?? '出欠未入力'}',
            },
          ),
          if (e.nextMemo.isNotEmpty)
            _DetailBlock(title: '次回への申し送り', rows: {'メモ': e.nextMemo}),
          if (place != null) ...[
            const SectionTitle('場所'),
            PlaceCard(place: place),
          ],
          AttachmentSection(
            repository: repo,
            targetType: AttachmentTargetType.event,
            targetId: e.id,
          ),
          const SizedBox(height: 14),
          if (!repo.viewerMode && e.status == EventStatus.completed)
            OutlinedButton.icon(
              onPressed: () => _duplicate(context, repo, e),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('前回をもとに次回準備を作る'),
            ),
          const SizedBox(height: 8),
          const Text('複製しても、日付・金額・出欠・添付は引き継ぎません。', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _duplicate(
    BuildContext context,
    FamilyRepository repo,
    MemorialEvent source,
  ) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('次回準備を作りますか？'),
            content: const Text(
              '会場、費用の項目名、参加者名、申し送りだけを引き継ぎます。日付、金額、出欠、添付は空になります。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('下書きを作る'),
              ),
            ],
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      final copy = await repo.duplicateSafely(source);
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EventEditScreen(event: copy)),
      );
    }
  }
}

class EventEditScreen extends StatefulWidget {
  const EventEditScreen({super.key, this.event});
  final MemorialEvent? event;
  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen> {
  final keyForm = GlobalKey<FormState>();
  late TextEditingController title;
  late TextEditingController date;
  late TextEditingController host;
  late TextEditingController notes;
  late TextEditingController memo;
  late String type;
  late String personId;
  String? placeId;
  late EventStatus status;
  late bool isCandidate;
  late List<Expense> expenses;
  late List<EventParticipant> participants;
  @override
  void initState() {
    super.initState();
    final e = widget.event;
    title = TextEditingController(text: e?.title);
    date = TextEditingController(
      text: e?.date == null
          ? ''
          : '${e!.date!.year}-${e.date!.month.toString().padLeft(2, '0')}-${e.date!.day.toString().padLeft(2, '0')}',
    );
    host = TextEditingController(text: e?.host);
    notes = TextEditingController(text: e?.notes);
    memo = TextEditingController(text: e?.nextMemo);
    type = e?.type ?? '法事・法要';
    personId = e?.subjectPersonId ?? 'father';
    placeId = e?.placeId;
    status = e?.status ?? EventStatus.planned;
    isCandidate = e?.isCandidate ?? false;
    expenses =
        e?.expenses
            .map(
              (item) => Expense(
                label: item.label,
                amount: item.amount,
                payer: item.payer,
              ),
            )
            .toList() ??
        [];
    participants =
        e?.participants
            .map(
              (item) => EventParticipant(
                name: item.name,
                relationshipAtTime: item.relationshipAtTime,
                attendance: item.attendance,
              ),
            )
            .toList() ??
        [];
  }

  @override
  void dispose() {
    for (final c in [title, date, host, notes, memo]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    if (repo.people.isNotEmpty &&
        !repo.people.any((person) => person.id == personId)) {
      personId = repo.people.first.id;
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.event == null ? '記録を追加' : '記録を編集')),
      body: Form(
        key: keyForm,
        child: PageBody(
          children: [
            if (repo.people.isEmpty) ...[
              const _EmptyCard(
                icon: Icons.person_add_alt_1_outlined,
                text: '先に人物を登録してください',
                action: '記録には対象となる故人または相手が必要です。',
              ),
              _gap,
            ],
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: '種類 *'),
              items: [
                '通夜',
                '葬儀',
                '法事・法要',
                '新盆・初盆',
                'お盆',
                'お彼岸',
                '墓参り',
                'お中元・お歳暮',
                '返礼',
                'その他',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => type = v!),
            ),
            _gap,
            TextFormField(
              controller: title,
              decoration: const InputDecoration(labelText: '記録名 *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '記録名を入力してください' : null,
            ),
            _gap,
            if (repo.people.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: personId,
                decoration: const InputDecoration(labelText: '対象の故人・相手 *'),
                items: repo.people
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.name}（${p.relationship}）'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => personId = v!),
              ),
            _gap,
            DropdownButtonFormField<EventStatus>(
              initialValue: status,
              decoration: const InputDecoration(labelText: '状態'),
              items: const [
                DropdownMenuItem(value: EventStatus.planned, child: Text('予定')),
                DropdownMenuItem(
                  value: EventStatus.completed,
                  child: Text('実施済み'),
                ),
                DropdownMenuItem(
                  value: EventStatus.cancelled,
                  child: Text('中止'),
                ),
              ],
              onChanged: (v) => setState(() => status = v!),
            ),
            if (status == EventStatus.planned) ...[
              _gap,
              CheckboxListTile(
                value: isCandidate,
                contentPadding: EdgeInsets.zero,
                title: const Text('確認が必要な法要候補として保存'),
                subtitle: const Text('寺院・地域・ご家庭の慣習を確認後に、確定予定へ変更します。'),
                onChanged: (value) =>
                    setState(() => isCandidate = value ?? false),
              ),
            ],
            _gap,
            TextFormField(
              controller: date,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: '日付',
                hintText: '例：2027-05-18',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                return DateTime.tryParse(v) == null
                    ? 'YYYY-MM-DD形式で入力してください'
                    : null;
              },
            ),
            _gap,
            DropdownButtonFormField<String?>(
              initialValue: placeId,
              decoration: const InputDecoration(labelText: '主な場所'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('未設定'),
                ),
                ...repo.places.map(
                  (p) => DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(p.name),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => placeId = v),
            ),
            _gap,
            TextFormField(
              controller: host,
              decoration: const InputDecoration(labelText: '施主・担当者'),
            ),
            _gap,
            TextFormField(
              controller: notes,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '概要・当日のメモ'),
            ),
            _gap,
            TextFormField(
              controller: memo,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '次回への申し送り'),
            ),
            _gap,
            const SectionTitle('費用'),
            for (var index = 0; index < expenses.length; index++)
              GlassCard(
                key: ObjectKey(expenses[index]),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      TextFormField(
                        initialValue: expenses[index].label,
                        decoration: const InputDecoration(
                          labelText: '用途',
                          hintText: 'お布施・御車代・会食など',
                        ),
                        onChanged: (value) => expenses[index].label = value,
                      ),
                      _gap,
                      TextFormField(
                        initialValue: expenses[index].amount?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '金額（円）',
                          hintText: '未確定なら空欄',
                        ),
                        onChanged: (value) =>
                            expenses[index].amount = int.tryParse(value),
                      ),
                      _gap,
                      TextFormField(
                        initialValue: expenses[index].payer,
                        decoration: const InputDecoration(labelText: '支払者・受取人'),
                        onChanged: (value) => expenses[index].payer = value,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => expenses.removeAt(index)),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('この費用を削除'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(
                () => expenses.add(Expense(label: 'お布施', amount: null)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('費用を追加'),
            ),
            const SectionTitle('参加者・関係者'),
            for (var index = 0; index < participants.length; index++)
              GlassCard(
                key: ObjectKey(participants[index]),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      TextFormField(
                        initialValue: participants[index].name,
                        decoration: const InputDecoration(labelText: '氏名・呼び名'),
                        onChanged: (value) => participants[index].name = value,
                      ),
                      _gap,
                      TextFormField(
                        initialValue: participants[index].relationshipAtTime,
                        decoration: const InputDecoration(
                          labelText: 'その当時の故人との関係',
                          hintText: '例：父の従兄',
                        ),
                        onChanged: (value) =>
                            participants[index].relationshipAtTime = value,
                      ),
                      _gap,
                      DropdownButtonFormField<String>(
                        initialValue: participants[index].attendance ?? '未回答',
                        decoration: const InputDecoration(labelText: '出欠'),
                        items: const ['招待', '出席予定', '出席', '欠席', '未回答']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            participants[index].attendance = value,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => participants.removeAt(index)),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('この人を削除'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(
                () => participants.add(
                  EventParticipant(name: '', relationshipAtTime: ''),
                ),
              ),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('参加者を追加'),
            ),
            _gap,
            if (status == EventStatus.planned)
              GlassCard(
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notifications_none),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('確定予定の通知候補：30日前・7日前。通知本文には人物名や行事名を表示しません。'),
                      ),
                    ],
                  ),
                ),
              ),
            _gap,
            FilledButton.icon(
              onPressed: repo.people.isEmpty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存する'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!keyForm.currentState!.validate()) return;
    final repo = RepositoryScope.of(context);
    final old = widget.event;
    final event = MemorialEvent(
      id: old?.id ?? 'event-${DateTime.now().microsecondsSinceEpoch}',
      title: title.text.trim(),
      type: type,
      subjectPersonId: personId,
      status: status,
      isCandidate: isCandidate,
      date: date.text.isEmpty ? null : DateTime.tryParse(date.text),
      placeId: placeId,
      host: host.text.trim(),
      notes: notes.text.trim(),
      nextMemo: memo.text.trim(),
      expenses: expenses
          .where((item) => item.label.trim().isNotEmpty)
          .map(
            (item) => Expense(
              label: item.label.trim(),
              amount: item.amount,
              payer: item.payer.trim(),
            ),
          )
          .toList(),
      participants: participants
          .where((item) => item.name.trim().isNotEmpty)
          .map(
            (item) => EventParticipant(
              name: item.name.trim(),
              relationshipAtTime: item.relationshipAtTime.trim(),
              attendance: item.attendance,
            ),
          )
          .toList(),
      notificationDays: old?.notificationDays ?? const [30, 7],
      version: old?.version ?? 1,
    );
    try {
      await repo.saveEvent(event);
      try {
        await LocalReminderService.instance.sync(repo.confirmedEvents);
      } catch (_) {
        // The event is already saved. Notification retry is independent.
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存できませんでした。内容と通信状態を確認してください。')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(repo.isDemo ? 'この起動中のデモデータへ保存しました。' : '家族の共有データへ保存しました。'),
      ),
    );
  }
}

class PlaceCard extends StatelessWidget {
  const PlaceCard({super.key, required this.place});
  final MemoryPlace place;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassCard(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: place)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(place.type),
                    if (place.section.isNotEmpty) Text(place.section),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlaceDetailScreen extends StatelessWidget {
  const PlaceDetailScreen({super.key, required this.place});
  final MemoryPlace place;
  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('場所の詳細'),
        actions: [
          if (!repo.viewerMode)
            IconButton(
              tooltip: '編集',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaceEditScreen(place: place),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: PageBody(
        children: [
          Icon(
            Icons.place,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          Text(
            place.name,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(place.type, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          _DetailBlock(
            title: '所在地と目印',
            rows: {
              '住所': place.address.isEmpty ? '未登録' : place.address,
              if (place.section.isNotEmpty) '区画・列・番号': place.section,
              if (place.landmark.isNotEmpty) '目印': place.landmark,
              if (place.directions.isNotEmpty) '入口からの行き方': place.directions,
            },
          ),
          if (place.mapUrl.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _openExternalMap(context, place.mapUrl),
              icon: const Icon(Icons.map_outlined),
              label: const Text('外部地図を開く'),
            ),
          AttachmentSection(
            repository: repo,
            targetType: AttachmentTargetType.place,
            targetId: place.id,
          ),
        ],
      ),
    );
  }
}

class PlaceEditScreen extends StatefulWidget {
  const PlaceEditScreen({super.key, this.place});

  final MemoryPlace? place;

  @override
  State<PlaceEditScreen> createState() => _PlaceEditScreenState();
}

class _PlaceEditScreenState extends State<PlaceEditScreen> {
  static const placeTypes = [
    '亡くなった場所',
    '霊園・墓地',
    '墓所・墓石',
    '納骨堂',
    '仏壇・位牌保管場所',
    '遺骨保管場所',
    '寺院',
    '葬儀会場',
    '法要会場',
    '会食会場',
    '自宅',
    'その他',
  ];

  final formKey = GlobalKey<FormState>();
  late String type;
  late TextEditingController name;
  late TextEditingController address;
  late TextEditingController section;
  late TextEditingController landmark;
  late TextEditingController directions;
  late TextEditingController mapUrl;
  String? relatedPersonId;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final place = widget.place;
    type = placeTypes.contains(place?.type) ? place!.type : 'その他';
    name = TextEditingController(text: place?.name);
    address = TextEditingController(text: place?.address);
    section = TextEditingController(text: place?.section);
    landmark = TextEditingController(text: place?.landmark);
    directions = TextEditingController(text: place?.directions);
    mapUrl = TextEditingController(text: place?.mapUrl);
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      address,
      section,
      landmark,
      directions,
      mapUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final relatedPeople = [...repo.people]
      ..sort((a, b) {
        final life = a.lifeStatus == LifeStatus.deceased ? -1 : 1;
        final otherLife = b.lifeStatus == LifeStatus.deceased ? -1 : 1;
        return life == otherLife ? a.name.compareTo(b.name) : life - otherLife;
      });
    return Scaffold(
      appBar: AppBar(title: Text(widget.place == null ? '場所を追加' : '場所を編集')),
      body: Form(
        key: formKey,
        child: PageBody(
          children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: '場所の種類 *'),
              items: placeTypes
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => type = value!),
            ),
            _gap,
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称 *'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '名称を入力してください' : null,
            ),
            _gap,
            TextFormField(
              controller: address,
              decoration: const InputDecoration(labelText: '住所'),
            ),
            _gap,
            TextFormField(
              controller: section,
              decoration: const InputDecoration(
                labelText: '区画・列・番号',
                hintText: 'やすらぎ区 B列 12番',
              ),
            ),
            _gap,
            TextFormField(
              controller: landmark,
              decoration: const InputDecoration(labelText: '入口・駐車場・目印'),
              maxLines: 2,
            ),
            _gap,
            TextFormField(
              controller: directions,
              decoration: const InputDecoration(labelText: '現地での行き方メモ'),
              maxLines: 3,
            ),
            _gap,
            TextFormField(
              controller: mapUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '外部地図URL',
                hintText: 'https://...',
              ),
              validator: (value) {
                final normalized = value?.trim() ?? '';
                if (normalized.isNotEmpty &&
                    !normalized.startsWith('https://')) {
                  return 'https:// から始まるURLを入力してください';
                }
                return null;
              },
            ),
            _gap,
            DropdownButtonFormField<String?>(
              initialValue: relatedPersonId,
              decoration: const InputDecoration(labelText: '関連する人物・故人'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('指定なし'),
                ),
                ...relatedPeople.map(
                  (person) => DropdownMenuItem<String?>(
                    value: person.id,
                    child: Text('${person.name}（${person.relationship}）'),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => relatedPersonId = value),
            ),
            const SizedBox(height: 6),
            const Text('位置情報は常時取得しません。住所・区画・地図URLだけを保存します。'),
            _gap,
            FilledButton.icon(
              onPressed: saving ? null : () => _save(repo),
              icon: const Icon(Icons.save_outlined),
              label: Text(saving ? '保存中…' : '保存する'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(FamilyRepository repo) async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final old = widget.place;
    try {
      await repo.savePlace(
        MemoryPlace(
          id: old?.id ?? 'place-${DateTime.now().microsecondsSinceEpoch}',
          name: name.text.trim(),
          type: type,
          address: address.text.trim(),
          section: section.text.trim(),
          landmark: landmark.text.trim(),
          directions: directions.text.trim(),
          mapUrl: mapUrl.text.trim(),
          version: old?.version ?? 1,
        ),
        relatedPersonId: relatedPersonId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            repo.isDemo ? 'デモデータへ場所を保存しました。' : '家族の共有データへ場所を保存しました。',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存できませんでした。内容と通信状態を確認してください。')),
      );
    }
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notificationsEnabled = false;
  bool notificationBusy = true;
  bool lifecycleBusy = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationState();
  }

  Future<void> _loadNotificationState() async {
    final enabled = await LocalReminderService.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      notificationsEnabled = enabled;
      notificationBusy = false;
    });
    if (enabled) {
      try {
        await LocalReminderService.instance.sync(
          RepositoryScope.of(context).confirmedEvents,
        );
      } catch (_) {
        // Keep the saved preference. The user can retry from this screen.
      }
    }
  }

  Future<void> _setNotifications(
    bool value,
    FamilyRepository repository,
  ) async {
    setState(() => notificationBusy = true);
    bool enabled;
    try {
      enabled = await LocalReminderService.instance.setEnabled(
        value,
        repository.confirmedEvents,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => notificationBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知を設定できませんでした。端末設定を確認して再試行してください。')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      notificationsEnabled = enabled;
      notificationBusy = false;
    });
    if (value && !enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端末の通知が許可されていません。OSの設定を確認してください。')),
      );
    }
  }

  Future<void> _exportData(FamilyRepository repository) async {
    final format = await showDialog<FamilyExportFormat>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('家族データを出力'),
        content: const Text(
          '氏名、住所、戒名、連絡先、金額などを含みます。'
          '共有端末やクラウドの共有フォルダには保存しないでください。'
          '写真本体は含みません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, FamilyExportFormat.csv),
            child: const Text('CSV'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, FamilyExportFormat.json),
            child: const Text('JSON'),
          ),
        ],
      ),
    );
    if (format == null) return;
    setState(() => lifecycleBusy = true);
    try {
      final export = await repository.exportFamilyData(format);
      await FileSaver.instance.saveAs(
        name: export.fileName,
        bytes: export.bytes,
        fileExtension: export.extension,
        mimeType: format == FamilyExportFormat.json
            ? MimeType.json
            : MimeType.csv,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('家族データを出力しました。')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('出力できませんでした。ownerで再度お試しください。')),
      );
    } finally {
      if (mounted) setState(() => lifecycleBusy = false);
    }
  }

  Future<void> _requestDeletion(
    FamilyRepository repository, {
    required bool wholeFamily,
  }) async {
    final target = wholeFamily ? '家族スペース全体' : 'このアカウント';
    final firstConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$targetの削除'),
        content: Text(
          wholeFamily
              ? '家族の全記録と添付ファイルが対象です。依頼後すぐに家族全員が利用できなくなり、30日後に完全削除します。'
              : 'アカウントをすぐに利用停止し、30日後に完全削除します。最後のownerは、先に別の家族へownerを移す必要があります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('確認へ'),
          ),
        ],
      ),
    );
    if (firstConfirmed != true) return;

    setState(() => lifecycleBusy = true);
    try {
      if (!mounted) return;
      setState(() => lifecycleBusy = false);
      final finalConfirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('最終確認'),
          content: Text(
            '$targetを利用停止し、30日後に完全削除します。'
            '必要な場合は先にJSONまたはCSVを出力してください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('削除を依頼'),
            ),
          ],
        ),
      );
      if (finalConfirmed != true) return;
      setState(() => lifecycleBusy = true);
      if (wholeFamily) {
        await repository.requestFamilyDeletion();
      } else {
        await repository.requestAccountDeletion();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => lifecycleBusy = false);
      if (repository is CloudflareFamilyRepository &&
          (error.toString().contains('REAUTH_REQUIRED') ||
              error.toString().contains('REAUTHENTICATION_REQUIRED'))) {
        try {
          await repository.reauthenticateGoogle();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Googleで本人確認した後、削除操作をもう一度行ってください。')),
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Googleの本人確認を開始できませんでした。再試行してください。')),
          );
        }
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_deletionErrorMessage(error))));
    } finally {
      if (mounted) setState(() => lifecycleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('家族と設定')),
      body: PageBody(
        children: [
          const DemoBanner(),
          const SectionTitle('家族スペース'),
          _DetailBlock(
            title: repo.familyName,
            rows: {
              '中心人物': repo.people.isEmpty
                  ? '未登録'
                  : repo.person(repo.centerPersonId).name,
              'タイムゾーン': 'Asia/Tokyo',
              '接続状態': repo.isDemo ? 'デモ（共有なし）' : '家族の共有サーバー',
              '権限': repo.currentRole,
            },
          ),
          const SectionTitle('メンバー'),
          for (final m in repo.familyUsers)
            GlassCard(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(m.name),
                subtitle: Text('${m.role} ・ ${m.state}'),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: repo.isDemo || repo.currentRole != 'owner'
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FamilyManagementScreen(),
                    ),
                  ),
            icon: const Icon(Icons.person_add_alt),
            label: Text(
              repo.isDemo
                  ? '家族を招待（ログイン後）'
                  : repo.currentRole == 'owner'
                  ? '招待・承認・権限を管理'
                  : '招待管理はownerのみ',
            ),
          ),
          const SectionTitle('確認用モード'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: repo.viewerMode,
            onChanged: repo.setViewerMode,
            title: const Text('viewer表示を確認'),
            subtitle: const Text('編集ボタンを隠し、閲覧のみの家族の画面を確認します。'),
          ),
          const SectionTitle('場所'),
          if (!repo.viewerMode)
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaceEditScreen()),
              ),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('場所を追加'),
            ),
          const SizedBox(height: 8),
          for (final p in repo.places) PlaceCard(place: p),
          const SectionTitle('端末の通知'),
          if (notificationBusy)
            Semantics(
              label: '通知設定を確認中',
              liveRegion: true,
              child: const GlassSkeleton(height: 84),
            )
          else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: notificationsEnabled,
              onChanged:
                  notificationBusy || !LocalReminderService.instance.isSupported
                  ? null
                  : (value) => _setNotifications(value, repo),
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('確定予定を30日前・7日前に通知'),
              subtitle: Text(
                LocalReminderService.instance.isSupported
                    ? 'この端末だけに保存します。通知には人物名・行事名・住所・金額を表示しません。'
                    : 'Web版では端末通知を使用しません。Android / iPhone版で設定してください。',
              ),
            ),
          const SectionTitle('データと安全'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('JSON / CSV出力'),
            subtitle: const Text('owner限定・写真本体は含みません'),
            enabled:
                !repo.isDemo &&
                repo.currentRole == 'owner' &&
                !repo.viewerMode &&
                !lifecycleBusy,
            onTap: () => _exportData(repo),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('変更履歴'),
            subtitle: const Text('変更者・日時・対象だけを記録（本文は複製しません）'),
            enabled: !repo.isDemo && repo.currentRole == 'owner',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
            ),
          ),
          if (!repo.isDemo) ...[
            ListTile(
              leading: Icon(
                Icons.person_off_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('アカウントを削除'),
              subtitle: const Text('本人確認後に利用停止し、30日後に完全削除'),
              enabled: !repo.viewerMode && !lifecycleBusy,
              onTap: () => _requestDeletion(repo, wholeFamily: false),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('家族スペース全体を削除'),
              subtitle: Text(
                repo.currentRole == 'owner'
                    ? 'owner限定・家族全員の記録が対象'
                    : 'ownerだけが実行できます',
              ),
              enabled:
                  repo.currentRole == 'owner' &&
                  !repo.viewerMode &&
                  !lifecycleBusy,
              onTap: () => _requestDeletion(repo, wholeFamily: true),
            ),
          ],
          const SectionTitle('このβ版について'),
          const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '人物・記録・写真は、招待して承認した家族だけに共有します。AI補助は利用操作時に実行します。デモの追加内容はアプリ終了時に消えます。',
              ),
            ),
          ),
          if (!repo.isDemo)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('ログアウト'),
              onTap: () async {
                await repo.signOut();
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('変更履歴')),
      body: PageBody(
        children: [
          const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ownerだけが過去180日の操作を確認できます。'
                '本文・金額・連絡先は履歴に複製しません。',
              ),
            ),
          ),
          if (repo.activityEntries.isEmpty)
            const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('表示できる変更履歴はまだありません。'),
              ),
            )
          else
            for (final entry in repo.activityEntries)
              GlassCard(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.history_rounded),
                  ),
                  title: Text(
                    '${_activityActionLabel(entry.action)}・${_activityEntityLabel(entry.entityType)}',
                  ),
                  subtitle: Text(
                    '${entry.actorName}\n${dateLabel(entry.occurredAt)} '
                    '${entry.occurredAt.hour.toString().padLeft(2, '0')}:'
                    '${entry.occurredAt.minute.toString().padLeft(2, '0')}',
                  ),
                  isThreeLine: true,
                ),
              ),
        ],
      ),
    );
  }
}

class FamilyManagementScreen extends StatefulWidget {
  const FamilyManagementScreen({super.key});

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen> {
  String? busyId;
  String? error;

  Future<void> _createInvitation(FamilyRepository repo) async {
    final request = await showDialog<_InvitationRequest>(
      context: context,
      builder: (_) => const _InvitationDialog(),
    );
    if (request == null) return;
    setState(() {
      busyId = 'create';
      error = null;
    });
    try {
      final secret = await repo.createInvitation(request.email, request.role);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('招待コードを作成しました'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('24時間・1回限りです。招待した本人へ安全な方法で伝えてください。'),
              const SizedBox(height: 16),
              SelectableText(
                secret.shortCode,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text('承諾後も、この画面で表示名を確認して承認するまでデータは見えません。'),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret.shortCode));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('招待コードをコピーしました')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('コードをコピー'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => error = '招待を作成できませんでした。通信状態と入力内容を確認してください。');
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      busyId = id;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => error = '処理できませんでした。最新状態を確認して再試行してください。');
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final pending = repo.invitations.where((item) => item.status == 'accepted');
    final activeInvites = repo.invitations.where(
      (item) => item.status == 'active',
    );
    return Scaffold(
      appBar: AppBar(title: const Text('家族の招待と権限')),
      body: PageBody(
        children: [
          const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '招待先メールとログインメールが一致した人だけが承諾できます。承諾後はownerが表示名を確認して正式参加を承認します。',
              ),
            ),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton.icon(
            onPressed: busyId == null ? () => _createInvitation(repo) : null,
            icon: const Icon(Icons.person_add_alt),
            label: Text(busyId == 'create' ? '作成中…' : '家族を招待'),
          ),
          const SectionTitle('承認待ち'),
          if (pending.isEmpty) const Text('承認待ちの家族はいません。'),
          for (final invitation in pending)
            GlassCard(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_search)),
                title: Text(
                  invitation.acceptedDisplayName.isEmpty
                      ? '表示名を取得できません'
                      : invitation.acceptedDisplayName,
                ),
                subtitle: Text('希望権限: ${_roleLabel(invitation.role)}'),
                trailing: FilledButton(
                  onPressed: busyId == null
                      ? () => _run(
                          invitation.id,
                          () => repo.approveInvitation(invitation.id),
                        )
                      : null,
                  child: Text(busyId == invitation.id ? '処理中…' : '承認'),
                ),
              ),
            ),
          const SectionTitle('発行中の招待'),
          if (activeInvites.isEmpty) const Text('発行中の招待はありません。'),
          for (final invitation in activeInvites)
            GlassCard(
              child: ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: Text('${_roleLabel(invitation.role)}として招待'),
                subtitle: Text(
                  '${invitation.expiresAt.toLocal().month}月${invitation.expiresAt.toLocal().day}日 '
                  '${invitation.expiresAt.toLocal().hour.toString().padLeft(2, '0')}:'
                  '${invitation.expiresAt.toLocal().minute.toString().padLeft(2, '0')}まで',
                ),
                trailing: TextButton(
                  onPressed: busyId == null
                      ? () => _run(
                          invitation.id,
                          () => repo.revokeInvitation(invitation.id),
                        )
                      : null,
                  child: const Text('取り消す'),
                ),
              ),
            ),
          const SectionTitle('参加中の家族'),
          for (final member in repo.familyUsers)
            GlassCard(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(
                  member.id == repo.currentUserId
                      ? '${member.name}（あなた）'
                      : member.name,
                ),
                subtitle: Text('${_roleLabel(member.role)} ・ ${member.state}'),
                trailing:
                    member.id == repo.currentUserId || member.state != '参加中'
                    ? null
                    : PopupMenuButton<String>(
                        enabled: busyId == null,
                        tooltip: '権限を変更',
                        onSelected: (role) => _run(
                          member.id,
                          () => repo.changeMemberRole(member.id, role),
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'owner',
                            child: Text('ownerにする'),
                          ),
                          PopupMenuItem(value: 'editor', child: Text('編集できる')),
                          PopupMenuItem(value: 'viewer', child: Text('閲覧のみ')),
                        ],
                      ),
              ),
            ),
          const SizedBox(height: 12),
          const Text('最後のownerは権限移譲または家族全体削除までownerから変更できません。'),
        ],
      ),
    );
  }
}

class _InvitationRequest {
  const _InvitationRequest(this.email, this.role);
  final String email;
  final String role;
}

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog();

  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  final email = TextEditingController();
  String role = 'editor';
  String? error;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('家族を招待'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '招待先メールアドレス'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(labelText: '参加後の権限'),
          items: const [
            DropdownMenuItem(value: 'editor', child: Text('編集できる')),
            DropdownMenuItem(value: 'viewer', child: Text('閲覧のみ')),
          ],
          onChanged: (value) => setState(() => role = value ?? 'editor'),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: () {
          final value = email.text.trim().toLowerCase();
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
            setState(() => error = 'メールアドレスを確認してください。');
            return;
          }
          Navigator.pop(context, _InvitationRequest(value, role));
        },
        child: const Text('招待コードを作る'),
      ),
    ],
  );
}

String _roleLabel(String role) => switch (role) {
  'owner' => 'owner（管理者）',
  'editor' => 'editor（編集可）',
  'viewer' => 'viewer（閲覧のみ）',
  _ => role,
};

String _deletionErrorMessage(Object error) {
  final text = error.toString();
  if (text.contains('OWNER_TRANSFER_REQUIRED')) {
    return '最後のownerはアカウントを削除できません。先に別の家族へowner権限を移してください。';
  }
  if (text.contains('REAUTHENTICATION_REQUIRED') ||
      text.contains('REAUTH_REQUIRED') ||
      text.contains('Token')) {
    return 'Googleでの本人確認が必要です。ログイン状態を確認して再試行してください。';
  }
  return '削除を依頼できませんでした。通信状態を確認して再試行してください。';
}

String _activityActionLabel(String action) => switch (action) {
  'insert' => '追加',
  'update' => '更新',
  'soft_delete' => 'ごみ箱へ移動',
  'restore' => '復元',
  'invite' => '招待',
  'approve' => '承認',
  'revoke' => '招待取消',
  'export' => 'データ出力',
  'account_deletion_requested' => 'アカウント削除依頼',
  'family_deletion_requested' => '家族全体削除依頼',
  _ => '操作',
};

String _activityEntityLabel(String entity) => switch (entity) {
  'people' => '人物',
  'deceased_profiles' => '故人情報',
  'person_relationships' => '家族関係',
  'places' => '場所',
  'person_places' => '人物と場所',
  'events' => '行事',
  'event_attendees' => '参加者',
  'event_expenses' => '費用',
  'gift_records' => '贈答',
  'attachments' => '添付',
  'family_members' => '家族メンバー',
  'family_invitations' => '家族招待',
  'export_jobs' => 'データ出力',
  'deletion_jobs' => '削除',
  _ => '家族データ',
};

Future<void> _openExternalMap(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('外部地図を開けませんでした。URLを確認してください。')),
    );
    return;
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('外部地図を開けませんでした。URLを確認してください。')),
    );
  }
}
