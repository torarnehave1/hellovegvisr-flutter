import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Represents a menu item in the branding configuration
class MenuItem {
  final String id;
  final String label;
  final String icon;
  final String route;

  MenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      icon: json['icon'] ?? '',
      route: json['route'] ?? json['path'] ?? '',
    );
  }
}

/// Represents the complete branding configuration for a domain
class BrandingConfig {
  final String? domain;
  final String? logoUrl;
  final String? mobileAppLogo; // Special logo for mobile app with "Powered by" branding
  final String? mobileAppTitle; // Custom title to replace the default app title in mobile app
  final String? siteTitle;
  final String? slogan; // Brand tagline/slogan
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final String? frontPageGraphId;
  final bool showSearchBar;
  final List<String> contentFilterAreas;
  final List<MenuItem> menuItems;
  final bool hasCustomBranding;

  BrandingConfig({
    this.domain,
    this.logoUrl,
    this.mobileAppLogo,
    this.mobileAppTitle,
    this.siteTitle,
    this.slogan,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    this.frontPageGraphId,
    this.showSearchBar = true,
    this.contentFilterAreas = const [],
    this.menuItems = const [],
    this.hasCustomBranding = false,
  });

  /// Creates default VEGVISR branding
  factory BrandingConfig.defaultBranding() {
    return BrandingConfig(
      domain: null,
      logoUrl: null,
      mobileAppLogo: null,
      mobileAppTitle: null,
      siteTitle: 'Hallo Vegvisr',
      slogan: null,
      primaryColor: const Color(0xFF4f6d7a),
      secondaryColor: const Color(0xFF3a5260),
      accentColor: const Color.fromARGB(255, 20, 195, 17),
      frontPageGraphId: null,
      showSearchBar: true,
      contentFilterAreas: [],
      menuItems: [],
      hasCustomBranding: false,
    );
  }

  /// Get the appropriate logo URL for the mobile app
  /// Prefers mobileAppLogo if set, otherwise falls back to regular logo
  String? get effectiveMobileLogoUrl => mobileAppLogo ?? logoUrl;

  /// Get the effective mobile app title
  /// Returns mobileAppTitle if set, otherwise falls back to "Hallo Vegvisr"
  String get effectiveMobileAppTitle =>
      (mobileAppTitle != null && mobileAppTitle!.isNotEmpty)
          ? mobileAppTitle!
          : 'Hallo Vegvisr';

  /// Creates branding configuration from API response
  factory BrandingConfig.fromJson(Map<String, dynamic> json) {
    // Parse colors from hex strings or use defaults
    Color parseColor(dynamic value, Color defaultColor) {
      if (value == null) return defaultColor;
      if (value is String && value.isNotEmpty) {
        try {
          String hex = value.replaceAll('#', '');
          if (hex.length == 6) {
            return Color(int.parse('FF$hex', radix: 16));
          } else if (hex.length == 8) {
            return Color(int.parse(hex, radix: 16));
          }
        } catch (_) {}
      }
      return defaultColor;
    }

    // Parse menu items
    List<MenuItem> parseMenuItems(dynamic items) {
      if (items == null) return [];
      if (items is List) {
        return items
            .whereType<Map<String, dynamic>>()
            .map((item) => MenuItem.fromJson(item))
            .toList();
      }
      return [];
    }

    // Parse content filter areas
    List<String> parseFilterAreas(dynamic areas) {
      if (areas == null) return [];
      if (areas is List) {
        return areas.whereType<String>().toList();
      }
      if (areas is String && areas.isNotEmpty) {
        return areas.split(',').map((s) => s.trim()).toList();
      }
      return [];
    }

    final defaults = BrandingConfig.defaultBranding();

    return BrandingConfig(
      domain: json['domain'] as String? ?? json['mySite'] as String?,
      logoUrl: json['logo'] as String? ?? json['myLogo'] as String?,
      mobileAppLogo: json['mobileAppLogo'] as String?,
      mobileAppTitle: json['mobileAppTitle'] as String?,
      siteTitle: json['siteTitle'] as String? ?? json['site_title'] as String? ?? json['mySite'] as String? ?? json['title'] as String?,
      slogan: json['slogan'] as String?,
      primaryColor: parseColor(json['primaryColor'], defaults.primaryColor),
      secondaryColor: parseColor(json['secondaryColor'], defaults.secondaryColor),
      accentColor: parseColor(json['accentColor'], defaults.accentColor),
      frontPageGraphId: json['mySiteFrontPage'] as String? ?? json['frontPageGraphId'] as String?,
      showSearchBar: json['showSearchBar'] as bool? ?? true,
      contentFilterAreas: parseFilterAreas(json['selectedCategories'] ?? json['contentFilterAreas']),
      menuItems: parseMenuItems(json['menuItems'] ?? json['menuConfig']?['items']),
      hasCustomBranding: true,
    );
  }

  /// Convert color to hex string
  String colorToHex(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).substring(2).toUpperCase()}';
  }
}

/// Service for fetching and managing branding configuration
class BrandingService {
  static const String _apiBaseUrl = 'https://vegvisr-frontend.torarnehave.workers.dev';

  // Cached branding configuration
  static BrandingConfig? _cachedBranding;

  /// Get the current branding configuration (cached or default)
  static BrandingConfig get currentBranding => _cachedBranding ?? BrandingConfig.defaultBranding();

  /// Check if we have custom branding loaded
  static bool get hasCustomBranding => _cachedBranding?.hasCustomBranding ?? false;

  /// Fetch branding configuration for a phone number
  /// Returns BrandingConfig (custom if found, default otherwise)
  static Future<BrandingConfig> fetchBrandingByPhone(String phone) async {
    try {
      // Normalize phone number
      final normalizedPhone = _normalizePhone(phone);
      if (normalizedPhone == null) {
        debugPrint('BrandingService: Invalid phone format: $phone');
        return BrandingConfig.defaultBranding();
      }

      final url = '$_apiBaseUrl/branding/by-phone?phone=${Uri.encodeComponent(normalizedPhone)}';
      debugPrint('BrandingService: Fetching branding from $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['branding'] != null) {
          // Merge top-level fields into branding for parsing
          final branding = Map<String, dynamic>.from(data['branding'] as Map<String, dynamic>);
          // Add top-level domain if not in branding
          if (data['domain'] != null && branding['domain'] == null) {
            branding['domain'] = data['domain'];
          }
          // Add menuConfig if present at top level
          if (data['menuConfig'] != null && branding['menuConfig'] == null) {
            branding['menuConfig'] = data['menuConfig'];
          }
          debugPrint('BrandingService: Found custom branding for domain: ${branding['domain']}');
          _cachedBranding = BrandingConfig.fromJson(branding);
          return _cachedBranding!;
        } else {
          debugPrint('BrandingService: No custom branding found, using defaults');
          _cachedBranding = BrandingConfig.defaultBranding();
          return _cachedBranding!;
        }
      } else {
        debugPrint('BrandingService: API error ${response.statusCode}: ${response.body}');
        return BrandingConfig.defaultBranding();
      }
    } catch (e) {
      debugPrint('BrandingService: Error fetching branding: $e');
      return BrandingConfig.defaultBranding();
    }
  }

  /// Clear cached branding (call on logout)
  static void clearBranding() {
    _cachedBranding = null;
    debugPrint('BrandingService: Branding cache cleared');
  }

  /// Normalize Norwegian phone number to +47XXXXXXXX format
  static String? _normalizePhone(String phone) {
    // Remove all non-digit characters except +
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');

    // Extract just digits
    String digits = cleaned.replaceAll(RegExp(r'\D'), '');

    // Handle different formats
    if (cleaned.startsWith('+47') && digits.length == 10) {
      return '+$digits';
    } else if (digits.length == 8) {
      return '+47$digits';
    } else if (digits.length == 10 && digits.startsWith('47')) {
      return '+$digits';
    }

    return null; // Invalid format
  }

  /// Generate a ThemeData from branding configuration
  static ThemeData generateTheme(BrandingConfig branding) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: branding.accentColor,
        primary: branding.primaryColor,
        secondary: branding.secondaryColor,
      ),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: branding.primaryColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: branding.primaryColor,
        foregroundColor: Colors.white,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: Colors.white,
      ),
    );
  }
}
