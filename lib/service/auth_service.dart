// lib/service/auth_service.dart
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== AUTHENTICATION ====================
  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUpWithEmailPassword({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName ?? email.split('@').first},
    );

    // If email confirmation is disabled — create profile immediately
    if (response.user != null && response.session != null) {
      await _createProfileIfNotExists(response.user!);
    }

    return response;
  }

  Future<void> signOut() async => await _supabase.auth.signOut();

  User? getCurrentUser() => _supabase.auth.currentUser;

  // ==================== PROFILE CREATION ====================
  Future<void> _createProfileIfNotExists(User user) async {
    try {
      final exists = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (exists == null) {
        await _supabase.from('profiles').insert({
          'id': user.id,
          'user_email': user.email,
          'full_name':
              user.userMetadata?['full_name'] ??
              user.email?.split('@').first ??
              'User',
        });
      }
    } catch (e) {
      log('Profile creation fallback error: $e');
    }
  }

  // ==================== USER SEARCH ====================
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final cleaned = query.trim();

    final response = await _supabase
        .from('profiles')
        .select('id, full_name, avatar_url, phone')
        .or('phone.ilike.%$cleaned%,full_name.ilike.%$cleaned%')
        .neq('id', _supabase.auth.currentUser?.id ?? '');

    return List<Map<String, dynamic>>.from(response);
  }

  // ==================== CONTACTS ====================
  Future<void> addContact(String contactUserId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await _supabase.from('contacts').insert({
      'user_id': userId,
      'contact_id': contactUserId,
    });
  }

  Future<Map<String, dynamic>?> getCurrentProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    return data;
  }

  Future<List<Map<String, dynamic>>> getMyContacts() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    // First, get all contact IDs
    final contactsResponse = await _supabase
        .from('contacts')
        .select('contact_id')
        .eq('user_id', userId);

    if (contactsResponse.isEmpty) return [];

    final List<String> contactIds = contactsResponse
        .map((e) => e['contact_id'] as String)
        .toList();

    // Then fetch all contact profiles in one query
    final profilesResponse = await _supabase
        .from('profiles')
        .select('id, full_name, avatar_url, phone')
        .inFilter('id', contactIds);

    return List<Map<String, dynamic>>.from(profilesResponse);
  }

  Future<void> updateProfile({required String fullName, String? phone}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': phone,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  // ==================== AVATAR UPLOAD ====================
  Future<String?> uploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop',
          toolbarColor: Colors.deepPurple,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Crop'),
      ],
    );
    if (cropped == null) return null;

    final file = File(cropped.path);
    final userId = _supabase.auth.currentUser!.id;
    final path = '$userId/avatar.jpg';

    await _supabase.storage
        .from('avatars')
        .upload(path, file, fileOptions: const FileOptions(upsert: true));

    final url = _supabase.storage.from('avatars').getPublicUrl(path);

    await _supabase
        .from('profiles')
        .update({'avatar_url': url})
        .eq('id', userId);

    return url;
  }
}
