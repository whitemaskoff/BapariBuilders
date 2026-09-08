/*
# Apply down payment on "Send updated terms" without buyer confirmation

After the buyer has accepted, sending updated terms:
- Does not change the fixed total price
- Treats the entered down payment as an additional payment
- Adds it to total_paid immediately
- Recalculates remaining_balance
- Does not send the deal back to terms_sent (no buyer re-confirm)
*/

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
  v_new_total_paid numeric;
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
    RETURN jsonb_build_object('buyer_token', v_deal.buyer_token, 'action', 'reminder');
  END IF;

  IF v_deal.status IN ('buyer_accepted', 'seller_confirmed', 'active') THEN
    IF p_new_down_payment IS NULL OR p_new_down_payment <= 0 THEN
      RAISE EXCEPTION 'Down payment must be greater than 0';
    END IF;

    v_new_total_paid := COALESCE(v_deal.total_paid, 0) + p_new_down_payment;
    v_remaining := v_deal.total_price - v_new_total_paid;

    IF v_remaining < 0 THEN
      RAISE EXCEPTION 'Down payment exceeds remaining balance of %', v_deal.remaining_balance;
    END IF;

    INSERT INTO payments (deal_id, amount, photo_url, recorded_by, note)
    VALUES (
      p_deal_id,
      p_new_down_payment,
      '',
      auth.uid(),
      'Down payment applied from updated terms'
    );

    UPDATE deals SET
      total_paid = v_new_total_paid,
      remaining_balance = v_remaining,
      status = CASE WHEN v_remaining = 0 THEN 'done' ELSE status END
    WHERE id = p_deal_id;

    IF v_remaining = 0 THEN
      UPDATE orders SET status = 'completed' WHERE id = v_deal.order_id;
    END IF;

    INSERT INTO notifications (user_id, type, title, message, data)
    SELECT
      p.id,
      'payment_recorded',
      'Down payment applied',
      'Payment of ' || p_new_down_payment || ' recorded. Total paid: ' || v_new_total_paid || ', Remaining: ' || v_remaining,
      jsonb_build_object('deal_id', p_deal_id)
    FROM profiles p;

    RETURN jsonb_build_object(
      'buyer_token', v_deal.buyer_token,
      'action', 'payment_applied',
      'total_price', v_deal.total_price,
      'total_paid', v_new_total_paid,
      'remaining_balance', v_remaining,
      'amount_added', p_new_down_payment
    );
  END IF;

  RAISE EXCEPTION 'Deal is not in a state where terms can be updated (current: %)', v_deal.status;
END;
$$;

GRANT EXECUTE ON FUNCTION resend_deal_terms(uuid, numeric, numeric) TO authenticated;
REVOKE EXECUTE ON FUNCTION resend_deal_terms(uuid, numeric, numeric) FROM anon, public;
