CREATE FUNCTION game.emit_club_notification(tid uuid,cid uuid,kind text,title text,body text,event text) RETURNS void LANGUAGE sql SET search_path='' AS $$
 INSERT INTO public.notifications(member_id,tournament_id,type,title,body,metadata)
 SELECT a.member_id,tid,kind,title,body,jsonb_build_object('event',event) FROM game.assignments a WHERE a.tournament_id=tid AND a.club_id=cid AND a.ended_at IS NULL;
$$;
CREATE FUNCTION game.notify_event() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE club uuid; label text; kind text; BEGIN
 IF TG_TABLE_NAME='offers' THEN
  IF TG_OP='INSERT' THEN kind:='offer_received';label:='Nueva oferta';
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN kind:='offer_'||NEW.status;label:='Oferta actualizada';
  ELSIF NEW.proposal_revision IS DISTINCT FROM OLD.proposal_revision THEN kind:='offer_countered';label:='Nueva contraoferta';
  ELSE RETURN NEW; END IF;
  IF TG_OP='INSERT' THEN PERFORM game.emit_club_notification(NEW.tournament_id,NEW.seller_club_id,kind,label,'Revisa las ofertas del mercado.',NEW.id::text);
  ELSE
   PERFORM game.emit_club_notification(NEW.tournament_id,NEW.buyer_club_id,kind,label,'Revisa las ofertas del mercado.',NEW.id::text);
   PERFORM game.emit_club_notification(NEW.tournament_id,NEW.seller_club_id,kind,label,'Revisa las ofertas del mercado.',NEW.id::text);
  END IF;
 ELSIF TG_TABLE_NAME='transfers' THEN
  PERFORM game.emit_club_notification(NEW.tournament_id,NEW.buyer_club_id,'transfer_completed','Fichaje completado','Tu plantilla y presupuesto se actualizaron.',NEW.id::text);
  IF NEW.seller_club_id IS NOT NULL THEN PERFORM game.emit_club_notification(NEW.tournament_id,NEW.seller_club_id,'transfer_completed','Venta completada','Tu plantilla y presupuesto se actualizaron.',NEW.id::text); END IF;
 ELSIF TG_TABLE_NAME='market_windows' AND NEW.status='closed' AND OLD.status='open' THEN
  FOR club IN SELECT id FROM game.clubs WHERE tournament_id=NEW.tournament_id LOOP
   PERFORM game.emit_club_notification(NEW.tournament_id,club,'market_closed','Mercado cerrado','Las ofertas pendientes se cerraron.',NEW.id::text);
  END LOOP;
 ELSIF TG_TABLE_NAME='auctions' THEN
  IF TG_OP='INSERT' THEN
   FOR club IN SELECT id FROM game.clubs WHERE tournament_id=NEW.tournament_id LOOP
    PERFORM game.emit_club_notification(NEW.tournament_id,club,'auction_started','Subasta abierta','Ya puedes pujar por el icono.',NEW.id::text);
   END LOOP;
  ELSIF NEW.highest_club_id IS DISTINCT FROM OLD.highest_club_id AND OLD.highest_club_id IS NOT NULL THEN
   PERFORM game.emit_club_notification(NEW.tournament_id,OLD.highest_club_id,'auction_outbid','Han superado tu puja','Revisa la subasta.',NEW.id::text);
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER notify_offer AFTER INSERT OR UPDATE ON game.offers FOR EACH ROW EXECUTE FUNCTION game.notify_event();
CREATE TRIGGER notify_transfer AFTER INSERT ON game.transfers FOR EACH ROW EXECUTE FUNCTION game.notify_event();
CREATE TRIGGER notify_market_close AFTER UPDATE ON game.market_windows FOR EACH ROW EXECUTE FUNCTION game.notify_event();
CREATE TRIGGER notify_auction AFTER INSERT OR UPDATE ON game.auctions FOR EACH ROW EXECUTE FUNCTION game.notify_event();

CREATE FUNCTION public.game_claim_push(p_limit integer DEFAULT 5) RETURNS SETOF public.notifications LANGUAGE sql SET search_path='' AS $$
 UPDATE public.notifications n SET push_attempted_at=clock_timestamp()
 WHERE n.id IN(SELECT id FROM public.notifications WHERE push_sent_at IS NULL
 AND created_at>clock_timestamp()-interval '1 day'
 AND (push_attempted_at IS NULL OR push_attempted_at<clock_timestamp()-interval '5 minutes')
 ORDER BY created_at LIMIT greatest(1,least(p_limit,20)) FOR UPDATE SKIP LOCKED) RETURNING n.*;
$$;
REVOKE ALL ON FUNCTION public.game_claim_push(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_claim_push(integer) TO service_role;
NOTIFY pgrst,'reload schema';
