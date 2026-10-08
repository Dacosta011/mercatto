"""Map saved HTML image identities to local files without downloading anything."""
import argparse
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse
from scrape_sofifa import document
from importlib.util import spec_from_file_location, module_from_spec
_spec = spec_from_file_location('saved_batch', Path(__file__).with_name('prepare-sofifa-saved.py'))
_saved = module_from_spec(_spec)
_spec.loader.exec_module(_saved)
prepare = _saved.prepare

def assets(folder):
    folder = folder.resolve()
    snapshot = prepare(folder)
    images = {}
    for page in folder.glob('*.html'):
        doc = document(page.read_text(encoding='utf-8'))
        canonical = next(n.attrs['href'] for n in doc.all('link') if n.attrs.get('rel') == 'canonical')
        page_team = int(re.search(r'/team/(\d+)/', canonical).group(1))
        for node in doc.all('img'):
            source = node.attrs.get('data-src', '') or node.attrs.get('srcset', '')
            match = re.search(r'cdn\.sofifa\.net/(players|teams)/(?:(\d+)/(\d+)|(\d+))/', source)
            local = node.attrs.get('src', '')
            is_crest = 'crest' in node.attrs.get('class', '').split() and node.attrs.get('data-type') == 'team'
            if (not match and not is_crest) or urlparse(local).scheme or not local:
                continue
            if is_crest:
                kind, identity = 'teams', page_team
            else:
                kind, major, minor, tid = match.groups()
                identity = int(major + minor) if kind == 'players' else int(tid)
            path = (page.parent / unquote(local)).resolve()
            if not path.is_relative_to(folder) or not path.is_file():
                continue
            placeholder = path.name.startswith('player_')
            key = (kind, identity)
            if key not in images or (images[key]['placeholder'] and not placeholder):
                images[key] = {'kind':kind,'id':identity,'path':str(path),'placeholder':placeholder}
    result = []
    for team in snapshot['teams']:
        for key in [('teams',team['id'])] + [('players',p['id']) for p in team['players']]:
            if key not in images:
                raise ValueError(f'Missing downloaded image for {key}')
            result.append(images[key])
    return {'revision':snapshot['revision'], 'assets':result}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = assets(args.folder)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data,indent=2), encoding='utf-8')
    print(f'{len(data["assets"])} local images; {sum(a["placeholder"] for a in data["assets"])} saved placeholders')
