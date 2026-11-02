import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/auth_service.dart';
import '../profile_service.dart';
import '../profile_validation.dart';

/// Editar nombre, teléfono opcional y foto (si Storage `avatars` existe).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _profiles = ProfileService();
  final _auth = AuthService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _storageReady = false;
  bool _checkingStorage = true;
  String? _error;
  String? _photoUrl;
  bool _clearPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _profiles.ensureOwnProfile();
      final storage = await _profiles.isAvatarStorageReady();
      if (!mounted) return;
      _nameController.text = p.displayName ?? '';
      _phoneController.text = p.phone ?? '';
      setState(() {
        _photoUrl = p.photoUrl;
        _storageReady = storage;
        _checkingStorage = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _checkingStorage = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    if (!_storageReady || _saving) return;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;

      setState(() => _saving = true);
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? 'image/jpeg';
      final url = await _profiles.uploadOwnAvatar(
        bytes: bytes,
        contentType: mime,
      );
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _clearPhoto = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppStrings.profilePhotoUploadError;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await _profiles.updateOwn(
        displayName: _nameController.text,
        phone: _phoneController.text,
        photoUrl: _clearPhoto ? null : _photoUrl,
        clearPhoto: _clearPhoto,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.profileSaved)),
      );
      Navigator.of(context).pop(updated);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message?.toString() ?? e.toString();
        _saving = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppStrings.profileSaveError;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.profileEditTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _buildAvatarSection(),
                  const SizedBox(height: 8),
                  if (!_checkingStorage && !_storageReady)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        AppStrings.profilePhotoStorageNote,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.midBlue,
                            ),
                      ),
                    ),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: AppStrings.profileNameLabel,
                      hintText: AppStrings.profileNameHint,
                    ),
                    validator: ProfileValidation.validateDisplayName,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: AppStrings.profilePhoneLabel,
                      hintText: AppStrings.profilePhoneHint,
                      helperText: AppStrings.profilePhoneHelper,
                    ),
                    enabled: !_saving,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${AppStrings.profileEmailReadonly}: '
                    '${_auth.currentUser?.email ?? '—'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(AppStrings.profileSave),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatarSection() {
    final url = _clearPhoto ? null : _photoUrl;
    return Column(
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: AppColors.deepBlue.withValues(alpha: 0.12),
          backgroundImage: (url != null && url.isNotEmpty)
              ? NetworkImage(url)
              : null,
          child: (url == null || url.isEmpty)
              ? Text(
                  _initials(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: AppColors.deepBlue,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (_storageReady)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _pickPhoto,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text(AppStrings.profileChangePhoto),
              ),
              if (url != null && url.isNotEmpty)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _clearPhoto = true;
                            _photoUrl = null;
                          }),
                  child: const Text(AppStrings.profileRemovePhoto),
                ),
            ],
          ),
      ],
    );
  }

  String _initials() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name[0].toUpperCase();
  }
}
