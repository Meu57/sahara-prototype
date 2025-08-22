import 'package:flutter/material.dart';
import 'package:sahara_app/screens/chat_screen.dart';
import 'package:sahara_app/screens/journey_screen.dart';
import 'package:sahara_app/screens/resource_library_screen.dart';
import 'package:sahara_app/screens/journal_screen.dart'; // ✅ Ensure this import is here

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 1;

  static const List<String> _appBarTitles = [
    'Aastha',
    'Your Journey',
    'Resources',
  ];

  static const List<Widget> _widgetOptions = [
    ChatScreen(),
    JourneyScreen(),
    ResourceLibraryScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // --- THIS IS THE UPGRADE ---
  List<Widget>? _buildAppBarActions() {
    // ONLY show the button if we are on the "Journey" tab (index 1)
    if (_selectedIndex == 1) {
      return [
        IconButton(
          icon: const Icon(Icons.book_outlined),
          tooltip: 'View Your Journal',
          onPressed: () {
            // This is a standard navigation command
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const JournalScreen()),
            );
          },
        ),
      ];
    }
    return null; // Return nothing for the other tabs
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitles[_selectedIndex]),
        // --- ENSURE THIS LINE IS HERE ---
        actions: _buildAppBarActions(),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
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
