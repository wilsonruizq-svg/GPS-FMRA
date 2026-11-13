import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/auth_service.dart';
import '../avatar_compress.dart';
import '../profile_service.dart';
import '../profile_validation.dart';

/// Editar nombre, teléfono opcional y foto (Storage `avatars`).
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
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _storageReady = false;
  bool _checkingStorage = true;
  String? _error;
  String? _photoUrl;
  bool _clearPhoto = false;
  /// `female` | `male` | null (= automático / heurística).
  String? _gender;

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
        _gender = p.gender;
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

  Future<void> _choosePhotoSource() async {
    if (!_storageReady || _saving) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text(AppStrings.profilePhotoFromGallery),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text(AppStrings.profilePhotoFromCamera),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;
    await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      // Captura a buena resolución; el recorte + AvatarCompress fijan ≤768.
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (file == null || !mounted) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 92,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: AppStrings.profilePhotoCropTitle,
            toolbarColor: AppColors.deepBlue,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.signalCyan,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
            cropStyle: CropStyle.circle,
          ),
          IOSUiSettings(
            title: AppStrings.profilePhotoCropTitle,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            cropStyle: CropStyle.circle,
          ),
        ],
      );
      if (!mounted) return;
      if (cropped == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.profilePhotoCropCancel)),
        );
        return;
      }

      setState(() {
        _saving = true;
        _error = null;
      });

      final raw = await File(cropped.path).readAsBytes();
      final compressed = AvatarCompress.compress(raw);
      final url = await _profiles.uploadOwnAvatar(bytes: compressed);
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _clearPhoto = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.profilePhotoUploaded)),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      final needsApply = raw.contains('bucket') ||
          raw.contains('avatars') ||
          raw.contains('storage') ||
          raw.contains('404') ||
          raw.contains('not found') ||
          raw.contains('row-level security') ||
          raw.contains('policy') ||
          raw.contains('permission');
      setState(() {
        _saving = false;
        _error = AppStrings.profilePhotoUploadError;
        if (needsApply) {
          _storageReady = false;
        }
      });
      if (needsApply) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AppStrings.profilePhotoApplyTitle),
            content: const SingleChildScrollView(
              child: Text(AppStrings.profilePhotoApplyBody),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(AppStrings.close),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _removePhoto() async {
    if (_saving) return;
    setState(() {
      _clearPhoto = true;
      _photoUrl = null;
      _error = null;
    });
  }

  String? _validatePhone(String? raw) {
    try {
      ProfileValidation.normalizePhone(raw);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_clearPhoto) {
        await _profiles.clearOwnAvatar();
      }
      final updated = await _profiles.updateOwn(
        displayName: _nameController.text,
        phone: _phoneController.text,
        photoUrl: _clearPhoto ? null : _photoUrl,
        clearPhoto: _clearPhoto,
        gender: _gender,
        clearGender: _gender == null,
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
    } catch (_) {
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
                    onChanged: (_) => setState(() {}),
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
                    validator: _validatePhone,
                    enabled: !_saving,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.profileGenderLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.profileGenderHelper,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.midBlue,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _GenderFiguritaPills(
                    value: _gender,
                    enabled: !_saving,
                    onChanged: (v) => setState(() => _gender = v),
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
        Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              radius: 52,
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
            if (_saving)
              const SizedBox(
                width: 104,
                height: 104,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_storageReady)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _choosePhotoSource,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  (url != null && url.isNotEmpty)
                      ? AppStrings.profileChangePhoto
                      : AppStrings.profileAddPhoto,
                ),
              ),
              if (url != null && url.isNotEmpty)
                TextButton(
                  onPressed: _saving ? null : _removePhoto,
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
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name[0].toUpperCase();
  }
}

/// Pastillas tipo diálogo «guardar ubicación» (Cámara/Galería / acciones).
/// Selección: Automático | Mujer | Hombre — sin SegmentedButton (texto partido).
class _GenderFiguritaPills extends StatelessWidget {
  const _GenderFiguritaPills({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  /// `female` | `male` | null (= automático).
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  static const _options = <({String? key, String label, IconData icon})>[
    (
      key: null,
      label: AppStrings.profileGenderUnset,
      icon: Icons.auto_awesome_outlined,
    ),
    (
      key: 'female',
      label: AppStrings.profileGenderFemale,
      icon: Icons.woman,
    ),
    (
      key: 'male',
      label: AppStrings.profileGenderMale,
      icon: Icons.man,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pillShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final selectedKey = value;

    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final opt = _options[i];
                final selected = selectedKey == opt.key;
                final child = Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(opt.icon, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        opt.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
                final onPressed = !enabled
                    ? null
                    : () => onChanged(opt.key);
                if (selected) {
                  return FilledButton(
                    style: FilledButton.styleFrom(
                      shape: pillShape,
                      backgroundColor: AppColors.deepBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onPressed,
                    child: child,
                  );
                }
                return OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: pillShape,
                    foregroundColor: AppColors.deepBlue,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: scheme.outlineVariant),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onPressed,
                  child: child,
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
