-- Deterministic seed: 150 bookings, 5 organizations, 6 cities, 4 statuses.
INSERT INTO hotel_bookings
    (id, org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at)
SELECT
    md5('booking-' || g)::uuid,
    md5('org-' || ((g % 5) + 1))::uuid,
    'hotel-' || ((g % 25) + 1),
    (ARRAY['delhi', 'mumbai', 'pune', 'jaipur', 'goa', 'bengaluru'])[((g - 1) % 6) + 1],
    CURRENT_DATE + ((g % 45) - 10),
    CURRENT_DATE + ((g % 45) - 7),
    (1000 + (g * 137) % 25000)::numeric(12,2),
    (ARRAY['confirmed', 'cancelled', 'pending', 'completed'])[((g - 1) % 4) + 1],
    NOW() - ((g % 60) || ' days')::interval
FROM generate_series(1, 150) AS g
ON CONFLICT (id) DO NOTHING;

INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    b.id,
    e.event_type,
    jsonb_build_object('source', 'seed', 'status', b.status, 'city', b.city),
    b.created_at + interval '5 minutes'
FROM hotel_bookings b
JOIN (VALUES ('booking_created'), ('payment_processed')) AS e(event_type) ON true
WHERE (substring(b.id::text, 1, 1) IN ('0', '2', '4', '6', '8', 'a', 'c', 'e'))
ON CONFLICT DO NOTHING;

ANALYZE hotel_bookings;
ANALYZE booking_events;
