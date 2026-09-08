CREATE OR REPLACE FUNCTION delete_ongoing_deal(p_deal_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_deal record;
BEGIN
  IF get_user_role() NOT IN ('admin', 'seller') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_deal FROM deals WHERE id = p_deal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found';
  END IF;

  IF v_deal.status NOT IN ('pending_terms', 'terms_sent', 'buyer_accepted', 'seller_confirmed', 'active') THEN
    RAISE EXCEPTION 'Only ongoing deals can be deleted';
  END IF;

  UPDATE orders SET status = 'rejected' WHERE id = v_deal.order_id;
  DELETE FROM deals WHERE id = p_deal_id;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_ongoing_deal(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION delete_ongoing_deal(uuid) FROM anon, public;
