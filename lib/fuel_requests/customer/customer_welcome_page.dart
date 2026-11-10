
import 'package:flutter/material.dart';

import '../../theme/mera_theme.dart';

class CustomerWelcomePage extends StatelessWidget {
  const CustomerWelcomePage({
    super.key,
    required this.onRegisteredCustomer,
    required this.onOnceOffCustomer,
  });

  final VoidCallback onRegisteredCustomer;
  final VoidCallback onOnceOffCustomer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MeraColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/mera_logo.png',
                    height: 100,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Welcome to MERA Container Fuels',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: MeraColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Fuel Request Management Portal',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please select your customer category to continue.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 35),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 600;

                      final cards = [
                        _CustomerOptionCard(
                          icon: Icons.account_circle_outlined,
                          title: 'Registered Customer',
                          description:
                              'Already registered with MERA? '
                              'Sign in to submit and track your '
                              'container fuel requests.',
                          buttonLabel: 'LOGIN',
                          onPressed: onRegisteredCustomer,
                        ),
                        _CustomerOptionCard(
                          icon: Icons.assignment_outlined,
                          title: 'Once-Off Customer',
                          description:
                              'Not registered? Submit a once-off '
                              'container fuel request for MERA '
                              'review and approval.',
                          buttonLabel: 'APPLY NOW',
                          onPressed: onOnceOffCustomer,
                        ),
                      ];

                      if (isWide) {
                        return Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 20),
                            Expanded(child: cards[1]),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          cards[0],
                          const SizedBox(height: 20),
                          cards[1],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Malawi Energy Regulatory Authority',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: MeraColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerOptionCard extends StatelessWidget {
  const _CustomerOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              icon,
              size: 55,
              color: MeraColors.green,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: MeraColors.green,
                ),
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
