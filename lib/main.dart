import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/overview_page.dart';
import 'screens/stations_page.dart';
import 'screens/fueling_activity_page.dart';
import 'screens/analytics_page.dart';
import 'screens/reports_page.dart';
import 'screens/expected_deliveries_page.dart';
import 'screens/login_page.dart';
import 'theme/mera_theme.dart';
import 'fuel_requests/customer/customer_welcome_page.dart';
import 'fuel_requests/customer/customer_login_page.dart';
import 'fuel_requests/customer/once_off_request_page.dart';
import 'fuel_requests/fuel_requests_review_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://sccwkrquytcawzaqduil.supabase.co',
    publishableKey: 'sb_publishable_lJTu9Xl5EbhCFh0GDCwOVA_rPwy3j6F',
  );

  runApp(const MeraFuelDashboardApp());
}

class MeraFuelDashboardApp extends StatefulWidget {
  const MeraFuelDashboardApp({super.key});

  @override
  State<MeraFuelDashboardApp> createState() => _MeraFuelDashboardAppState();
}

class _MeraFuelDashboardAppState extends State<MeraFuelDashboardApp> {
  Map<String, dynamic>? _profile;
  bool _checkingSession = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _checkingSession = false;
        });
      }
      return;
    }

    try {
      final profile = await _supabase
          .from('staff_profiles')
          .select(
            'id, staff_number, full_name, role, active, '
            'dashboard_access, omc',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        await _supabase.auth.signOut();
        return;
      }

      final active = profile['active'] == true;
      final role = profile['role']?.toString().trim().toUpperCase() ?? '';
      final dashboardAccess = profile['dashboard_access'] == true;

      final allowed =
          active &&
          (role == 'ADMIN' ||
              ((role == 'MERA' || role == 'OTHER' || role == 'OMC') &&
                  dashboardAccess));

      if (!allowed) {
        await _supabase.auth.signOut();
        return;
      }

      if (mounted) {
        setState(() {
          _profile = Map<String, dynamic>.from(profile);
        });
      }
    } catch (error) {
      debugPrint('DASHBOARD AUTH: Session restore failed: $error');
      await _supabase.auth.signOut();
    } finally {
      if (mounted) {
        setState(() {
          _checkingSession = false;
        });
      }
    }
  }

  void _handleLogin(DashboardLoginResult result) {
    setState(() {
      _profile = result.profile;
    });
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();

    if (!mounted) {
      return;
    }

    setState(() {
      _profile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MERA Fuel Control Dashboard',
      debugShowCheckedModeBanner: false,
      theme: MeraTheme.light,

      initialRoute: (() {
        final path = Uri.base.path;
        final fragment = Uri.base.fragment;

        if (fragment.startsWith('/container-fuels')) {
          return fragment;
        }

        if (path.startsWith('/container-fuels')) {
          return path;
        }

        return '/';
      })(),
      routes: {
        '/container-fuels': (context) => CustomerWelcomePage(
          onRegisteredCustomer: () {
            Navigator.pushNamed(context, '/container-fuels/login');
          },
          onOnceOffCustomer: () {
            Navigator.pushNamed(context, '/container-fuels/apply');
          },
        ),
        '/container-fuels/login': (context) => CustomerLoginPage(
          onLogin: (applicant) {
            // Registered customer dashboard will be connected later.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Customer login successful.')),
            );
          },
        ),
        '/container-fuels/apply': (context) => const OnceOffRequestPage(),
      },
      home: _checkingSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _profile == null
          ? LoginPage(onLogin: _handleLogin)
          : DashboardShell(staffProfile: _profile!, onLogout: _logout),
    );
  }
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    required this.staffProfile,
    required this.onLogout,
  });

  final Map<String, dynamic> staffProfile;
  final Future<void> Function() onLogout;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;

  String get _fullName =>
      widget.staffProfile['full_name']?.toString().trim() ?? 'Dashboard User';

  String get _role =>
      widget.staffProfile['role']?.toString().trim().toUpperCase() ?? '';

  static const _navigationItems = <_NavigationItem>[
    _NavigationItem(
      label: 'Overview',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),

    _NavigationItem(
      label: 'Expected Deliveries',
      icon: Icons.local_shipping_outlined,
      selectedIcon: Icons.local_shipping,
    ),
    _NavigationItem(
      label: 'Fuel Requests',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
    ),
    _NavigationItem(
      label: 'Fuelling Station Statistics',
      icon: Icons.local_gas_station_outlined,
      selectedIcon: Icons.local_gas_station,
    ),

    _NavigationItem(
      label: 'Fueling Activity',
      icon: Icons.ev_station_outlined,
      selectedIcon: Icons.ev_station,
    ),
    _NavigationItem(
      label: 'Analytics',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
    ),
    _NavigationItem(
      label: 'Reports',
      icon: Icons.description_outlined,
      selectedIcon: Icons.description,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 900;

        if (wideLayout) {
          return Scaffold(
            body: Row(
              children: [
                _buildNavigationRail(),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPage()),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('MERA FUEL CONTROL')),
          drawer: _buildDrawer(),
          body: _buildPage(),
        );
      },
    );
  }

  Widget _buildNavigationRail() {
    const meraGreen = MeraColors.green;

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: MeraColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // MERA branding
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Image.asset(
                  'assets/images/mera_logo.png',
                  height: 72,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 14),
                const Text(
                  'MERA FUEL CONTROL',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: Color(0xFF16352D),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Monitoring Dashboard',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _navigationItems.length,
              itemBuilder: (context, index) {
                final item = _navigationItems[index];
                final selected = index == _selectedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: MeraColors.paleGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(
                        selected ? item.selectedIcon : item.icon,
                        color: selected ? meraGreen : Colors.black54,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          color: selected ? meraGreen : const Color(0xFF33423E),
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Logged-in user
          Padding(
            padding: const EdgeInsets.all(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 19,
                    backgroundColor: meraGreen,
                    child: Icon(
                      Icons.person_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF263A35),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _role,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Logout',
                    onPressed: () async {
                      await widget.onLogout();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    const meraGreen = Color(0xFF006B54);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/mera_logo.png',
                    width: 58,
                    height: 58,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MERA FUEL CONTROL',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF16352D),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Monitoring Dashboard',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _navigationItems.length,
                itemBuilder: (context, index) {
                  final item = _navigationItems[index];
                  final selected = index == _selectedIndex;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: meraGreen.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(
                        selected ? item.selectedIcon : item.icon,
                        color: selected ? meraGreen : Colors.black54,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          color: selected ? meraGreen : const Color(0xFF33423E),
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: meraGreen,
                    child: Icon(Icons.person_outline, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _role,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Logout',
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await widget.onLogout();
                    },
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage() {
    const pages = [
      OverviewPage(),
      ExpectedDeliveriesPage(),
      FuelRequestsReviewPage(),
      StationsPage(),
      FuelingActivityPage(),
      AnalyticsPage(),
      ReportsPage(),
    ];

    return pages[_selectedIndex];
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: MeraColors.green),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('Module ready for implementation'),
        ],
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
