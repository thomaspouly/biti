/// Décode un corps RLE type LifeWiki (`o` vivant, `b` mort, `$` ligne, `!` fin).
class ConwayRle {
  ConwayRle._();

  /// Grille **fixe** [width]×[height] (tronquée / bordée si le RLE dépasse).
  static List<List<bool>> decodeBodyToGrid(String body, int width, int height) {
    final List<List<bool>> grid = List<List<bool>>.generate(
      height,
      (_) => List<bool>.filled(width, false),
    );
    int x = 0;
    int y = 0;
    int i = 0;
    final String s = body.replaceAll(RegExp(r'\s'), '');
    while (i < s.length) {
      final int ch = s.codeUnitAt(i);
      if (ch >= 48 && ch <= 57) {
        int run = 0;
        while (i < s.length) {
          final int c = s.codeUnitAt(i);
          if (c < 48 || c > 57) break;
          run = run * 10 + (c - 48);
          i++;
        }
        if (run <= 0) run = 1;
        if (i >= s.length) break;
        final String tag = s[i].toLowerCase();
        i++;
        if (tag == r'$') {
          for (int k = 0; k < run; k++) {
            x = 0;
            y++;
          }
          continue;
        }
        final bool alive = tag == 'o' || tag == 'x';
        final bool dead = tag == 'b' || tag == '.';
        if (!alive && !dead) continue;
        for (int k = 0; k < run; k++) {
          if (y >= 0 && y < height && x >= 0 && x < width) {
            grid[y][x] = alive;
          }
          x++;
        }
        continue;
      }
      final String tag = s[i].toLowerCase();
      i++;
      if (tag == '!') break;
      if (tag == r'$') {
        x = 0;
        y++;
        continue;
      }
      final bool alive = tag == 'o' || tag == 'x';
      final bool dead = tag == 'b' || tag == '.';
      if (alive || dead) {
        if (y >= 0 && y < height && x >= 0 && x < width) {
          grid[y][x] = alive;
        }
        x++;
      }
    }
    return grid;
  }

  static void _setCell(List<List<bool>> rows, int cx, int cy, bool alive) {
    while (rows.length <= cy) {
      rows.add(<bool>[]);
    }
    final List<bool> row = rows[cy];
    while (row.length < cx) {
      row.add(false);
    }
    if (row.length == cx) {
      row.add(alive);
    } else {
      row[cx] = alive;
    }
  }

  /// Décode le RLE en rectangle **minimal** (largeur = max des lignes, hauteur = nombre de lignes).
  ///
  /// Plus de boîte imposée par le JSON : la taille du motif vient uniquement du RLE.
  static List<List<bool>> decodeBodyToTightGrid(String body) {
    final List<List<bool>> rows = <List<bool>>[];
    int x = 0;
    int y = 0;
    int i = 0;
    final String s = body.replaceAll(RegExp(r'\s'), '');
    while (i < s.length) {
      final int ch = s.codeUnitAt(i);
      if (ch >= 48 && ch <= 57) {
        int run = 0;
        while (i < s.length) {
          final int c = s.codeUnitAt(i);
          if (c < 48 || c > 57) break;
          run = run * 10 + (c - 48);
          i++;
        }
        if (run <= 0) run = 1;
        if (i >= s.length) break;
        final String tag = s[i].toLowerCase();
        i++;
        if (tag == r'$') {
          for (int k = 0; k < run; k++) {
            x = 0;
            y++;
          }
          continue;
        }
        final bool alive = tag == 'o' || tag == 'x';
        final bool dead = tag == 'b' || tag == '.';
        if (!alive && !dead) continue;
        for (int k = 0; k < run; k++) {
          _setCell(rows, x, y, alive);
          x++;
        }
        continue;
      }
      final String tag = s[i].toLowerCase();
      i++;
      if (tag == '!') break;
      if (tag == r'$') {
        x = 0;
        y++;
        continue;
      }
      final bool alive = tag == 'o' || tag == 'x';
      final bool dead = tag == 'b' || tag == '.';
      if (alive || dead) {
        _setCell(rows, x, y, alive);
        x++;
      }
    }
    if (rows.isEmpty) {
      return <List<bool>>[List<bool>.filled(1, false)];
    }
    int maxW = 0;
    for (final List<bool> r in rows) {
      if (r.length > maxW) maxW = r.length;
    }
    for (final List<bool> r in rows) {
      while (r.length < maxW) {
        r.add(false);
      }
    }
    while (rows.length > 1 && rows.last.every((bool v) => !v)) {
      rows.removeLast();
    }
    while (rows.length > 1 && rows.first.every((bool v) => !v)) {
      rows.removeAt(0);
    }
    if (rows.isEmpty) {
      return <List<bool>>[List<bool>.filled(1, false)];
    }
    return rows;
  }
}
