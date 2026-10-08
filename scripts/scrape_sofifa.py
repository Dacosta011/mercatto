"""Fetch the latest SoFIFA edition into a validated JSON snapshot (Python 3, stdlib only).

Does not write to a database. Stops on access challenges; never solves or bypasses them.
"""
import argparse
import hashlib
import json
import re
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parent


class Node:
    def __init__(self, tag, attrs=(), parent=None):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.children = []

    def all(self, tag=None):
        for child in self.children:
            if isinstance(child, Node):
                if tag is None or child.tag == tag:
                    yield child
                yield from child.all(tag)

    def text(self):
        return ' '.join(c.text() if isinstance(c, Node) else c for c in self.children).strip()


class Document(HTMLParser):
    VOID = {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}

    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = self.current = Node('root')
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.current)
        self.current.children.append(node)
        if tag not in self.VOID:
            self.current = node

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        node = self.current
        while node.parent:
            if node.tag == tag:
                self.current = node.parent
                break
            node = node.parent

    def handle_data(self, data):
        self.current.children.append(data)


def document(html):
    if re.search(r'cf-chl-|challenge-platform|Just a moment|Verificación de seguridad', html, re.I):
        raise ValueError('SoFIFA returned an access challenge; no import will be performed.')
    if '</html>' not in html.lower():
        raise ValueError('Incomplete HTML document.')
    return Document(html).root


def revisions(doc):
    found = set()
    selectors = [n for n in doc.all('select') if n.attrs.get('id') in ('select-version','select-roster')]
    nodes = [n for selector in selectors for n in selector.all('option')] if selectors else doc.all()
    for node in nodes:
        for value in (node.attrs.get('href',''), node.attrs.get('value','')):
            found.update(int(v) for v in re.findall(r'[?&]r=(\d{6})(?=[&#]|$)', value))
            found.update(int(v) for v in re.findall(r'/(?:team|player)/\d+/[^/?#]+/(\d{6})(?=[/?#]|$)', value))
            found.update(int(v) for v in re.findall(r'/team/\d+/(\d{6})(?=[/?#]|$)', value))
            if node.tag == 'option' and re.fullmatch(r'\d{6}', value):
                found.add(int(value))
    return found


def section_heading(node):
    """SoFIFA puts Squad and On loan tables in the same article."""
    while node.parent:
        siblings = node.parent.children
        for sibling in reversed(siblings[:siblings.index(node)]):
            if isinstance(sibling, Node) and sibling.tag in ('h2','h3','h4','h5'):
                return sibling.text().lower()
        node = node.parent
    return ''


def image_url(node):
    value = node.attrs.get('data-src') or node.attrs.get('src') or ''
    parsed = urlparse(urljoin('https://sofifa.com/', value))
    return parsed.geturl() if parsed.scheme == 'https' and parsed.hostname in ('cdn.sofifa.net','sofifa.com') else None


def parse_team(html, team_id, revision, fallback_name):
    doc = document(html)
    canonical = next((n.attrs.get('href','') for n in doc.all('link') if n.attrs.get('rel') == 'canonical'), '')
    if not re.search(rf'/team/{team_id}(?:/|$)', canonical):
        raise ValueError(f'Team {team_id}: missing or mismatched canonical identity.')
    # A pinned page must identify the requested edition in its canonical or player links.
    edition_links = [canonical] + [a.attrs.get('href','') for a in doc.all('a') if '/player/' in a.attrs.get('href','')]
    if not any(re.search(rf'(?:/|[?&]r=){revision}(?:/|[&#?]|$)', value) for value in edition_links):
        raise ValueError(f'Team {team_id}: could not verify edition {revision}.')
    players = {}
    for row in doc.all('tr'):
        links = [(a, re.search(r'/player/(\d+)(?:/|$)', a.attrs.get('href',''))) for a in row.all('a')]
        links = [(a,m) for a,m in links if m]
        if not links:
            continue
        heading = section_heading(row)
        if re.search(r'on loan|loaned out|cedidos|en préstamo|en prestamo', heading):
            continue
        if heading not in ('squad','plantilla'):
            raise ValueError('Player table is not identified as the active squad.')
        identities = {int(m.group(1)) for _,m in links}
        if len(identities) != 1:
            raise ValueError('Ambiguous player row.')
        pid = identities.pop()
        link = next((a for a,_ in links if a.text()), links[0][0])
        name = link.attrs.get('data-tippy-content') or link.attrs.get('title') or link.text()
        rating = next((n for n in row.all('td') if n.attrs.get('data-col') == 'oa'), None)
        rating_match = re.fullmatch(r'(\d{1,2})(?:\s+[+\-−]\d{1,2})?', rating.text()) if rating else None
        if rating_match is None:
            raise ValueError(f'Player {pid}: overall rating missing/invalid; refusing partial roster.')
        overall = int(rating_match.group(1))
        position = next((n.text() for n in row.all() if 'pos' in n.attrs.get('class','').split()), '')
        flag = next((n for n in row.all('img') if 'flag' in n.attrs.get('class','').split()), None)
        portrait = next((image_url(n) for n in row.all('img') if '/players/' in (n.attrs.get('data-src') or n.attrs.get('src',''))), None)
        if not name or not position or not 1 <= overall <= 99:
            raise ValueError(f'Player {pid}: incomplete identity, position or rating.')
        player = {'id':pid,'name':name.strip(),'ovr':overall,'position':position,
                  'country':flag.attrs.get('title') if flag else None,'headshotUrl':portrait}
        if pid in players and players[pid] != player:
            raise ValueError(f'Conflicting rows for player {pid}.')
        players[pid] = player
    if not 18 <= len(players) <= 80:
        raise ValueError(f'Team {team_id}: suspicious squad size {len(players)}; expected 18–80.')
    crest, team_name = None, fallback_name
    for script in doc.all('script'):
        if script.attrs.get('type') != 'application/ld+json':
            continue
        try:
            meta = json.loads(script.text())
        except (ValueError,TypeError):
            continue
        if isinstance(meta,dict) and meta.get('@type') == 'Organization' and re.search(rf'/team/{team_id}(?:/|$)',meta.get('url','')):
            team_name = meta.get('name') or fallback_name
            if isinstance(meta.get('logo'),str):
                crest = image_url(Node('img',[('src',meta['logo'])]))
    return {'id':team_id,'name':team_name,'crestUrl':crest,'players':list(players.values())}


def fetch(url):
    # Explicit identity; no stealth, challenge solving, proxy rotation or browser cookies.
    request = Request(url, headers={'User-Agent':'MercattoCatalogSync/1.0','Accept':'text/html','Accept-Language':'en-US,en;q=0.8'})
    try:
        with urlopen(request, timeout=40) as response:
            if urlparse(response.url).hostname not in ('sofifa.com','www.sofifa.com'):
                raise ValueError('Unexpected redirect destination.')
            if 'text/html' not in response.headers.get('Content-Type',''):
                raise ValueError('Expected HTML from SoFIFA.')
            html = response.read(8_000_001)
            if len(html)>8_000_000:
                raise ValueError('HTML response too large.')
            return html.decode('utf-8')
    except HTTPError as error:
        raise RuntimeError(f'SoFIFA HTTP {error.code} for {url}; stopped without importing.') from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--saved-html', help='Validate one saved team page only; does not claim it is the latest live edition or import it.')
    args = parser.parse_args()
    teams = json.loads((ROOT/'sofifa-teams.json').read_text(encoding='utf-8'))
    if args.saved_html:
        html = Path(args.saved_html).read_text(encoding='utf-8')
        doc = document(html)
        canonical = next((n.attrs.get('href','') for n in doc.all('link') if n.attrs.get('rel')=='canonical'),'')
        match = re.search(r'/team/(\d+)/(?:[^/?#]+/)?(\d{6})(?:/|$)',canonical)
        if not match:
            raise ValueError('Saved page must identify its team and edition.')
        team_id, revision = map(int,match.groups())
        config = next((t for t in teams if t['id']==team_id),None)
        if not config:
            raise ValueError('Team is not in the configured list.')
        team = parse_team(html,team_id,revision,config['name'])
        output = Path(args.output)
        output.parent.mkdir(parents=True,exist_ok=True)
        output.write_text(json.dumps({'source':'sofifa-saved-html','revision':revision,'latestListedInSavedPage':max(revisions(doc)),'teams':[team]},ensure_ascii=False,indent=2),encoding='utf-8')
        print(f'Saved HTML validated: {len(team["players"])} active players, edition {revision}. Preview only: {output}')
        return
    # No edition in the entry URL: discover the newest edition offered by the site each run.
    first = fetch(f'https://sofifa.com/team/{teams[0]["id"]}/?hl=en-US')
    available = revisions(document(first))
    if not available:
        raise ValueError('Cannot identify the latest SoFIFA edition; refusing to guess.')
    revision = max(available)
    result = []
    receipts = []
    for team in teams:
        time.sleep(2)
        url = f'https://sofifa.com/team/{team["id"]}/{revision}/?hl=en-US'
        html = fetch(url)
        data = parse_team(html, team['id'], revision, team['name'])
        result.append(data)
        receipts.append({'url':url,'sha256':hashlib.sha256(html.encode()).hexdigest()})
        print(f'{team["name"]}: {len(data["players"])} players, edition {revision}', flush=True)
    ids = [p['id'] for t in result for p in t['players']]
    if len(ids) != len(set(ids)):
        raise ValueError('A player appears in more than one selected club; import aborted.')
    # Detect a release during the download instead of committing a mixed/stale batch.
    if max(revisions(document(fetch(f'https://sofifa.com/team/{teams[0]["id"]}/?hl=en-US')))) != revision:
        raise ValueError('Latest edition changed during download. Run again.')
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.tmp')
    temporary.write_text(json.dumps({'source':'sofifa','revision':revision,'fetchedAt':datetime.now(timezone.utc).isoformat(),'teams':result,'receipts':receipts},ensure_ascii=False,indent=2),encoding='utf-8')
    temporary.replace(output)
    print(f'Validated snapshot: {output}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError,RuntimeError,OSError) as error:
        raise SystemExit(str(error))
