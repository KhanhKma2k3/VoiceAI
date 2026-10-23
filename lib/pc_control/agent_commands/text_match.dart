library text_match;

/// Tiện ích so khớp văn bản tiếng Việt (bỏ dấu + độ giống mờ).
/// Dùng chung cho parser và lệnh mở/đóng ứng dụng.
class TextMatch {
  TextMatch._();

  static final Map<String, String> _noMark = _build();

  static Map<String, String> _build() {
    const groups = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    final m = <String, String>{};
    groups.forEach((base, chars) {
      for (final c in chars.split('')) {
        m[c] = base;
      }
    });
    return m;
  }

  /// Chữ thường, bỏ dấu, chỉ giữ chữ-số và khoảng trắng đơn.
  static String normalize(String s) {
    final sb = StringBuffer();
    for (final c in s.toLowerCase().split('')) {
      sb.write(_noMark[c] ?? c);
    }
    return sb
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
        cur[j] = v;
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Độ giống 0..1 dựa trên khoảng cách chỉnh sửa.
  static double similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final longest = a.length > b.length ? a.length : b.length;
    return 1 - _lev(a, b) / longest;
  }

  /// Điểm khớp 0..1 giữa [query] (người nói) và [name] (tên ứng dụng/cửa sổ).
  /// 1.0 khớp tuyệt đối > 0.95 bắt đầu bằng > 0.88 chứa > 0.85 đủ các từ >
  /// độ giống mờ (chịu được nghe sai 1-2 ký tự).
  static double score(String query, String name) {
    final q = normalize(query);
    final n = normalize(name);
    if (q.isEmpty || n.isEmpty) return 0;
    if (q == n) return 1.0;
    if (n.startsWith('$q ') || n.startsWith(q)) return 0.95;
    if (q.length >= 3 && n.contains(q)) return 0.88;

    final qt = q.split(' ');
    final nt = n.split(' ');
    if (qt.every(nt.contains)) return 0.85;

    var best = similarity(q, n);
    // So từng từ của tên với toàn bộ câu nói (tên dài như "Microsoft Word").
    for (final t in nt) {
      if (t.length < 3) continue;
      final s = similarity(q, t) * 0.92;
      if (s > best) best = s;
    }
    // Từng từ của câu nói với từng từ của tên (cả hai nhiều từ).
    if (qt.length > 1 && nt.length > 1) {
      var sum = 0.0;
      for (final a in qt) {
        var m = 0.0;
        for (final b in nt) {
          final s = similarity(a, b);
          if (s > m) m = s;
        }
        sum += m;
      }
      final avg = sum / qt.length * 0.9;
      if (avg > best) best = avg;
    }
    return best;
  }
}