import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../utils/dialog_utils.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../utils/route_transitions.dart';
import '../widgets/battery_indicator.dart';
import '../widgets/list_filter_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/quick_switch_bar.dart';
import '../widgets/unread_badge.dart';
import 'channel_chat_screen.dart';
import 'contacts_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

enum ChannelSortOption { manual, name, latestMessages, unread }

class ChannelsScreen extends StatefulWidget {
  final bool hideBackButton;

  const ChannelsScreen({super.key, this.hideBackButton = false});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen>
    with DisconnectNavigationMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  ChannelSortOption _sortOption = ChannelSortOption.manual;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MeshCoreConnector>().getChannels();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();

    // Auto-navigate back to scanner if disconnected
    if (!checkConnectionAndNavigate(connector)) {
      return const SizedBox.shrink();
    }

    final allowBack = !connector.isConnected;

    return PopScope(
      canPop: allowBack,
      child: Scaffold(
        appBar: AppBar(
          leading: BatteryIndicator(connector: connector),
          title: Text(context.l10n.channels_title),
          centerTitle: true,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: context.l10n.common_disconnect,
              onPressed: () => _disconnect(context),
            ),
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: context.l10n.common_settings,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await context.read<MeshCoreConnector>().getChannels();
          },
          child: () {
            if (connector.isLoadingChannels) {
              return const Center(child: CircularProgressIndicator());
            }

            final channels = connector.channels;

            if (channels.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height - 200,
                    child: EmptyState(
                      icon: Icons.tag,
                      title: context.l10n.channels_noChannelsConfigured,
                      action: FilledButton.icon(
                        onPressed: () => _addPublicChannel(context, connector),
                        icon: const Icon(Icons.public),
                        label: Text(context.l10n.channels_addPublicChannel),
                      ),
                    ),
                  ),
                ],
              );
            }

            final filteredChannels = _filterAndSortChannels(
              channels,
              connector,
            );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: context.l10n.channels_searchChannels,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            ),
                          _buildFilterButton(),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 300),
                        () {
                          if (!mounted) return;
                          setState(() {
                            _searchQuery = value.toLowerCase();
                          });
                        },
                      );
                    },
                  ),
                ),
                Expanded(
                  child: filteredChannels.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height - 300,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      context.l10n.channels_noChannelsFound,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : (_sortOption == ChannelSortOption.manual &&
                            _searchQuery.isEmpty)
                      ? ReorderableListView.builder(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 8,
                            bottom: 88,
                          ),
                          buildDefaultDragHandles: false,
                          itemCount: filteredChannels.length,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final reordered = List<Channel>.from(
                              filteredChannels,
                            );
                            final item = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, item);
                            unawaited(
                              connector.setChannelOrder(
                                reordered.map((c) => c.index).toList(),
                              ),
                            );
                          },
                          itemBuilder: (context, index) {
                            final channel = filteredChannels[index];
                            return _buildChannelTile(
                              context,
                              connector,
                              channel,
                              showDragHandle: true,
                              dragIndex: index,
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 8,
                            bottom: 88,
                          ),
                          itemCount: filteredChannels.length,
                          itemBuilder: (context, index) {
                            final channel = filteredChannels[index];
                            return _buildChannelTile(
                              context,
                              connector,
                              channel,
                            );
                          },
                        ),
                ),
              ],
            );
          }(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddChannelDialog(context),
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: QuickSwitchBar(
            selectedIndex: 1,
            onDestinationSelected: (index) =>
                _handleQuickSwitch(index, context),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelTile(
    BuildContext context,
    MeshCoreConnector connector,
    Channel channel, {
    bool showDragHandle = false,
    int? dragIndex,
  }) {
    final unreadCount = connector.getUnreadCountForChannel(channel);
    return Card(
      key: ValueKey('channel_${channel.index}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        dense: true,
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: const VisualDensity(vertical: -2),
        leading: CircleAvatar(
          backgroundColor: channel.isPublicChannel
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.blue.withValues(alpha: 0.2),
          child: Icon(
            channel.isPublicChannel
                ? Icons.public
                : channel.name.startsWith('#')
                ? Icons.tag
                : Icons.lock,
            color: channel.isPublicChannel ? Colors.green : Colors.blue,
          ),
        ),
        title: Text(
          channel.name.isEmpty
              ? context.l10n.channels_channelIndex(channel.index)
              : channel.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          channel.name.startsWith('#')
              ? context.l10n.channels_hashtagChannel
              : channel.isPublicChannel
              ? context.l10n.channels_publicChannel
              : context.l10n.channels_privateChannel,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unreadCount > 0) ...[
              UnreadBadge(count: unreadCount),
              const SizedBox(width: 4),
            ],
            if (showDragHandle && dragIndex != null)
              ReorderableDelayedDragStartListener(
                index: dragIndex,
                child: Icon(
                  Icons.drag_handle,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        onTap: () async {
          connector.markChannelRead(channel.index);
          await Future.delayed(const Duration(milliseconds: 50));
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChannelChatScreen(channel: channel),
              ),
            );
          }
        },
        onLongPress: () => _showChannelActions(context, connector, channel),
      ),
    );
  }

  void _showChannelActions(
    BuildContext context,
    MeshCoreConnector connector,
    Channel channel,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.l10n.channels_editChannel),
              onTap: () async {
                Navigator.pop(context);
                await Future.delayed(const Duration(milliseconds: 100));
                if (context.mounted) {
                  _showEditChannelDialog(context, connector, channel);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                context.l10n.channels_deleteChannel,
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(context);
                await Future.delayed(const Duration(milliseconds: 100));
                if (context.mounted) {
                  _confirmDeleteChannel(context, connector, channel);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleQuickSwitch(int index, BuildContext context) {
    if (index == 1) return;
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const ContactsScreen(hideBackButton: true)),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const MapScreen(hideBackButton: true)),
        );
        break;
    }
  }

  Future<void> _disconnect(BuildContext context) async {
    final connector = context.read<MeshCoreConnector>();
    await showDisconnectDialog(context, connector);
  }

  Widget _buildFilterButton() {
    const actionSortManual = 0;
    const actionSortName = 1;
    const actionSortLatest = 2;
    const actionSortUnread = 3;

    return SortFilterMenu(
      tooltip: context.l10n.listFilter_tooltip,
      sections: [
        SortFilterMenuSection(
          title: context.l10n.channels_sortBy,
          options: [
            SortFilterMenuOption(
              value: actionSortManual,
              label: context.l10n.channels_sortManual,
              checked: _sortOption == ChannelSortOption.manual,
            ),
            SortFilterMenuOption(
              value: actionSortName,
              label: context.l10n.channels_sortAZ,
              checked: _sortOption == ChannelSortOption.name,
            ),
            SortFilterMenuOption(
              value: actionSortLatest,
              label: context.l10n.channels_sortLatestMessages,
              checked: _sortOption == ChannelSortOption.latestMessages,
            ),
            SortFilterMenuOption(
              value: actionSortUnread,
              label: context.l10n.channels_sortUnread,
              checked: _sortOption == ChannelSortOption.unread,
            ),
          ],
        ),
      ],
      onSelected: (action) {
        setState(() {
          switch (action) {
            case actionSortManual:
              _sortOption = ChannelSortOption.manual;
              break;
            case actionSortLatest:
              _sortOption = ChannelSortOption.latestMessages;
              break;
            case actionSortUnread:
              _sortOption = ChannelSortOption.unread;
              break;
            case actionSortName:
            default:
              _sortOption = ChannelSortOption.name;
              break;
          }
        });
      },
    );
  }

  List<Channel> _filterAndSortChannels(
    List<Channel> channels,
    MeshCoreConnector connector,
  ) {
    var filtered = channels.where((channel) {
      if (_searchQuery.isEmpty) return true;
      final label = _normalizeChannelName(channel);
      return label.toLowerCase().contains(_searchQuery);
    }).toList();

    int compareByName(Channel a, Channel b) {
      final nameA = _normalizeChannelName(a);
      final nameB = _normalizeChannelName(b);
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    }

    switch (_sortOption) {
      case ChannelSortOption.manual:
        break;
      case ChannelSortOption.latestMessages:
        filtered.sort((a, b) {
          final aMessages = connector.getChannelMessages(a);
          final bMessages = connector.getChannelMessages(b);
          final aLast = aMessages.isEmpty
              ? DateTime(1970)
              : aMessages.last.timestamp;
          final bLast = bMessages.isEmpty
              ? DateTime(1970)
              : bMessages.last.timestamp;
          final timeCompare = bLast.compareTo(aLast);
          if (timeCompare != 0) return timeCompare;
          return compareByName(a, b);
        });
        break;
      case ChannelSortOption.unread:
        filtered.sort((a, b) {
          final aUnread = connector.getUnreadCountForChannel(a);
          final bUnread = connector.getUnreadCountForChannel(b);
          final unreadCompare = bUnread.compareTo(aUnread);
          if (unreadCompare != 0) return unreadCompare;
          return compareByName(a, b);
        });
        break;
      case ChannelSortOption.name:
        filtered.sort(compareByName);
        break;
    }

    return filtered;
  }

  String _normalizeChannelName(Channel channel) {
    if (channel.name.isEmpty)
      return 'Channel ${channel.index}'; // Fallback for sorting
    final trimmed = channel.name.trim();
    if (trimmed.startsWith('#') && trimmed.length > 1) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  void _showAddChannelDialog(BuildContext context) {
    final connector = context.read<MeshCoreConnector>();
    final nextIndex = _findNextAvailableIndex(
      connector.channels,
      connector.maxChannels,
    );
    final hasPublicChannel = connector.channels.any((c) => c.isPublicChannel);
    int? selectedOption;
    final nameController = TextEditingController();
    final pskController = TextEditingController();
    final hashtagController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Widget buildOptionTile({
            required int optionIndex,
            required IconData icon,
            required String title,
            required String subtitle,
            bool enabled = true,
          }) {
            final isSelected = selectedOption == optionIndex;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: enabled
                    ? (isSelected
                          ? Theme.of(dialogContext).colorScheme.primaryContainer
                          : null)
                    : Colors.grey.withValues(alpha: 0.2),
                child: Icon(
                  icon,
                  color: enabled
                      ? (isSelected
                            ? Theme.of(dialogContext).colorScheme.primary
                            : null)
                      : Colors.grey,
                ),
              ),
              title: Text(
                title,
                style: TextStyle(color: enabled ? null : Colors.grey),
              ),
              subtitle: Text(
                subtitle,
                style: TextStyle(color: enabled ? null : Colors.grey),
              ),
              trailing: enabled ? const Icon(Icons.chevron_right) : null,
              selected: isSelected,
              onTap: enabled
                  ? () {
                      setDialogState(() {
                        selectedOption = optionIndex;
                        nameController.clear();
                        pskController.clear();
                        hashtagController.clear();
                      });
                    }
                  : null,
            );
          }

          Widget? buildExpandedContent() {
            switch (selectedOption) {
              case 0: // Create Private Channel
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: dialogContext.l10n.channels_channelName,
                          border: const OutlineInputBorder(),
                        ),
                        maxLength: 31,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final name = nameController.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        dialogContext
                                            .l10n
                                            .channels_enterChannelName,
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final random = Random.secure();
                                final psk = Uint8List(16);
                                for (int i = 0; i < 16; i++) {
                                  psk[i] = random.nextInt(256);
                                }
                                Navigator.pop(dialogContext);
                                connector.setChannel(nextIndex, name, psk);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.l10n.channels_channelAdded(
                                          name,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Text(dialogContext.l10n.common_create),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

              case 1: // Join Private Channel
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: dialogContext.l10n.channels_channelName,
                          border: const OutlineInputBorder(),
                        ),
                        maxLength: 31,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: pskController,
                        decoration: InputDecoration(
                          labelText: dialogContext.l10n.channels_pskHex,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final name = nameController.text.trim();
                                final pskHex = pskController.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        dialogContext
                                            .l10n
                                            .channels_enterChannelName,
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Uint8List psk;
                                try {
                                  psk = Channel.parsePskHex(pskHex);
                                } on FormatException {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        dialogContext
                                            .l10n
                                            .channels_pskMustBe32Hex,
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.pop(dialogContext);
                                connector.setChannel(nextIndex, name, psk);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.l10n.channels_channelAdded(
                                          name,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Text(dialogContext.l10n.common_add),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

              case 2: // Join Public Channel
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final psk = Channel.parsePskHex(
                              Channel.publicChannelPsk,
                            );
                            Navigator.pop(dialogContext);
                            connector.setChannel(nextIndex, 'Public', psk);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.l10n.channels_publicChannelAdded,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text(dialogContext.l10n.common_add),
                        ),
                      ),
                    ],
                  ),
                );

              case 3: // Join Hashtag Channel
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: hashtagController,
                        decoration: InputDecoration(
                          labelText: dialogContext.l10n.channels_enterHashtag,
                          hintText: dialogContext.l10n.channels_hashtagHint,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.tag),
                        ),
                        maxLength: 31,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                var hashtag = hashtagController.text.trim();
                                if (hashtag.isEmpty) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        dialogContext
                                            .l10n
                                            .channels_enterChannelName,
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                // Normalize hashtag name
                                final name = hashtag.startsWith('#')
                                    ? hashtag
                                    : '#$hashtag';
                                final psk = Channel.derivePskFromHashtag(
                                  hashtag,
                                );
                                Navigator.pop(dialogContext);
                                connector.setChannel(nextIndex, name, psk);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.l10n.channels_channelAdded(
                                          name,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Text(dialogContext.l10n.common_add),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

              default:
                return null;
            }
          }

          return AlertDialog(
            title: Text(dialogContext.l10n.channels_addChannel),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildOptionTile(
                      optionIndex: 0,
                      icon: Icons.add,
                      title: dialogContext.l10n.channels_createPrivateChannel,
                      subtitle:
                          dialogContext.l10n.channels_createPrivateChannelDesc,
                    ),
                    if (selectedOption == 0) buildExpandedContent()!,
                    const Divider(height: 1),
                    buildOptionTile(
                      optionIndex: 1,
                      icon: Icons.lock,
                      title: dialogContext.l10n.channels_joinPrivateChannel,
                      subtitle:
                          dialogContext.l10n.channels_joinPrivateChannelDesc,
                    ),
                    if (selectedOption == 1) buildExpandedContent()!,
                    if (!hasPublicChannel) ...[
                      const Divider(height: 1),
                      buildOptionTile(
                        optionIndex: 2,
                        icon: Icons.public,
                        title: dialogContext.l10n.channels_joinPublicChannel,
                        subtitle:
                            dialogContext.l10n.channels_joinPublicChannelDesc,
                      ),
                      if (selectedOption == 2) buildExpandedContent()!,
                    ],
                    const Divider(height: 1),
                    buildOptionTile(
                      optionIndex: 3,
                      icon: Icons.tag,
                      title: dialogContext.l10n.channels_joinHashtagChannel,
                      subtitle:
                          dialogContext.l10n.channels_joinHashtagChannelDesc,
                    ),
                    if (selectedOption == 3) buildExpandedContent()!,
                    const Divider(height: 1),
                    buildOptionTile(
                      optionIndex: 4,
                      icon: Icons.qr_code,
                      title: dialogContext.l10n.channels_scanQrCode,
                      subtitle:
                          dialogContext.l10n.channels_scanQrCodeComingSoon,
                      enabled: false,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(dialogContext.l10n.common_close),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditChannelDialog(
    BuildContext context,
    MeshCoreConnector connector,
    Channel channel,
  ) {
    final nameController = TextEditingController(text: channel.name);
    final pskController = TextEditingController(text: channel.pskHex);
    bool smazEnabled = connector.isChannelSmazEnabled(channel.index);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(
            dialogContext.l10n.channels_editChannelTitle(channel.index),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: dialogContext.l10n.channels_channelName,
                    border: const OutlineInputBorder(),
                  ),
                  maxLength: 31,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pskController,
                  decoration: InputDecoration(
                    labelText: dialogContext.l10n.channels_pskHex,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.casino),
                      tooltip: dialogContext.l10n.channels_generateRandomPsk,
                      onPressed: () {
                        final random = Random.secure();
                        final bytes = Uint8List(16);
                        for (int i = 0; i < 16; i++) {
                          bytes[i] = random.nextInt(256);
                        }
                        pskController.text = Channel.formatPskHex(bytes);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dialogContext.l10n.channels_smazCompression),
                  value: smazEnabled,
                  onChanged: (value) => setState(() => smazEnabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final pskHex = pskController.text.trim();

                Uint8List psk;
                try {
                  psk = Channel.parsePskHex(pskHex);
                } on FormatException {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(dialogContext.l10n.channels_pskMustBe32Hex),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext);
                connector.setChannel(channel.index, name, psk);
                connector.setChannelSmazEnabled(channel.index, smazEnabled);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.channels_channelUpdated(name)),
                  ),
                );
              },
              child: Text(dialogContext.l10n.common_save),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteChannel(
    BuildContext context,
    MeshCoreConnector connector,
    Channel channel,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.channels_deleteChannel),
        content: Text(
          dialogContext.l10n.channels_deleteChannelConfirm(channel.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              connector.deleteChannel(channel.index);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.channels_channelDeleted(channel.name),
                  ),
                ),
              );
            },
            child: Text(
              dialogContext.l10n.common_delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _addPublicChannel(BuildContext context, MeshCoreConnector connector) {
    final psk = Channel.parsePskHex(Channel.publicChannelPsk);
    connector.setChannel(0, 'Public', psk);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.channels_publicChannelAdded)),
    );
  }

  int _findNextAvailableIndex(List<Channel> channels, int maxChannels) {
    final usedIndices = channels.map((c) => c.index).toSet();
    for (int i = 0; i < maxChannels; i++) {
      if (!usedIndices.contains(i)) return i;
    }
    return 0;
  }
}
