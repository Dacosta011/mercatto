import {assertLocal,sql} from './db-local.mjs';
import {mkdirSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
assertLocal();
const report=JSON.parse(sql(`SELECT jsonb_build_object(
 'destination','local only','legacyTournaments',(SELECT count(*) FROM public.tournaments WHERE status<>'prototype'),
 'clubGames',(SELECT count(*) FROM game.tournaments),'completeGames',(SELECT count(*) FROM game.rules),
 'catalogueDuplicateOwners',(SELECT count(*) FROM (SELECT player_id FROM public.team_players GROUP BY player_id HAVING count(*)>1) x),
 'crossTournamentPosts',(SELECT count(*) FROM public.posts p JOIN public.members m ON m.id=p.member_id WHERE p.tournament_id<>m.tournament_id),
 'unbalancedOperations',(SELECT count(*) FROM (SELECT operation_id FROM game.ledger GROUP BY operation_id HAVING sum(amount)<>0) x),
 'accountLedgerMismatches',(SELECT count(*) FROM game.accounts a WHERE a.balance<>(SELECT coalesce(sum(amount),0) FROM game.ledger WHERE account_id=a.id)),
 'duplicateActiveOwners',(SELECT count(*) FROM (SELECT tournament_id,player_id FROM game.contracts WHERE ended_at IS NULL GROUP BY tournament_id,player_id HAVING count(*)>1) x),
 'duplicateActiveAssignments',(SELECT count(*) FROM (SELECT tournament_id,club_id FROM game.assignments WHERE ended_at IS NULL GROUP BY tournament_id,club_id HAVING count(*)>1) x),
 'missingFixtureFinance',(SELECT count(*) FROM game.fixtures f WHERE f.status='finished' AND (SELECT count(*) FROM game.operations o WHERE o.tournament_id=f.tournament_id AND o.kind='match_expenses' AND o.payload->>'fixture'=f.id::text)<>2),
 'uncoveredDebt',(SELECT coalesce(sum(amount),0) FROM game.debts),
 'legacyReconstruction','No historical transactions invented. Existing public games remain archived for an explicit reviewed import.'
);`).trim());
const folder=new URL('../.local-db/',import.meta.url);mkdirSync(folder,{recursive:true});const output=new URL('migration-audit.json',folder);writeFileSync(output,JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));console.log(`Audit saved: ${fileURLToPath(output)}`);
if(['unbalancedOperations','accountLedgerMismatches','duplicateActiveOwners','duplicateActiveAssignments','missingFixtureFinance'].some(key=>report[key]!==0))throw new Error('Local game integrity audit failed');
