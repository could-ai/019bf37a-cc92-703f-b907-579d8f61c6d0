import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  const SupabaseConfig._();

  static const String supabaseUrl = 'https://nyfyxhpugahsdgowqhhl.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im55Znl4aHB1Z2Foc2Rnb3dxaGhsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzMTAzOTIsImV4cCI6MjA4NDg4NjM5Mn0.4mjsq--Bh_HczHek6b6UN2tCFk0wSdg5FEc1TMDat_w';

  static const String _envSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String _envSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static Future<void>? _initialization;

  static Future<void> ensureInitialized() async {
    if (_isReady) {
      return;
    }

    _validateEnv();

    _initialization ??= Supabase.initialize(
      url: _effectiveSupabaseUrl,
      anonKey: _effectiveSupabaseAnonKey,
    );

    try {
      await _initialization;
    } catch (error) {
      _initialization = null;
      rethrow;
    }
  }

  static SupabaseClient get client {
    if (!_isReady) {
      throw StateError(
        'Supabase is not initialized. Call await SupabaseConfig.ensureInitialized() before using the client.',
      );
    }

    return Supabase.instance.client;
  }

  static bool get _isReady {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _validateEnv() {
    if (_effectiveSupabaseUrl.isEmpty || _effectiveSupabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing Supabase credentials. Pass --dart-define SUPABASE_URL and SUPABASE_ANON_KEY when running the app.',
      );
    }
  }

  static String get _effectiveSupabaseUrl =>
      _envSupabaseUrl.isEmpty ? supabaseUrl : _envSupabaseUrl;

  static String get _effectiveSupabaseAnonKey =>
      _envSupabaseAnonKey.isEmpty ? supabaseAnonKey : _envSupabaseAnonKey;
}

class SupabaseEdgeFunctions {
  const SupabaseEdgeFunctions._();

  static Future<FunctionResponse> invoke(
    String functionName, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    await SupabaseConfig.ensureInitialized();

    return SupabaseConfig.client.functions.invoke(
      functionName,
      body: body,
      headers: headers,
    );
  }
}
