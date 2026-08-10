import 'package:flutter/material.dart';

import 'local_ai_summary_panel.dart';

class LocalAiSummaryPage extends StatelessWidget {
  const LocalAiSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 回忆')), 
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: scheme.secondary.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '把聊天整理成真正值得回看的故事',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '先理解每天发生的具体事情，再逐级合成周、月和年总结。默认模型完全在设备上运行，聊天正文不会上传。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 14),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TrustChip(icon: Icons.phonelink_lock_rounded, label: '离线运行'),
                      _TrustChip(icon: Icons.cloud_off_rounded, label: '不上传聊天'),
                      _TrustChip(icon: Icons.cached_rounded, label: '结果自动缓存'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '整理范围',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '第一次建议先生成日总结；已有结果会自动复用，不会每次都重新计算。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            LocalAiSummaryPanel(onSummariesChanged: () {}),
          ],
        ),
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
