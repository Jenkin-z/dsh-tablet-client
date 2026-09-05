/// 行级 unified diff（LCS），为 RK3288 做了上限保护
library;

enum DiffOp { same, add, del }

class DiffLine {
  final DiffOp op;
  final String text;
  const DiffLine(this.op, this.text);
}

/// oldText == null 表示新建文件：全部标绿
/// 超限时降级为「全删+全加」，并在末尾注记
List<DiffLine> unifiedDiff(String? oldText, String newText,
    {int maxLines = 400}) {
  List<String> newLines = newText.split('\n');
  if (oldText == null) {
    final out = newLines.take(maxLines).map((l) => DiffLine(DiffOp.add, l)).toList();
    if (newLines.length > maxLines) {
      out.add(DiffLine(DiffOp.same, '… 以下 ${newLines.length - maxLines} 行已截断'));
    }
    return out;
  }
  List<String> oldLines = oldText.split('\n');

  // 规模保护：DP 表上限约 400 万格
  if (oldLines.length * newLines.length > 4000000) {
    final out = <DiffLine>[];
    for (final l in oldLines.take(maxLines ~/ 2)) {
      out.add(DiffLine(DiffOp.del, l));
    }
    for (final l in newLines.take(maxLines ~/ 2)) {
      out.add(DiffLine(DiffOp.add, l));
    }
    out.add(const DiffLine(DiffOp.same, '… 文件过大，仅显示前后片段'));
    return out;
  }

  final n = oldLines.length;
  final m = newLines.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = oldLines[i] == newLines[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m && out.length < maxLines) {
    if (oldLines[i] == newLines[j]) {
      out.add(DiffLine(DiffOp.same, oldLines[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add(DiffLine(DiffOp.del, oldLines[i]));
      i++;
    } else {
      out.add(DiffLine(DiffOp.add, newLines[j]));
      j++;
    }
  }
  while (i < n && out.length < maxLines) {
    out.add(DiffLine(DiffOp.del, oldLines[i++]));
  }
  while (j < m && out.length < maxLines) {
    out.add(DiffLine(DiffOp.add, newLines[j++]));
  }
  if (i < n || j < m) {
    out.add(const DiffLine(DiffOp.same, '… 以下内容已截断'));
  }
  return out;
}