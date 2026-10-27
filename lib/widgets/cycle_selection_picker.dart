import 'package:flutter/material.dart';

import '../services/crop_cycle_service.dart';
import '../utils/app_colors.dart';

/// Filtro de ciclo de maturação.
///
/// Visual:
///
/// ┌─────────────────────────────────┐
/// │ Ciclo de maturação              │
/// │ [ Médio                      ▼ ] │
/// └─────────────────────────────────┘
class CycleSelectionPicker extends StatelessWidget {
  const CycleSelectionPicker({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final service = CropCycleService();

    return AnimatedBuilder(
      animation: service,

      builder: (context, _) {
        return Container(
          width: double.infinity,

          padding: compact ? EdgeInsets.zero : const EdgeInsets.all(14),

          decoration: compact
              ? null
              : BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),

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
              // ================================================
              // TÍTULO
              // ================================================

              SizedBox(
                height: compact ? 36 : null,
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: compact ? 16 : 18,
                      color: AppColors.greenDark,
                    ),
                    SizedBox(width: compact ? 5 : 7),
                    Expanded(
                      child: Text(
                        'Ciclo de maturação',
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

              // ================================================
              // DROPDOWN
              // ================================================
              Container(
                width: double.infinity,

                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),

                decoration: BoxDecoration(
                  color: AppColors.bege.withValues(alpha: 0.45),

                  borderRadius: BorderRadius.circular(12),

                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.10),
                  ),
                ),

                child: DropdownButtonHideUnderline(
                  child: Semantics(
                    label: 'Filtrar por ciclo de maturação',
                    child: DropdownButton<CropCycle>(
                      key: const ValueKey('cycle-filter-dropdown'),
                      value: service.cycle,

                      isExpanded: true,
                      menuWidth: compact ? 240 : null,

                      borderRadius: BorderRadius.circular(14),

                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: compact ? 20 : 24,
                      ),

                      items: CropCycle.values.map((ciclo) {
                        return DropdownMenuItem<CropCycle>(
                          value: ciclo,

                          child: Text(
                            ciclo.label,

                            style: TextStyle(
                              fontSize: compact ? 12.5 : 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),

                      onChanged: (novo) {
                        if (novo == null) {
                          return;
                        }

                        service.setCycle(novo);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
