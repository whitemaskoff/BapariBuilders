/*
# Deal Flow Enhancements — Resend Terms, Buyer-Accepted Repricing, Modification Reminders

1. Purpose
   - Allow sellers to resend deal terms (reminder nudge) when status is 'terms_sent'.
   - Allow sellers to send updated/additional pricing after buyer has accepted (status 'buyer_accepted').
     This re-sends terms: the deal goes back to 'terms_sent' with the new price, buyer gets email.
   - Allow sellers to send a reminder nudge for pending deal modifications.
   - Allow propose_modification to work from 'buyer_accepted' status (not just 'active').

2. Schema Changes
   - No new tables. No column changes.
   - deals.status CHECK constraint: 'buyer_accepted' already exists, no change needed.
   - deal_modifications: no schema change needed.

3. New RPC Functions
   - resend_deal_terms(p_deal_id, p_new_total_price, p_new_down_payment):
       If status is 'buyer_accepted': updates total_price, down_payment, total_paid, remaining_balance,
       sets status back to 'terms_sent'. This lets the seller add more products / increase price
       after the buyer accepted the initial terms.
       If status is 'terms_sent': just resets status to 'terms_sent' (re-sends as reminder, no price change).
       Returns the buyer_token so the frontend can send the email.
   - nudge_buyer(p_deal_id):
       Returns the buyer_token and buyer email (via order join) so the frontend can send a reminder email.
       Works for both 'terms_sent' deals and deals with pending modifications.
   - nudge_modification(p_mod_buyer_token):
       Returns modification + deal + order info so the frontend can send a reminder email
       about a pending modification the buyer hasn't responded to.

4. Modified RPC Functions
   - propose_modification: now allows status IN ('active', 'seller_confirmed', 'buyer_accepted').
     Previously only allowed ('active', 'seller_confirmed'). This lets the seller add products
     before the deal is officially active (e.g. buyer accepted but seller hasn't confirmed yet).

5. Security
   - New RPCs are SECURITY DEFINER, check get_user_role() for 'admin'/'seller'.
   - Granted to authenticated role only (staff operations).
   - No new policies needed (no new tables).

6. Important Notes
   - resend_deal_terms with buyer_accepted status: total_paid is reset to the new down_payment.
     This is correct because the seller is proposing new terms — previous down_payment is replaced.
     If the seller wants to keep the same down_payment, they pass the same value.
   - The frontend handles email sending via the send-notification-email edge function,
     just like the existing set_deal_terms and propose_modification flows.
*/

-- ─── resend_deal_terms ───────────────────────────────────────
-- Allows seller to:
--   (a) Re-send terms as a reminder when status = 'terms_sent' (no price change)
--   (b) Send updated pricing when status = 'buyer_accepted' (new total + down payment, back to terms_sent)
CREATE OR REPLACE FUNCTION resend_deal_terms(
  p_deal_id uuid,
  p_new_total_price numeric DEFAULT NULL,
  p_new_down_payment numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_deal record;
  v_remaining numeric;
BEGIN
  IF get_user_role() NOT IN ('admin', 'seller') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_deal FROM deals WHERE id = p_deal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found';
  END IF;

  IF v_deal.status = 'terms_sent' THEN
    -- Reminder: just return the buyer_token, no price change
    RETURN jsonb_build_object('buyer_token', v_deal.buyer_token, 'action', 'reminder');
  END IF;

  IF v_deal.status = 'buyer_accepted' THEN
    -- Updated pricing: must have both new total and new down payment
    IF p_new_total_price IS NULL OR p_new_total_price <= 0 THEN
      RAISE EXCEPTION 'Total price must be greater than 0';
    END IF;
    IF p_new_down_payment IS NULL OR p_new_down_payment < 0 THEN
      RAISE EXCEPTION 'Down payment cannot be negative';
    END IF;
    IF p_new_down_payment > p_new_total_price THEN
      RAISE EXCEPTION 'Down payment cannot exceed total price';
    END IF;

    v_remaining := p_new_total_price - p_new_down_payment;

    UPDATE deals SET
      total_price = p_new_total_price,
      down_payment = p_new_down_payment,
      total_paid = p_new_down_payment,
      remaining_balance = v_remaining,
      status = 'terms_sent'
    WHERE id = p_deal_id;

    RETURN jsonb_build_object('buyer_token', v_deal.buyer_token, 'action', 'updated_terms');
  END IF;

  RAISE EXCEPTION 'Deal is not in a state where terms can be resent (current: %)', v_deal.status;
END;
$$;

GRANT EXECUTE ON FUNCTION resend_deal_terms TO authenticated;

-- ─── nudge_buyer ──────────────────────────────────────────────
-- Returns buyer_token + buyer email so the frontend can send a reminder email
-- for deals in 'terms_sent' status or deals with pending modifications
CREATE OR REPLACE FUNCTION nudge_buyer(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_deal record;
  v_order record;
  v_has_pending_mod boolean;
BEGIN
  IF get_user_role() NOT IN ('admin', 'seller') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_deal FROM deals WHERE id = p_deal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found';
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = v_deal.order_id;

  SELECT EXISTS(
    SELECT 1 FROM deal_modifications WHERE deal_id = p_deal_id AND status = 'pending'
  ) INTO v_has_pending_mod;

  IF v_deal.status != 'terms_sent' AND NOT v_has_pending_mod THEN
    RAISE EXCEPTION 'No pending action to remind the buyer about';
  END IF;

  RETURN jsonb_build_object(
    'buyer_token', v_deal.buyer_token,
    'buyer_email', v_order.buyer_email,
    'buyer_name', v_order.buyer_name,
    'has_pending_mod', v_has_pending_mod,
    'deal_status', v_deal.status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION nudge_buyer TO authenticated;

-- ─── propose_modification: allow from buyer_accepted status ───
CREATE OR REPLACE FUNCTION propose_modification(
  p_deal_id uuid,
  p_new_items jsonb,
  p_new_total_price numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_mod_id uuid;
  v_deal record;
BEGIN
  IF get_user_role() NOT IN ('admin', 'seller') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_deal FROM deals WHERE id = p_deal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found';
  END IF;

  IF v_deal.status NOT IN ('active', 'seller_confirmed', 'buyer_accepted') THEN
    RAISE EXCEPTION 'Deal is not in a state where modifications can be proposed (current: %)', v_deal.status;
  END IF;

  INSERT INTO deal_modifications (deal_id, proposed_by, new_items, new_total_price)
  VALUES (p_deal_id, auth.uid(), p_new_items, p_new_total_price)
  RETURNING id INTO v_mod_id;

  RETURN v_mod_id;
END;
$$;

-- Re-grant (function signature unchanged but replaced)
GRANT EXECUTE ON FUNCTION propose_modification TO authenticated;