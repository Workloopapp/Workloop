import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/repositories/address_search_repository.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';

bool isValidClientEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return true;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

String normaliseClientPhone(String value) =>
    value.replaceAll(RegExp(r'[^0-9+]'), '');

Client? findDuplicateClient(
  Iterable<Client> clients, {
  required String phone,
  required String email,
  String? excludingClientId,
}) {
  final normalisedPhone = normaliseClientPhone(phone);
  final normalisedEmail = email.trim().toLowerCase();
  if (normalisedPhone.isEmpty && normalisedEmail.isEmpty) return null;

  for (final client in clients) {
    if (client.id == excludingClientId) continue;
    final samePhone =
        normalisedPhone.isNotEmpty &&
        normaliseClientPhone(client.phone ?? '') == normalisedPhone;
    final sameEmail =
        normalisedEmail.isNotEmpty &&
        (client.email ?? '').trim().toLowerCase() == normalisedEmail;
    if (samePhone || sameEmail) return client;
  }
  return null;
}

class ClientForm extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController addressController;
  final TextEditingController sourceController;
  final TextEditingController tagsController;
  final TextEditingController notesController;
  final TextEditingController importantNotesController;
  final String status;
  final String preferredContactMethod;
  final DateTime? birthday;
  final bool additionalInformationExpanded;
  final bool autofocusName;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPreferredContactChanged;
  final ValueChanged<DateTime?> onBirthdayChanged;
  final VoidCallback onToggleAdditionalInformation;
  final VoidCallback onChanged;

  const ClientForm({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.addressController,
    required this.sourceController,
    required this.tagsController,
    required this.notesController,
    required this.importantNotesController,
    required this.status,
    required this.preferredContactMethod,
    required this.birthday,
    required this.additionalInformationExpanded,
    required this.onStatusChanged,
    required this.onPreferredContactChanged,
    required this.onBirthdayChanged,
    required this.onToggleAdditionalInformation,
    required this.onChanged,
    this.autofocusName = false,
  });

  @override
  Widget build(BuildContext context) {
    final emailValid = isValidClientEmail(emailController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FormSectionHeader(
          title: 'Contact information',
          subtitle: 'Only a name is required. Add contact details when useful.',
        ),
        const SizedBox(height: AppSpacing.md),
        _ClientTextField(
          label: 'Client name',
          isRequired: true,
          hint: 'Person or business name',
          icon: LucideIcons.user,
          controller: nameController,
          autofocus: autofocusName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ClientTextField(
          label: 'Phone number',
          hint: 'Mobile or business number',
          icon: LucideIcons.phone,
          controller: phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ClientTextField(
          label: 'Email address',
          hint: 'name@example.com',
          icon: LucideIcons.mail,
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          errorText: emailValid ? null : 'Enter a valid email address.',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _FormSectionHeader(
          title: 'Client settings',
          subtitle:
              'Keep their relationship stage and communication preference clear.',
        ),
        const SizedBox(height: AppSpacing.md),
        _ChoiceField(
          label: 'Client status',
          value: status,
          options: const {
            'active': 'Active',
            'lead': 'Lead',
            'inactive': 'Inactive',
          },
          onChanged: onStatusChanged,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          switch (status) {
            'lead' => 'A prospective client you are still converting.',
            'inactive' => 'A past or paused client kept for reference.',
            _ => 'A current client you actively work with.',
          },
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ChoiceField(
          label: 'Preferred contact method',
          value: preferredContactMethod,
          options: const {
            'phone': 'Phone',
            'sms': 'Text',
            'email': 'Email',
            'whatsapp': 'WhatsApp',
          },
          onChanged: onPreferredContactChanged,
        ),
        if (!_contactMethodAvailable) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add the matching phone number or email to use this contact method.',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        const _FormSectionHeader(
          title: 'Booking address',
          subtitle:
              'The usual location where bookings take place, if relevant.',
        ),
        const SizedBox(height: AppSpacing.md),
        BookingAddressField(
          controller: addressController,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.xl),
        const _FormSectionHeader(
          title: 'Client notes',
          subtitle: 'Useful context that helps you deliver a better service.',
        ),
        const SizedBox(height: AppSpacing.md),
        _ClientTextField(
          label: 'Notes',
          hint: 'Preferences, access instructions or useful context',
          icon: LucideIcons.fileText,
          controller: notesController,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ClientTextField(
          label: 'Important note',
          hint: 'A must-know detail to keep prominent',
          icon: LucideIcons.bookmark,
          controller: importantNotesController,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.xl),
        SlateDisclosure(
          title: 'Additional information',
          subtitle: 'Lead source, tags and birthday',
          icon: LucideIcons.listPlus,
          expanded: additionalInformationExpanded,
          onToggle: onToggleAdditionalInformation,
          child: Column(
            children: [
              _ClientTextField(
                label: 'Lead source',
                hint: 'Referral, website, Instagram…',
                icon: LucideIcons.radio,
                controller: sourceController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ClientTextField(
                label: 'Tags',
                hint: 'Regular, monthly, commercial',
                helperText: 'Separate tags with commas.',
                icon: LucideIcons.tags,
                controller: tagsController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: AppSpacing.sm),
              _BirthdayField(birthday: birthday, onChanged: onBirthdayChanged),
            ],
          ),
        ),
      ],
    );
  }

  bool get _contactMethodAvailable {
    return switch (preferredContactMethod) {
      'email' => emailController.text.trim().isNotEmpty,
      _ => phoneController.text.trim().isNotEmpty,
    };
  }
}

class BookingAddressField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const BookingAddressField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  ConsumerState<BookingAddressField> createState() =>
      _BookingAddressFieldState();
}

class _BookingAddressFieldState extends ConsumerState<BookingAddressField> {
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<AddressPrediction> _predictions = const [];
  late String _sessionToken;
  String? _message;
  String? _selectedAddress;
  int _requestVersion = 0;
  bool _loading = false;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _sessionToken = _newSessionToken();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTapOutside() {
    _focusNode.unfocus();
  }

  void _closeSearchResults() {
    _requestVersion++;
    _debounce?.cancel();
    _focusNode.unfocus();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _predictions = const [];
      _message = null;
    });
  }

  void _handleChanged(String value) {
    widget.onChanged();
    _debounce?.cancel();
    final query = value.trim();
    if (query == _selectedAddress) return;
    _selectedAddress = null;
    if (query.length < 3) {
      setState(() {
        _loading = false;
        _message = null;
        _predictions = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () {
      _loadPredictions(query);
    });
  }

  Future<void> _loadPredictions(String query) async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final results = await ref
          .read(addressSearchRepositoryProvider)
          .autocomplete(input: query, sessionToken: _sessionToken);
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _predictions = results;
        _message = results.isEmpty ? 'No matching UK addresses found.' : null;
      });
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _predictions = const [];
        _message = 'Address search unavailable — enter it manually.';
      });
    }
  }

  Future<void> _selectPrediction(AddressPrediction prediction) async {
    if (_resolving) return;
    SlateHaptics.tap();

    var address = prediction.fullText;
    widget.controller
      ..text = address
      ..selection = TextSelection.collapsed(offset: address.length);
    widget.onChanged();
    _selectedAddress = address;
    setState(() {
      _loading = false;
      _resolving = true;
      _predictions = const [];
      _message = null;
    });
    try {
      final resolved = await ref
          .read(addressSearchRepositoryProvider)
          .resolve(placeId: prediction.placeId, sessionToken: _sessionToken)
          .timeout(const Duration(seconds: 6));
      if (resolved.formattedAddress.isNotEmpty) {
        address = preserveAddressUnit(
          formattedAddress: resolved.formattedAddress,
          unitLabel: prediction.unitLabel,
        );
      }
    } catch (_) {
      // The prediction remains a useful manual address if details fail.
    }
    if (!mounted) return;
    widget.controller
      ..text = address
      ..selection = TextSelection.collapsed(offset: address.length);
    widget.onChanged();
    _selectedAddress = address;
    _focusNode.unfocus();
    setState(() {
      _resolving = false;
      _predictions = const [];
      _sessionToken = _newSessionToken();
    });
  }

  String _newSessionToken() {
    final random = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${random.nextInt(1 << 32).toRadixString(36)}-'
        '${random.nextInt(1 << 32).toRadixString(36)}';
  }

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      onTapOutside: (_) => _handleTapOutside(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkloopFieldLabel(
            'Address',
            isRequired: false,
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _addressTextField(
            controller: widget.controller,
            focusNode: _focusNode,
            hintText: 'Start with the first line of the address',
            icon: LucideIcons.mapPin,
            onChanged: _handleChanged,
          ),
          if (_predictions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _AddressPredictions(
              predictions: _predictions,
              resolving: _resolving,
              onSelected: _selectPrediction,
              onDismiss: _closeSearchResults,
            ),
          ] else if (_message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _message!,
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addressTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.streetAddress,
      textInputAction: TextInputAction.search,
      textCapitalization: TextCapitalization.words,
      autocorrect: false,
      onChanged: onChanged,
      style: TextStyle(
        color: AppColors.of(context).t1,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: AppColors.of(context).t4,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.sm,
          ),
          child: Icon(icon, color: AppColors.of(context).t3, size: 17),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        suffixIcon: _loading || _resolving
            ? Padding(
                padding: EdgeInsets.all(15),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppColors.of(context).accentPrimary,
                  ),
                ),
              )
            : null,
        filled: true,
        fillColor: AppColors.of(context).bgCard.withValues(alpha: 0.68),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.of(context).border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: AppColors.of(context).accentPrimary,
            width: 1.4,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 15,
        ),
      ),
    );
  }
}

class _AddressPredictions extends StatelessWidget {
  final List<AddressPrediction> predictions;
  final bool resolving;
  final ValueChanged<AddressPrediction> onSelected;
  final VoidCallback onDismiss;

  const _AddressPredictions({
    required this.predictions,
    required this.resolving,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const rowHeight = 62.0;
    final resultsHeight = min(predictions.length * rowHeight, 248.0);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: resultsHeight,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              itemCount: predictions.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.of(context).border),
              itemBuilder: (context, index) => SizedBox(
                height: rowHeight,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: resolving
                        ? null
                        : () => onSelected(predictions[index]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.mapPin,
                            color: AppColors.of(context).t3,
                            size: 16,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  predictions[index].primaryText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.of(context).t1,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (predictions[index]
                                    .secondaryText
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    predictions[index].secondaryText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.of(context).t3,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.of(context).border),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: onDismiss,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 6,
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: AppColors.of(context).t3,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Google Maps',
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _FormSectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _ClientTextField extends StatelessWidget {
  final String label;
  final bool isRequired;
  final String hint;
  final String? helperText;
  final String? errorText;
  final IconData icon;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool autofocus;
  final bool autocorrect;
  final ValueChanged<String> onChanged;

  const _ClientTextField({
    required this.label,
    this.isRequired = false,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.onChanged,
    this.helperText,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.autofocus = false,
    this.autocorrect = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopFieldLabel(
          label,
          isRequired: isRequired,
          style: TextStyle(
            color: AppColors.of(context).t2,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: maxLines > 1
              ? TextInputAction.newline
              : textInputAction,
          textCapitalization: textCapitalization,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 2 : 1,
          autofocus: autofocus,
          autocorrect: autocorrect,
          onChanged: onChanged,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.of(context).t4,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.sm,
                bottom: maxLines > 1 ? 28 : 0,
              ),
              child: Icon(icon, color: AppColors.of(context).t3, size: 17),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 46),
            filled: true,
            fillColor: AppColors.of(context).bgCard.withValues(alpha: 0.68),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(
                color: errorText == null
                    ? AppColors.of(context).border
                    : AppColors.of(context).error,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(
                color: errorText == null
                    ? AppColors.of(context).accentPrimary
                    : AppColors.of(context).error,
                width: 1.4,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 15,
            ),
          ),
        ),
        if (errorText != null || helperText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            errorText ?? helperText!,
            style: TextStyle(
              color: errorText == null
                  ? AppColors.of(context).t3
                  : AppColors.of(context).error,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceField extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _ChoiceField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopFieldLabel(
          label,
          isRequired: false,
          style: TextStyle(
            color: AppColors.of(context).t2,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: options.entries.map((entry) {
            final selected = entry.key == value;
            void handleTap() {
              SlateHaptics.tap();
              onChanged(entry.key);
            }

            return Semantics(
              button: true,
              selected: selected,
              label: entry.value,
              onTap: handleTap,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: handleTap,
                  child: AnimatedContainer(
                    key: ValueKey(Theme.of(context).brightness),
                    duration: AppMotion.responsive(context, AppMotion.standard),
                    curve: AppMotion.curve,
                    constraints: const BoxConstraints(
                      minHeight: AppSpacing.minTouch,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.of(
                              context,
                            ).accentPrimary.withValues(alpha: 0.14)
                          : AppColors.of(
                              context,
                            ).bgCard.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: selected
                            ? AppColors.of(
                                context,
                              ).accentPrimary.withValues(alpha: 0.28)
                            : AppColors.of(context).border,
                      ),
                    ),
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: selected
                            ? AppColors.of(context).accentPrimary
                            : AppColors.of(context).t2,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _BirthdayField extends StatelessWidget {
  final DateTime? birthday;
  final ValueChanged<DateTime?> onChanged;

  const _BirthdayField({required this.birthday, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.of(context).bgCard.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _pickDate(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.of(context).border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.cake, color: AppColors.of(context).t3, size: 17),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: WorkloopFieldLabel(
                  'Birthday',
                  isRequired: false,
                  style: TextStyle(
                    color: AppColors.of(context).t2,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                birthday == null
                    ? 'Add date'
                    : '${birthday!.day}/${birthday!.month}/${birthday!.year}',
                style: TextStyle(
                  color: AppColors.of(context).t3,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (birthday != null) ...[
                const SizedBox(width: AppSpacing.xs),
                WorkloopIconButton(
                  icon: LucideIcons.x,
                  semanticLabel: 'Clear birthday',
                  color: AppColors.of(context).t3,
                  onTap: () => onChanged(null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final selected = await showWorkloopDatePicker(
      context: context,
      initialDate: birthday ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (selected != null) onChanged(selected);
  }
}
