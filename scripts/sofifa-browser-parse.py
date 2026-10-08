"""Parse a browser capture using the same strict parser as the HTTP importer."""
import json
import sys
from pathlib import Path
from scrape_sofifa import document, revisions, parse_team

if __name__ == '__main__':
    html = Path(sys.argv[1]).read_text(encoding='utf-8')
    available = revisions(document(html))
    if not available:
        raise SystemExit('No edition selector found.')
    result = {'latest': max(available)}
    if len(sys.argv) > 2:
        result['team'] = parse_team(html, int(sys.argv[2]), int(sys.argv[3]), sys.argv[4])
    print(json.dumps(result, ensure_ascii=True))
