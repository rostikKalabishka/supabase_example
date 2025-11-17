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
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUpWithEmailPassword({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName ?? email.split('@').first},
    );

    // Create profile immediately if session exists (email confirmation disabled)
    if (response.session != null && response.user != null) {
      await _createProfileIfNotExists(response.user!);
    }

    return response;
  }

  Future<void> signOut() async => await _supabase.auth.signOut();
  User? getCurrentUser() => _supabase.auth.currentUser;

  // ==================== PROFILE CREATION (SAFE) ====================
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
          'email': user.email,
          'phone_number': user.phone?.isNotEmpty == true ? user.phone : null,
          'full_name':
              user.userMetadata?['full_name'] ??
              user.email?.split('@').first ??
              'User',
        });
      }
    } catch (e) {
      log('Profile creation error: $e');
    }
  }

  // ==================== USER SEARCH (FIXED & OPTIMIZED) ====================
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final cleaned = query.trim();

    try {
      final response = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, phone_number, email')
          .or(
            'phone_number.ilike.%$cleaned%,'
            'full_name.ilike.%$cleaned%,'
            'email.ilike.%$cleaned%',
          )
          .neq('id', _supabase.auth.currentUser?.id ?? '');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('Search error: $e');
      return [];
    }
  }

  // ==================== CONTACTS ====================
  Future<void> addContact(String contactUserId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');
    if (userId == contactUserId) throw Exception('Cannot add yourself');

    try {
      await _supabase.from('contacts').insert({
        'user_id': userId,
        'contact_id': contactUserId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Contact already added');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getCurrentProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      return data;
    } catch (e) {
      log('getCurrentProfile error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getMyContacts() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final contactsResponse = await _supabase
          .from('contacts')
          .select('contact_id')
          .eq('user_id', userId);

      if (contactsResponse.isEmpty) return [];

      final List<String> contactIds = contactsResponse
          .map((e) => e['contact_id'] as String)
          .toList();

      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, phone_number')
          .inFilter('id', contactIds);

      return List<Map<String, dynamic>>.from(profilesResponse);
    } catch (e) {
      log('getMyContacts error: $e');
      return [];
    }
  }

  // ==================== PROFILE UPDATE ====================
  Future<void> updateProfile({required String fullName, String? phone}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await _supabase
        .from('profiles')
        .update({
          'full_name': fullName.trim().isEmpty ? null : fullName.trim(),
          'phone_number': phone?.trim().isEmpty == true ? null : phone?.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  // ==================== AVATAR UPLOAD (FIXED PATH) ====================
  Future<String?> uploadAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile == null) return null;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Colors.deepPurple,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Crop Image'),
      ],
    );
    if (croppedFile == null) return null;

    final file = File(croppedFile.path);
    final userId = _supabase.auth.currentUser!.id;
    final filePath = 'avatars/$userId/avatar.jpg';

    try {
      await _supabase.storage
          .from('avatars')
          .upload(filePath, file, fileOptions: const FileOptions(upsert: true));

      final publicUrl = _supabase.storage
          .from('avatars')
          .getPublicUrl(filePath);

      await _supabase
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', userId);

      return publicUrl;
    } catch (e) {
      log('Avatar upload error: $e');
      return null;
    }
  }

  // ==================== OTP (Email & Phone) ====================

  Future<void> signInWithOtp(String email) async {
    try {
      await _supabase.auth.signInWithOtp(
        email: email.trim(),
        // options: AuthOptions(redirectTo: 'io.supabase.flutter://login-callback/'),
      );
    } catch (e) {
      log(e.toString());
      rethrow;
    }
  }

  Future<void> signInWithPhoneOtp(String phone) async {
    // final formattedPhone = phone.trim().startsWith('+')
    //     ? phone.trim()
    //     : 'phone';
    try {
      await _supabase.auth.signInWithOtp(
        phone: phone.trim(),
        //  redirectTo: 'io.supabase.flutter://login-callback/',
      );
    } catch (e) {
      log(e.toString());
      rethrow;
    }
  }

  /// Перевіряє OTP код (для email і телефону)
  Future<AuthResponse> verifyOtp({
    required String token,
    required String type, // 'email' або 'sms'
    String? email,
    String? phone,
  }) async {
    try {
      final otpType = type == 'email' ? OtpType.email : OtpType.sms;

      final response = await _supabase.auth.verifyOTP(
        token: token,
        phone: phone,
        email: email,
        // type: otpType,
        type: OtpType.sms,
        //redirectTo: 'io.supabase.flutter://login-callback/',
      );

      if (response.user != null && response.session != null) {
        await _createProfileIfNotExists(response.user!);
      }

      return response;
    } catch (e) {
      log(e.toString());
      rethrow;
    }
  }
}
