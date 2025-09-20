// lib/screens/app_shell.dart
import 'package:flutter/material.dart';
import 'package:sahara_app/screens/chat_screen.dart';
import 'package:sahara_app/screens/journey_screen.dart';
import 'package:sahara_app/screens/resource_library_screen.dart';
import 'package:sahara_app/screens/journal_screen.dart';
import 'package:sahara_app/screens/journal_entry_screen.dart';



class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 1;

  // One-time payloads we can pass into children when navigating.
  String? _completedTaskTitleForChat;
  String? _initialResourceIdForLibrary;
  String? _initialJournalTitle;    
  String? _initialJournalContent;

  static const List<String> _appBarTitles = [
    'Aastha',
    'Your Journey',
    'Resources',
  ];

  // Pages are built dynamically so we can pass one-time payloads down.
  List<Widget> _buildPages() {
    return [
      ChatScreen(completedTaskTitle: _completedTaskTitleForChat),
      JourneyScreen(onNavigate: _navigateToTab),
      ResourceLibraryScreen(initialResourceId: _initialResourceIdForLibrary),
    ];
  }

  void _navigateToTab(
    int index, {
    String? completedTaskTitle,
    String? resourceId,
    String? journalTitle,
    String? journalContent,
  }) {
    setState(() {
      _selectedIndex = index;
      _completedTaskTitleForChat = completedTaskTitle;
      _initialResourceIdForLibrary = resourceId;
      _initialJournalTitle = journalTitle;
      _initialJournalContent = journalContent;
    });

    // 🔥 FIX: use the stored fields instead of params
    if ((_initialJournalTitle != null && _initialJournalTitle!.isNotEmpty) ||
        (_initialJournalContent != null && _initialJournalContent!.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JournalEntryScreen(
              initialTitle: _initialJournalTitle,
              initialContent: _initialJournalContent,
            ),
          ),
        );
        setState(() {
          _initialJournalTitle = null;
          _initialJournalContent = null;
        });
      });
    }

    // Clear the other one-time payloads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _completedTaskTitleForChat = null;
        _initialResourceIdForLibrary = null;
      });
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _completedTaskTitleForChat = null;
      _initialResourceIdForLibrary = null;
      _initialJournalTitle = null;
      _initialJournalContent = null;
      _selectedIndex = index;
    });
  }

  List<Widget>? _buildAppBarActions() {
    if (_selectedIndex == 1) {
      return [
        IconButton(
          icon: const Icon(Icons.book_outlined),
          tooltip: 'View Your Journal',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const JournalScreen()),
            );
          },
        ),
      ];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitles[_selectedIndex]),
        actions: _buildAppBarActions(),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: 'Journey',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            label: 'Resources',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
