import 'package:common_dart/common_dart.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

const double kExpandedHeight = 180;

const List<(String, String, String)> kLanguages = [
  ('🌐', 'Original', ''),
  ('🇬🇧', 'English', 'en'),
  ('🇷🇺', 'Russian', 'ru'),
  ('🇨🇿', 'Czech', 'cs'),
  ('🇺🇦', 'Ukrainian', 'uk'),
  ('🇵🇱', 'Polish', 'pl'),
];

class MenuSliverAppBar extends StatelessWidget {
  final String restaurantUrl;
  final RestaurantPreviewInfo previewInfo;
  final RestaurantInfo? restaurantInfo;
  final String selectedLanguage;
  final String selectedCurrency;
  final List<String> currencyOptions;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onCurrencyChanged;

  const MenuSliverAppBar({
    super.key,
    required this.restaurantUrl,
    required this.previewInfo,
    required this.restaurantInfo,
    required this.selectedLanguage,
    required this.selectedCurrency,
    required this.currencyOptions,
    required this.onLanguageChanged,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final name = restaurantInfo?.name ?? previewInfo.name ?? _hostFromUrl(restaurantUrl);
    final iconUrl = previewInfo.iconUrl ?? restaurantInfo?.iconUrl;

    return SliverAppBar(
      expandedHeight: kExpandedHeight,
      pinned: true,
      stretch: true,
      title: Row(
        children: [
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ShadSelect<String>(
            initialValue: selectedLanguage,
            onChanged: (v) {
              if (v != null) onLanguageChanged(v);
            },
            options: kLanguages.map((l) => ShadOption(value: l.$3, child: Text('${l.$1} ${l.$2}'))).toList(),
            selectedOptionBuilder: (context, value) {
              final lang = kLanguages.firstWhere((l) => l.$3 == value, orElse: () => kLanguages.first);
              return Text('${lang.$1} ${lang.$2}');
            },
          ),
          const SizedBox(width: 4),
          ShadSelect<String>(
            initialValue: selectedCurrency,
            onChanged: (v) {
              if (v != null) onCurrencyChanged(v);
            },
            options: [const ShadOption(value: '', child: Text('🌐 Original')), ...currencyOptions.map((c) => ShadOption(value: c, child: Text(c)))],
            selectedOptionBuilder: (context, value) => Text(value.isEmpty ? '🌐 Original' : value),
          ),
        ],
      ),
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _ExpandedBackground(name: name, iconUrl: iconUrl, url: restaurantUrl, restaurantInfo: restaurantInfo),
      ),
    );
  }

  static String _hostFromUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    final parts = host.split('.').where((p) => p != 'www').toList();
    return parts.isNotEmpty ? parts.first : host;
  }
}

class _ExpandedBackground extends StatelessWidget {
  final String name;
  final String? iconUrl;
  final RestaurantInfo? restaurantInfo;
  final String url;

  const _ExpandedBackground({required this.name, required this.url, required this.iconUrl, required this.restaurantInfo});

  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  /// Groups consecutive days with identical hours into ranges.
  /// e.g. Mon 9-21, Tue 9-21, Wed 9-21, Thu 12-20 → "Mon–Wed 9:00–21:00, Thu 12:00–20:00"
  static String _formatHours(List<DaySchedule> hours) {
    if (hours.isEmpty) return '';
    // Sort by day
    final sorted = [...hours]..sort((a, b) => a.day.compareTo(b.day));

    final groups = <({int first, int last, String? open, String? close})>[];
    for (final d in sorted) {
      if (groups.isNotEmpty && groups.last.open == d.open && groups.last.close == d.close && groups.last.last == d.day - 1) {
        final g = groups.removeLast();
        groups.add((first: g.first, last: d.day, open: g.open, close: g.close));
      } else {
        groups.add((first: d.day, last: d.day, open: d.open, close: d.close));
      }
    }

    return groups
        .map((g) {
          final days = g.first == g.last ? _dayNames[g.first] : '${_dayNames[g.first]}–${_dayNames[g.last]}';
          final time = '${g.open ?? '?'}–${g.close ?? '?'}';
          return '$days $time';
        })
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final info = restaurantInfo;
    final appBarHeight = Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight;

    return Container(
      color: colorScheme.surface,
      padding: EdgeInsets.fromLTRB(16, appBarHeight + 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + icon + controls row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (iconUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    iconUrl!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.restaurant, color: colorScheme.onSurfaceVariant),
                        ),
                  ),
                ),
            ],
          ),
          // Info lines
          if (info != null) ...[
            if (info.address != null) ...[const SizedBox(height: 8), _InfoLine(icon: Icons.location_on_outlined, text: info.address!)],
            if (info.phones.isNotEmpty) ...[const SizedBox(height: 4), _InfoLine(icon: Icons.phone_outlined, text: info.phones.join(', '))],
            if (info.workingHours.isNotEmpty) ...[
              const SizedBox(height: 4),
              _InfoLine(icon: Icons.access_time_outlined, text: _formatHours(info.workingHours)),
            ],
            ...[const SizedBox(height: 4), _InfoLine(icon: Icons.link, text: Uri.parse(url).origin, url: url)],
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? url;

  const _InfoLine({required this.icon, required this.text, this.url});

  Future<void> _launchUrl() async {
    if (url == null) return;
    final uri = Uri.parse(url!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isLink = url != null && url!.isNotEmpty;

    Widget richText = RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(padding: const EdgeInsets.only(right: 6.0), child: Icon(icon, size: 16, color: theme.colorScheme.mutedForeground)),
          ),
          TextSpan(
            text: text,
            style: theme.textTheme.muted.copyWith(
              decoration: isLink ? TextDecoration.underline : TextDecoration.none,
              color: isLink ? theme.colorScheme.primary : theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );

    if (isLink) {
      return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: _launchUrl, child: richText));
    }

    return richText;
  }
}
