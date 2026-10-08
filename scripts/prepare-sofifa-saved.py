"""Validate a complete user-supplied HTML batch; does not claim live freshness."""
import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from scrape_sofifa import ROOT, document, revisions, parse_team

def prepare(folder):
    config = {t['id']: t for t in json.loads((ROOT/'sofifa-teams.json').read_text(encoding='utf-8'))}
    teams, receipts, editions, players = {}, [], set(), set()
    for path in sorted(folder.glob('*.html')):
        raw = path.read_bytes()
        html = raw.decode('utf-8')
        doc = document(html)
        canonical = next((n.attrs.get('href','') for n in doc.all('link') if n.attrs.get('rel') == 'canonical'), '')
        match = re.search(r'/team/(\d+)/(?:[^/?#]+/)?(\d{6})(?:/|$)', canonical)
        if not match:
            raise ValueError(f'{path.name}: missing team/edition')
        tid, revision = map(int, match.groups())
        if tid not in config or tid in teams:
            raise ValueError(f'{path.name}: unexpected or duplicate team')
        available = revisions(doc)
        if not available or revision != max(available):
            raise ValueError(f'{path.name}: not the latest revision listed in this saved page')
        team = parse_team(html, tid, revision, config[tid]['name'])
        for player in team['players']:
            if player['id'] in players:
                raise ValueError(f'Duplicate player: {player["id"]}')
            players.add(player['id'])
        teams[tid] = team
        editions.add(revision)
        receipts.append({'file':path.name, 'sha256':hashlib.sha256(raw).hexdigest(), 'canonical':canonical})
    if set(teams) != set(config) or len(editions) != 1:
        raise ValueError('Need all 16 teams from the same edition')
    return {'source':'sofifa-saved-html', 'revision':editions.pop(),
            'validatedAt':datetime.now(timezone.utc).isoformat(),
            'teams':[teams[tid] for tid in config], 'receipts':receipts}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = prepare(args.folder)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(args.output)
    print(f'Validated saved batch: {len(data["teams"])} teams, {sum(len(t["players"]) for t in data["teams"])} players; revision {data["revision"]}')
