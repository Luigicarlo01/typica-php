import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class InstitutionFilterPicker extends StatelessWidget {
  const InstitutionFilterPicker({
    super.key,
    required this.value,
    required this.institutions,
    required this.onChanged,
    this.compact = false,
  });

  final bool compact;
  final String? value;
  final List<String> institutions;
  final ValueChanged<String?> onChanged;
  static const _all = '__all__';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(14),
      decoration: compact
          ? null
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: compact ? 36 : null,
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_outlined,
                  size: compact ? 16 : 18,
                  color: AppColors.greenDark,
                ),
                SizedBox(width: compact ? 5 : 7),
                Expanded(
                  child: Text(
                    'Instituição',
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: compact ? 12.5 : 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.greenDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            decoration: BoxDecoration(
              color: AppColors.bege.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            ),
            child: DropdownButtonHideUnderline(
              child: Semantics(
                label: 'Filtrar por instituição',
                child: DropdownButton<String>(
                  key: const ValueKey('institution-filter-dropdown'),
                  value: value ?? _all,
                  isExpanded: true,
                  menuWidth: compact ? 240 : null,
                  selectedItemBuilder: (context) => [
                    for (final label in ['Todos', ...institutions])
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 12.5 : 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                  borderRadius: BorderRadius.circular(14),
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: compact ? 20 : 24,
                  ),
                  items: [
                    const DropdownMenuItem(value: _all, child: Text('Todos')),
                    for (final institution in institutions)
                      DropdownMenuItem(
                        value: institution,
                        child: Text(institution),
                      ),
                  ],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  onChanged: (selection) {
                    if (selection != null) {
                      onChanged(selection == _all ? null : selection);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
