class DailyActivitySummarizer {
  const DailyActivitySummarizer();

  static const _activityKeywords = <String>[
    '去',
    '到家',
    '到了',
    '回家',
    '回来',
    '出发',
    '吃',
    '喝',
    '做饭',
    '买',
    '逛',
    '看电影',
    '看剧',
    '玩',
    '游戏',
    '散步',
    '运动',
    '跑步',
    '健身',
    '上班',
    '下班',
    '工作',
    '开会',
    '上课',
    '学习',
    '考试',
    '睡',
    '起床',
    '医院',
    '医生',
    '旅行',
    '酒店',
    '拍照',
    '快递',
  ];

  String summarize({
    required List<String> activityCandidates,
    required List<String> fallbackCandidates,
  }) {
    final preferred = _rank(activityCandidates, minimumScore: 2);
    final selected = preferred.isNotEmpty
        ? preferred.take(3).toList(growable: false)
        : _rank(fallbackCandidates, minimumScore: 0)
            .take(2)
            .toList(growable: false);

    if (selected.isEmpty) {
      return '这一天更多是零碎的日常聊天，展开后可以直接回看当天的真实记录。';
    }

    final snippets = selected.map((value) => '“$value”').join('、');
    if (preferred.isNotEmpty) {
      return '从聊天里能看到这一天的几个日常片段：$snippets。';
    }
    return '这一天聊天里比较有代表性的片段有：$snippets。';
  }

  List<String> _rank(
    List<String> values, {
    required int minimumScore,
  }) {
    final seen = <String>{};
    final scored = <({String text, int score, int order})>[];

    for (var index = 0; index < values.length; index += 1) {
      final normalized = _normalize(values[index]);
      if (!_isUseful(normalized) || !seen.add(normalized)) {
        continue;
      }

      var score = 0;
      for (final keyword in _activityKeywords) {
        if (normalized.contains(keyword)) {
          score += keyword.length > 1 ? 4 : 1;
        }
      }
      if (normalized.length >= 6 && normalized.length <= 42) {
        score += 3;
      } else if (normalized.length <= 64) {
        score += 1;
      }
      if (_looksLikeQuestion(normalized)) {
        score -= 3;
      }
      if (normalized.contains('哈哈') || normalized == '好的' || normalized == '嗯嗯') {
        score -= 4;
      }

      if (score >= minimumScore) {
        scored.add((text: normalized, score: score, order: index));
      }
    }

    scored.sort((first, second) {
      final byScore = second.score.compareTo(first.score);
      return byScore != 0 ? byScore : first.order.compareTo(second.order);
    });
    return scored.map((item) => item.text).toList(growable: false);
  }

  String _normalize(String value) {
    var text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAll(RegExp(r'^[，。！？、,.!?\s]+|[，。！？、,.!?\s]+$'), '');
    if (text.length > 56) {
      text = '${text.substring(0, 54)}…';
    }
    return text;
  }

  bool _isUseful(String value) {
    if (value.length < 2) return false;
    final lower = value.toLowerCase();
    if (lower.startsWith('<') || lower.startsWith('http')) return false;
    if (value.startsWith('[') && value.endsWith(']')) return false;
    return RegExp(r'[\u4e00-\u9fffA-Za-z0-9]').hasMatch(value);
  }

  bool _looksLikeQuestion(String value) {
    return value.endsWith('?') ||
        value.endsWith('？') ||
        value.endsWith('吗') ||
        value.endsWith('嘛') ||
        value.endsWith('呢');
  }
}
