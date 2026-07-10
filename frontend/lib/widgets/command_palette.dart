import 'dart:async';

import 'package:flutter/material.dart';

class EditorCommand {
  const EditorCommand({
    required this.label,
    required this.category,
    required this.icon,
    required this.action,
    this.shortcut = '',
    this.enabled = true,
    this.keywords = const [],
  });

  final String label;
  final String category;
  final IconData icon;
  final FutureOr<void> Function() action;
  final String shortcut;
  final bool enabled;
  final List<String> keywords;

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    final haystack = [
      label,
      category,
      shortcut,
      ...keywords,
    ].join(' ').toLowerCase();
    return haystack.contains(query.toLowerCase());
  }
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.commands});

  final List<EditorCommand> commands;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.commands
        .where((command) => command.matches(_query))
        .toList();
    return Dialog(
      alignment: const Alignment(0, -0.45),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const Key('command-palette-search'),
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (value) => setState(() => _query = value.trim()),
                onSubmitted: (_) {
                  final first = filtered
                      .where((item) => item.enabled)
                      .firstOrNull;
                  if (first != null) {
                    _run(first);
                  }
                },
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search commands, tools, and panels',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matching commands'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final command = filtered[index];
                        return ListTile(
                          enabled: command.enabled,
                          leading: Icon(command.icon),
                          title: Text(command.label),
                          subtitle: Text(command.category),
                          trailing: command.shortcut.isEmpty
                              ? null
                              : _ShortcutBadge(label: command.shortcut),
                          onTap: command.enabled ? () => _run(command) : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _run(EditorCommand command) {
    Navigator.of(context).pop();
    final result = command.action();
    if (result is Future<void>) {
      unawaited(result);
    }
  }
}

class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
