"""Synthetic parser fixtures. These are not claimed to be a live SoFIFA export."""
import unittest
from scrape_sofifa import parse_team, revisions, document


def page(count=18):
    rows=''.join(f'<tr><td><a href="/player/{200001+i}/person/270003/">Person {i}</a><span class="pos">ST</span><img class="flag" title="Spain"></td><td data-col="oa"><em>85</em></td></tr>' for i in range(count))
    return f'<html><head><link rel="canonical" href="https://sofifa.com/team/5/chelsea/270003/"></head><body><article><h5>Squad</h5><table>{rows}</table></article><a href="?r=270004">New release</a></body></html>'


class ParserTests(unittest.TestCase):
    def test_rating_with_change_indicator(self):
        for delta in (' +1', ' -2', ' −2'):
            html=page().replace('<em>85</em>',f'<em>85</em><span>{delta}</span>')
            self.assertTrue(all(p['ovr']==85 for p in parse_team(html,5,270003,'Chelsea')['players']))

    def test_roster(self):
        team=parse_team(page(),5,270003,'Chelsea')
        self.assertEqual(len(team['players']),18)
        self.assertEqual(team['players'][0]['id'],200001)

    def test_latest_does_not_confuse_player_id_with_revision(self):
        self.assertEqual(max(revisions(document(page().replace('/player/200001/','/player/999999/')))),270004)

    def test_incomplete_and_challenge(self):
        for html in (page(3),page().replace('data-col="oa"','data-col="pt"'),page()[:-7],'<html>Just a moment</html>'):
            with self.assertRaises(ValueError):
                parse_team(html,5,270003,'Chelsea')

    def test_wrong_team_and_edition(self):
        for team,revision in ((1,270003),(5,270002)):
            with self.assertRaises(ValueError):
                parse_team(page(),team,revision,'Chelsea')

    def test_loaned_out_not_in_squad(self):
        loan='<article><h5>On loan</h5><table><tr><td><a href="/player/1/out/270003/">Out</a></td></tr></table></article>'
        self.assertEqual(len(parse_team(page().replace('</body>',loan+'</body>'),5,270003,'Chelsea')['players']),18)

    def test_shared_article_and_team_metadata(self):
        loan='<h5>On loan</h5><table><tr><td><a href="/player/1/out/270003/">Out</a></td></tr></table>'
        html=page().replace('</article>',loan+'</article>')
        html=html.replace('</head>','<script type="application/ld+json">{"@type":"Organization","url":"https://sofifa.com/team/5/chelsea/","name":"Chelsea","logo":"https://cdn.sofifa.net/teams/5/360.png"}</script></head>')
        team=parse_team(html,5,270003,'Fallback')
        self.assertEqual(len(team['players']),18)
        self.assertEqual(team['crestUrl'],'https://cdn.sofifa.net/teams/5/360.png')
        self.assertEqual(team['name'],'Chelsea')

    def test_revision_selectors_without_slug(self):
        html=page().replace('</body>','<select id="select-roster"><option value="/team/5/270005/">New</option><option value="/team/5/270003/">Old</option></select></body>')
        self.assertEqual(revisions(document(html)),{270005,270003})


if __name__=='__main__':
    unittest.main()
