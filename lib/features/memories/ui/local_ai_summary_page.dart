import 'package:flutter/material.dart';

import 'local_ai_summary_panel.dart';

class LocalAiSummaryPage extends StatelessWidget {
  const LocalAiSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地 AI 总结')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            Text(
              '日 · 周 · 月 · 年',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '默认使用 App 内置轻量模型理解每天发生的事，再逐级合并成周、月和年总结；高级模式也可以换成自己的 GGUF。聊天文字始终留在设备上。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 18),
            LocalAiSummaryPanel(onSummariesChanged: () {}),
          ],
        ),
      ),
    );
  }
}
