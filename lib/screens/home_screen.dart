import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:studenthub_chat/screens/chat.dart';
import 'package:studenthub_chat/screens/qr_code_scanner.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State variables
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _currentUserId;
  Map<String, dynamic>? _currentUserData;

  // User lists
  List<Map<String, dynamic>> _allAppUsers = [];
  List<Map<String, dynamic>> _matchedContacts = [];
  List<Map<String, dynamic>> _displayedUsers = [];

  // Controllers and keys
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Timer for search debouncing
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      await _loadCurrentUser();
      await _loadAllData();
    } catch (error) {
      print("Error initializing app: $error");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("No user logged in");
      }

      _currentUserId = user.uid;

      // Load current user data from Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();

      if (userDoc.exists) {
        _currentUserData = userDoc.data() as Map<String, dynamic>;
        print("Current user loaded: ${_currentUserData?['username']}");
      }
    } catch (e) {
      print("Error loading current user: $e");
      rethrow;
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load data in sequence
      await _loadAppUsers();
      await _loadAndMatchContacts();
    } catch (e) {
      print("Error loading all data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadAppUsers() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      _allAppUsers.clear();

      for (DocumentSnapshot doc in snapshot.docs) {
        // Skip current user
        if (doc.id == _currentUserId) continue;

        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;

        // Extract phone number from various possible fields
        String? phoneNumber = _extractPhoneNumber(userData);
        if (phoneNumber == null || phoneNumber.isEmpty) continue;

        // Extract username/display name
        String userName = _extractUserName(userData);

        _allAppUsers.add({
          'id': doc.id,
          'name': userName,
          'phone': phoneNumber,
          'email': userData['email'] ?? '',
          'username': userData['username'] ?? userName,
          'rawData': userData, // Keep original data for debugging
        });
      }

      print("Loaded ${_allAppUsers.length} app users");
    } catch (e) {
      print("Error loading app users: $e");
      rethrow;
    }
  }

  String? _extractPhoneNumber(Map<String, dynamic> userData) {
    // Check different possible phone field names
    final phoneFields = ['phone', 'phoneNumber', 'mobile', 'contact', 'tel'];

    for (String field in phoneFields) {
      if (userData.containsKey(field) && userData[field] != null) {
        String phone = userData[field].toString().trim();
        if (phone.isNotEmpty) return phone;
      }
    }
    return null;
  }

  String _extractUserName(Map<String, dynamic> userData) {
    final nameFields = ['username', 'name', 'displayName', 'fullName'];

    for (String field in nameFields) {
      if (userData.containsKey(field) && userData[field] != null) {
        String name = userData[field].toString().trim();
        if (name.isNotEmpty) return name;
      }
    }

    // Fallback to email or 'Unknown User'
    String? email = userData['email'];
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'Unknown User';
  }

  Future<void> _loadAndMatchContacts() async {
    try {
      // Get device contacts
      List<Map<String, dynamic>> deviceContacts = await _getDeviceContacts();
      print("Found ${deviceContacts.length} device contacts");

      // Match contacts with app users
      _matchedContacts = await _matchContacts(deviceContacts, _allAppUsers);
      print("Matched ${_matchedContacts.length} contacts");

      // Update displayed users
      if (mounted) {
        setState(() {
          _displayedUsers = List.from(_matchedContacts);
        });
      }
    } catch (e) {
      print("Error loading/matching contacts: $e");
      if (mounted) {
        setState(() {
          _displayedUsers = [];
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getDeviceContacts() async {
    List<Map<String, dynamic>> contacts = [];

    try {
      // Check and request contacts permission
      PermissionStatus status = await Permission.contacts.status;

      if (status.isDenied || status.isRestricted) {
        await Permission.contacts.request();
        status = await Permission.contacts.status;
      }

      if (status.isGranted) {
        // Get contacts from device
        List<Contact> flutterContacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );

        for (Contact contact in flutterContacts) {
          if (contact.phones.isNotEmpty) {
            for (var phone in contact.phones) {
              if (phone.number != null && phone.number!.trim().isNotEmpty) {
                String normalizedPhone = _normalizeIndianPhoneNumber(
                  phone.number!.trim(),
                );
                if (normalizedPhone.isNotEmpty) {
                  contacts.add({
                    'name': contact.displayName ?? 'Unknown Contact',
                    'originalPhone': phone.number!.trim(),
                    'normalizedPhone': normalizedPhone,
                    'label': phone.label?.name ?? 'mobile',
                    'contactId': contact.id,
                  });
                }
              }
            }
          }
        }

        // Sort contacts by name
        contacts.sort(
          (a, b) => (a['name'] as String).compareTo(b['name'] as String),
        );
      } else {
        print("Contacts permission not granted");
      }
    } catch (e) {
      print("Error getting device contacts: $e");
    }

    return contacts;
  }

  String _normalizeIndianPhoneNumber(String phone) {
    if (phone.isEmpty) return '';

    // Remove all non-digit characters except +
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d+]'), '');

    // Handle various Indian phone formats
    if (digitsOnly.startsWith('+91') && digitsOnly.length == 13) {
      // Perfect format: +919876543210
      return digitsOnly;
    } else if (digitsOnly.startsWith('91') && digitsOnly.length == 12) {
      // 919876543210 -> +919876543210
      return '+$digitsOnly';
    } else if (digitsOnly.startsWith('0') && digitsOnly.length == 11) {
      // 09876543210 -> +919876543210
      return '+91${digitsOnly.substring(1)}';
    } else if (digitsOnly.length == 10 &&
        RegExp(r'^[6-9]\d{9}$').hasMatch(digitsOnly)) {
      // 9876543210 -> +919876543210 (valid Indian mobile number)
      return '+91$digitsOnly';
    } else if (digitsOnly.startsWith('+') && digitsOnly.length >= 12) {
      // Already has international code, keep as is
      return digitsOnly;
    }

    // Return empty if not a valid Indian mobile number
    return '';
  }

  Future<List<Map<String, dynamic>>> _matchContacts(
    List<Map<String, dynamic>> deviceContacts,
    List<Map<String, dynamic>> appUsers,
  ) async {
    List<Map<String, dynamic>> matches = [];

    // Create a map for quick lookup of device contacts by normalized phone
    Map<String, Map<String, dynamic>> contactMap = {};
    for (var contact in deviceContacts) {
      String normalizedPhone = contact['normalizedPhone'] as String;
      if (normalizedPhone.isNotEmpty) {
        contactMap[normalizedPhone] = contact;
      }
    }

    // Match app users with device contacts
    for (var appUser in appUsers) {
      String userPhone = appUser['phone'] as String;
      String normalizedUserPhone = _normalizeIndianPhoneNumber(userPhone);

      if (normalizedUserPhone.isEmpty) continue;

      // Check for direct match
      if (contactMap.containsKey(normalizedUserPhone)) {
        var matchedContact = contactMap[normalizedUserPhone]!;
        matches.add({
          ...appUser,
          'contactName': matchedContact['name'],
          'contactPhone': matchedContact['originalPhone'],
          'contactLabel': matchedContact['label'],
          'isContact': true,
        });
        continue;
      }

      // Check for match with last 10 digits (for Indian numbers)
      if (normalizedUserPhone.length >= 13) {
        // +91 + 10 digits
        String last10Digits = normalizedUserPhone.substring(
          normalizedUserPhone.length - 10,
        );

        for (var contact in deviceContacts) {
          String contactPhone = contact['normalizedPhone'] as String;
          if (contactPhone.length >= 13 &&
              contactPhone.endsWith(last10Digits)) {
            matches.add({
              ...appUser,
              'contactName': contact['name'],
              'contactPhone': contact['originalPhone'],
              'contactLabel': contact['label'],
              'isContact': true,
            });
            break;
          }
        }
      }
    }

    return matches;
  }

  void _onSearchChanged(String query) {
    // Cancel previous timer
    _searchDebounceTimer?.cancel();

    // Start new timer for debouncing
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      setState(() {
        _searchQuery = query;
        _filterUsers();
      });
    });
  }

  void _filterUsers() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _displayedUsers = List.from(_matchedContacts);
      });
      return;
    }

    final query = _searchQuery.toLowerCase();

    List<Map<String, dynamic>> filtered = _matchedContacts.where((user) {
      final name = (user['name'] ?? '').toString().toLowerCase();
      final contactName = (user['contactName'] ?? '').toString().toLowerCase();
      final phone = (user['phone'] ?? '').toString().toLowerCase();
      final contactPhone = (user['contactPhone'] ?? '')
          .toString()
          .toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      final username = (user['username'] ?? '').toString().toLowerCase();

      return name.contains(query) ||
          contactName.contains(query) ||
          phone.contains(query) ||
          contactPhone.contains(query) ||
          email.contains(query) ||
          username.contains(query);
    }).toList();

    setState(() {
      _displayedUsers = filtered;
    });
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadAllData();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _openChatWithUser(Map<String, dynamic> user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ChatScreen(
          otherUserId: user["id"],
          otherUserName: user["name"],
          otherUserPhone: user["phone"],
        ),
      ),
    );

    print("Opening chat with ${user['name']}");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Opening chat with ${user['contactName'] ?? user['name']}",
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contacts Access Required'),
        content: const Text(
          'Student Hub needs access to your contacts to find friends who are also using the app. '
          'This helps you connect with people you already know.\n\n'
          'Your contacts are only used locally on your device and are not uploaded to any server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _debugCurrentState() {
    print("\n=== DEBUG INFO ===");
    print("Current User ID: $_currentUserId");
    print("Current User Data: $_currentUserData");
    print("App Users: ${_allAppUsers.length}");
    print("Matched Contacts: ${_matchedContacts.length}");
    print("Displayed Users: ${_displayedUsers.length}");

    if (_currentUserData != null && _currentUserData!['phone'] != null) {
      String myPhone = _currentUserData!['phone'].toString();
      print("My Phone: $myPhone -> ${_normalizeIndianPhoneNumber(myPhone)}");
    }

    print("=== END DEBUG ===\n");
  }

  Widget _buildUserItem(Map<String, dynamic> user, ThemeData theme) {
    String displayName = user['contactName'] ?? user['name'];
    String phoneNumber = user['contactPhone'] ?? user['phone'];
    bool isContact = user['isContact'] ?? false;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isContact
              ? theme.colorScheme.primary
              : theme.colorScheme.secondary,
          radius: 24,
          child: Text(
            displayName.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isContact && user['contactName'] != null)
              Text(
                'In your contacts',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            Text(
              phoneNumber,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            if (user['email'] != null && user['email'].isNotEmpty)
              Text(
                user['email'],
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
          ],
        ),
        trailing: Icon(
          Icons.chat_bubble_outline,
          color: theme.colorScheme.primary,
          size: 24,
        ),
        onTap: () => _openChatWithUser(user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: const Text(
          'Student Hub',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR Code',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const QRCodeScanner()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'Refresh Contacts',
            onPressed: () async {
              final status = await Permission.contacts.status;
              if (status.isDenied || status.isPermanentlyDenied) {
                _showPermissionDialog();
              } else {
                _refreshData();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: theme.colorScheme.primary,
        child: _isLoading
            ? _buildLoadingState(theme)
            : _buildMainContent(theme, size),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshData,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        tooltip: 'Refresh',
        child: _isRefreshing
            ? const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              )
            : const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            'Loading your contacts...',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onBackground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Finding friends who use Student Hub',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onBackground.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(ThemeData theme, Size size) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts or users...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                border: InputBorder.none,
                prefixIcon: Icon(
                  Icons.search,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ),

        // Current User Info
        if (_currentUserData != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primary,
                      radius: 20,
                      child: Text(
                        (_currentUserData!['username']?[0] ?? 'Y')
                            .toString()
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentUserData!['username'] ?? 'You',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          if (_currentUserData!['phone'] != null)
                            Text(
                              _currentUserData!['phone'].toString(),
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.7,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Results Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Contacts using Student Hub',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onBackground,
                ),
              ),
              Text(
                '${_displayedUsers.length} found',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onBackground.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),

        // User List or Empty State
        Expanded(
          child: _displayedUsers.isEmpty
              ? _buildEmptyState(theme, size)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: _displayedUsers.length,
                  itemBuilder: (context, index) {
                    return _buildUserItem(_displayedUsers[index], theme);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, Size size) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: size.height * 0.6,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: theme.colorScheme.onBackground.withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching contacts found'
                  : 'No contacts using Student Hub yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onBackground,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'Try a different search term or ask your friends to join Student Hub'
                    : 'Ask your friends to join Student Hub to start chatting with them!',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onBackground.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            if (_searchQuery.isEmpty)
              ElevatedButton.icon(
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Contacts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
