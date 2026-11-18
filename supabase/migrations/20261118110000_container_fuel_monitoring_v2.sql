-- MERA Container Fuel Monitoring V2
-- Existing V1 reporting function remains unchanged.
CREATE OR REPLACE FUNCTION public.dashboard_container_fuel_report_v2(
    p_start_date date DEFAULT NULL,
    p_end_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_result jsonb;
BEGIN
    IF NOT (
        public.can_access_dashboard()
        AND (
            public.current_staff_role() = 'ADMIN'
            OR (
                public.current_staff_role() = 'MERA'
                AND (
                    public.has_fuel_request_permission('FUEL_REQUEST_VIEWER')
                    OR public.has_fuel_request_permission('FUEL_REQUEST_ADMIN')
                )
            )
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized to view container fuel monitoring data';
    END IF;

    IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_start_date > p_end_date THEN
        RAISE EXCEPTION 'Start date cannot be after end date';
    END IF;

    WITH latest_confirmations AS (
        SELECT DISTINCT ON (c.allocation_id)
            c.allocation_id, c.confirmation_status, c.confirmed_litres,
            c.confirmed_at, c.created_at, c.id
        FROM public.fuel_request_station_confirmations c
        ORDER BY c.allocation_id, c.created_at DESC, c.id DESC
    ),
    allocation_base AS (
        SELECT
            a.id AS allocation_id,
            a.request_item_id,
            a.filling_station_id AS station_id,
            a.allocation_status,
            a.allocated_litres,
            a.dispensed_litres,
            a.allocated_at,
            (a.allocated_at AT TIME ZONE 'Africa/Blantyre')::date AS allocated_date,
            i.request_id, UPPER(i.product) AS product,
            i.requested_litres, i.approved_litres,
            r.request_number, r.applicant_id, r.applicant_type,
            r.applicant_name, r.company_name, r.phone_number,
            r.status AS request_status,
            CASE WHEN r.applicant_id IS NOT NULL
                THEN 'REGISTERED:' || r.applicant_id::text
                ELSE 'REQUEST:' || r.id::text END AS customer_key,
            COALESCE(fs.name, 'Unknown station') AS station_name,
            COALESCE(o.name, NULLIF(fs.omc, ''), 'Unassigned') AS omc_name,
            COALESCE(d.name, 'Unknown district') AS district_name,
            c.confirmation_status, c.confirmed_litres, c.confirmed_at,
            (c.confirmed_at AT TIME ZONE 'Africa/Blantyre')::date AS confirmed_date,
            (c.created_at AT TIME ZONE 'Africa/Blantyre')::date AS confirmation_created_date
        FROM public.fuel_request_allocations a
        JOIN public.fuel_request_items i ON i.id = a.request_item_id
        JOIN public.fuel_requests r ON r.id = i.request_id
        LEFT JOIN public.filling_stations fs ON fs.id = a.filling_station_id
        LEFT JOIN public.omcs o ON o.id = fs.omc_id
        LEFT JOIN public.districts d ON d.id = fs.district_id
        LEFT JOIN latest_confirmations c ON c.allocation_id = a.id
    ),
    consumed AS (
        SELECT * FROM allocation_base
        WHERE confirmation_status = 'CONFIRMED'
          AND confirmed_at IS NOT NULL
          AND allocation_status = 'COMPLETED'
          AND (p_start_date IS NULL OR confirmed_date >= p_start_date)
          AND (p_end_date IS NULL OR confirmed_date <= p_end_date)
    ),
    filtered_allocations AS (
        SELECT * FROM allocation_base
        WHERE (p_start_date IS NULL OR allocated_date >= p_start_date)
          AND (p_end_date IS NULL OR allocated_date <= p_end_date)
    ),
    filtered_confirmations AS (
        SELECT * FROM allocation_base
        WHERE confirmation_status IS NOT NULL
          AND (p_start_date IS NULL OR confirmation_created_date >= p_start_date)
          AND (p_end_date IS NULL OR confirmation_created_date <= p_end_date)
    ),
    filtered_requests AS (
        SELECT r.* FROM public.fuel_requests r
        WHERE (p_start_date IS NULL OR (r.created_at AT TIME ZONE 'Africa/Blantyre')::date >= p_start_date)
          AND (p_end_date IS NULL OR (r.created_at AT TIME ZONE 'Africa/Blantyre')::date <= p_end_date)
    ),
    filtered_items AS (
        SELECT i.*, r.status AS request_status, r.approved_at
        FROM public.fuel_request_items i
        JOIN public.fuel_requests r ON r.id = i.request_id
        WHERE (p_start_date IS NULL OR (r.created_at AT TIME ZONE 'Africa/Blantyre')::date >= p_start_date)
          AND (p_end_date IS NULL OR (r.created_at AT TIME ZONE 'Africa/Blantyre')::date <= p_end_date)
    ),
    date_bounds AS (
        SELECT
            COALESCE(p_start_date, (SELECT MIN(confirmed_date) FROM consumed),
                (now() AT TIME ZONE 'Africa/Blantyre')::date - 6) AS first_day,
            COALESCE(p_end_date, (SELECT MAX(confirmed_date) FROM consumed),
                (now() AT TIME ZONE 'Africa/Blantyre')::date) AS last_day
    ),
    daily_totals AS (
        SELECT confirmed_date AS day,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'PETROL'), 0) AS petrol_litres,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'DIESEL'), 0) AS diesel_litres,
            COALESCE(SUM(confirmed_litres), 0) AS total_litres
        FROM consumed GROUP BY confirmed_date
    ),
    daily_series AS (
        SELECT g.day::date AS day,
            COALESCE(t.petrol_litres, 0) AS petrol_litres,
            COALESCE(t.diesel_litres, 0) AS diesel_litres,
            COALESCE(t.total_litres, 0) AS total_litres
        FROM date_bounds b
        CROSS JOIN LATERAL generate_series(
            GREATEST(b.first_day, b.last_day - 3660), b.last_day, interval '1 day'
        ) AS g(day)
        LEFT JOIN daily_totals t ON t.day = g.day::date
    ),
    weekly_series AS (
        SELECT date_trunc('week', day::timestamp)::date AS week_start,
            SUM(petrol_litres) AS petrol_litres,
            SUM(diesel_litres) AS diesel_litres,
            SUM(total_litres) AS total_litres
        FROM daily_series GROUP BY 1
    ),
    monthly_series AS (
        SELECT date_trunc('month', day::timestamp)::date AS month_start,
            SUM(petrol_litres) AS petrol_litres,
            SUM(diesel_litres) AS diesel_litres,
            SUM(total_litres) AS total_litres
        FROM daily_series GROUP BY 1
    ),
    station_totals AS (
        SELECT station_id, station_name, omc_name, district_name,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'PETROL'), 0) AS petrol_litres,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'DIESEL'), 0) AS diesel_litres,
            SUM(confirmed_litres) AS total_litres,
            COUNT(DISTINCT allocation_id) AS confirmed_allocations,
            COUNT(DISTINCT customer_key) AS customer_keys
        FROM consumed GROUP BY station_id, station_name, omc_name, district_name
    ),
    omc_totals AS (
        SELECT omc_name,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'PETROL'), 0) AS petrol_litres,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'DIESEL'), 0) AS diesel_litres,
            SUM(confirmed_litres) AS total_litres,
            COUNT(DISTINCT station_id) AS stations_used,
            COUNT(DISTINCT allocation_id) AS confirmed_allocations
        FROM consumed GROUP BY omc_name
    ),
    district_totals AS (
        SELECT district_name,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'PETROL'), 0) AS petrol_litres,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'DIESEL'), 0) AS diesel_litres,
            SUM(confirmed_litres) AS total_litres,
            COUNT(DISTINCT station_id) AS stations_used,
            COUNT(DISTINCT allocation_id) AS confirmed_allocations
        FROM consumed GROUP BY district_name
    ),
    customer_totals AS (
        SELECT customer_key, MAX(applicant_name) AS customer,
            MAX(company_name) AS company,
            MAX(applicant_id::text) AS applicant_id,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'PETROL'), 0) AS petrol_litres,
            COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'DIESEL'), 0) AS diesel_litres,
            SUM(confirmed_litres) AS total_litres,
            COUNT(DISTINCT allocation_id) AS confirmed_allocations,
            COUNT(DISTINCT station_id) AS stations_visited,
            MIN(confirmed_date) AS first_confirmed_date,
            MAX(confirmed_date) AS last_confirmed_date
        FROM consumed GROUP BY customer_key
    ),
    allowance_rows AS (
        SELECT l.applicant_id, a.applicant_name,
            UPPER(l.product) AS product,
            UPPER(l.allowance_type) AS allowance_type,
            COALESCE(l.limit_litres, l.monthly_limit_litres) AS allowance_litres
        FROM public.fuel_applicant_limits l
        JOIN public.fuel_applicants a ON a.id = l.applicant_id
        WHERE l.active = true
    ),
    monthly_allowances AS (
        SELECT ar.applicant_id, ar.applicant_name, ar.product,
            ar.allowance_litres,
            COALESCE((
                SELECT SUM(ab.confirmed_litres)
                FROM allocation_base ab
                WHERE ab.applicant_id = ar.applicant_id
                  AND ab.product = ar.product
                  AND ab.confirmation_status = 'CONFIRMED'
                  AND ab.allocation_status = 'COMPLETED'
                  AND ab.confirmed_at IS NOT NULL
                  AND date_trunc('month', ab.confirmed_date::timestamp) =
                      date_trunc('month', (now() AT TIME ZONE 'Africa/Blantyre')::timestamp)
            ), 0) AS current_month_confirmed_litres
        FROM allowance_rows ar WHERE ar.allowance_type = 'MONTHLY'
    )
    SELECT jsonb_build_object(
        'metadata', jsonb_build_object(
            'timezone', 'Africa/Blantyre',
            'start_date', p_start_date,
            'end_date', p_end_date,
            'trend_start_date', (SELECT first_day FROM date_bounds),
            'trend_end_date', (SELECT last_day FROM date_bounds),
            'trend_truncated_to_3661_days',
                (SELECT last_day - first_day > 3660 FROM date_bounds),
            'consumption_basis', 'Latest CONFIRMED station confirmation on COMPLETED allocation',
            'request_metrics_basis', 'Request creation date',
            'allocation_metrics_basis', 'Allocation date',
            'confirmation_metrics_basis', 'Confirmation record creation date',
            'one_off_identity_note', 'One-off requests are distinct request keys, not verified unique persons',
            'allowance_basis', 'Current Malawi calendar month; active MONTHLY limits only'
        ),
        'summary', (
            SELECT jsonb_build_object(
                'petrol_litres', COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'PETROL'), 0),
                'diesel_litres', COALESCE(SUM(confirmed_litres) FILTER (WHERE product = 'DIESEL'), 0),
                'total_litres', COALESCE(SUM(confirmed_litres), 0),
                'confirmed_allocations', COUNT(DISTINCT allocation_id),
                'unique_customers', COUNT(DISTINCT customer_key),
                'registered_customers', COUNT(DISTINCT applicant_id) FILTER (WHERE applicant_id IS NOT NULL),
                'one_off_requests_confirmed', COUNT(DISTINCT request_id) FILTER (WHERE applicant_id IS NULL),
                'stations_used', COUNT(DISTINCT station_id),
                'omcs_used', COUNT(DISTINCT omc_name),
                'districts_used', COUNT(DISTINCT district_name)
            ) FROM consumed
        ),
        'trends', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'date', day, 'petrol_litres', petrol_litres,
            'diesel_litres', diesel_litres, 'total_litres', total_litres
        ) ORDER BY day), '[]'::jsonb) FROM daily_series),
        'weekly_trends', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'week_start', week_start, 'petrol_litres', petrol_litres,
            'diesel_litres', diesel_litres, 'total_litres', total_litres
        ) ORDER BY week_start), '[]'::jsonb) FROM weekly_series),
        'monthly_trends', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'month_start', month_start, 'petrol_litres', petrol_litres,
            'diesel_litres', diesel_litres, 'total_litres', total_litres
        ) ORDER BY month_start), '[]'::jsonb) FROM monthly_series),
        'history', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'allocation_id', allocation_id, 'request_id', request_id,
            'request_number', request_number, 'customer', applicant_name,
            'company', company_name, 'applicant_id', applicant_id,
            'customer_key', customer_key, 'product', product,
            'litres', confirmed_litres, 'allocated_litres', allocated_litres,
            'dispensed_litres', dispensed_litres,
            'confirmed_at', confirmed_at, 'date', confirmed_date,
            'station', station_name, 'omc', omc_name, 'district', district_name
        ) ORDER BY confirmed_at DESC), '[]'::jsonb) FROM consumed),
        'stations', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'station_id', station_id, 'station', station_name, 'omc', omc_name,
            'district', district_name, 'petrol_litres', petrol_litres,
            'diesel_litres', diesel_litres, 'total_litres', total_litres,
            'confirmed_allocations', confirmed_allocations,
            'customer_keys', customer_keys
        ) ORDER BY total_litres DESC), '[]'::jsonb) FROM station_totals),
        'omcs', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'omc', omc_name, 'petrol_litres', petrol_litres,
            'diesel_litres', diesel_litres, 'total_litres', total_litres,
            'stations_used', stations_used,
            'confirmed_allocations', confirmed_allocations
        ) ORDER BY total_litres DESC), '[]'::jsonb) FROM omc_totals),
        'districts', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'district', district_name, 'petrol_litres', petrol_litres,
            'diesel_litres', diesel_litres, 'total_litres', total_litres,
            'stations_used', stations_used,
            'confirmed_allocations', confirmed_allocations
        ) ORDER BY total_litres DESC), '[]'::jsonb) FROM district_totals),
        'customers', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'customer_key', customer_key, 'customer', customer,
            'company', company, 'applicant_id', applicant_id,
            'petrol_litres', petrol_litres, 'diesel_litres', diesel_litres,
            'total_litres', total_litres,
            'confirmed_allocations', confirmed_allocations,
            'stations_visited', stations_visited,
            'first_confirmed_date', first_confirmed_date,
            'last_confirmed_date', last_confirmed_date
        ) ORDER BY total_litres DESC), '[]'::jsonb) FROM customer_totals),
        'repeats', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'customer_key', customer_key, 'customer', customer,
            'confirmed_allocations', confirmed_allocations,
            'sessions', confirmed_allocations,
            'total_litres', total_litres,
            'stations_visited', stations_visited
        ) ORDER BY confirmed_allocations DESC, total_litres DESC), '[]'::jsonb)
        FROM customer_totals WHERE confirmed_allocations > 1),
        'request_statuses', (SELECT COALESCE(jsonb_object_agg(status, total), '{}'::jsonb)
            FROM (SELECT COALESCE(status, 'UNKNOWN') AS status, COUNT(*) AS total
                  FROM filtered_requests GROUP BY 1) x),
        'request_metrics', (SELECT jsonb_build_object(
            'requests_received', COUNT(*),
            'requests_approved', COUNT(*) FILTER (WHERE status = 'APPROVED'),
            'requests_rejected', COUNT(*) FILTER (WHERE status = 'REJECTED'),
            'requests_other', COUNT(*) FILTER (WHERE status IS DISTINCT FROM 'APPROVED'
                                                  AND status IS DISTINCT FROM 'REJECTED')
        ) FROM filtered_requests),
        'requested_approved_litres', (SELECT jsonb_build_object(
            'petrol_requested_litres', COALESCE(SUM(requested_litres) FILTER (WHERE UPPER(product) = 'PETROL'), 0),
            'diesel_requested_litres', COALESCE(SUM(requested_litres) FILTER (WHERE UPPER(product) = 'DIESEL'), 0),
            'total_requested_litres', COALESCE(SUM(requested_litres), 0),
            'petrol_approved_litres', COALESCE(SUM(approved_litres) FILTER (WHERE UPPER(product) = 'PETROL'), 0),
            'diesel_approved_litres', COALESCE(SUM(approved_litres) FILTER (WHERE UPPER(product) = 'DIESEL'), 0),
            'total_approved_litres', COALESCE(SUM(approved_litres), 0)
        ) FROM filtered_items),
        'allocation_metrics', (SELECT jsonb_build_object(
            'total_allocations', COUNT(*),
            'active_allocations', COUNT(*) FILTER (WHERE allocation_status = 'ACTIVE'),
            'completed_allocations', COUNT(*) FILTER (WHERE allocation_status = 'COMPLETED'),
            'cancelled_allocations', COUNT(*) FILTER (WHERE allocation_status = 'CANCELLED'),
            'petrol_allocated_litres', COALESCE(SUM(allocated_litres) FILTER (WHERE product = 'PETROL'), 0),
            'diesel_allocated_litres', COALESCE(SUM(allocated_litres) FILTER (WHERE product = 'DIESEL'), 0),
            'total_allocated_litres', COALESCE(SUM(allocated_litres), 0),
            'total_recorded_dispensed_litres', COALESCE(SUM(dispensed_litres), 0)
        ) FROM filtered_allocations),
        'confirmation_metrics', (SELECT jsonb_build_object(
            'confirmed', COUNT(*) FILTER (WHERE confirmation_status = 'CONFIRMED'),
            'pending', COUNT(*) FILTER (WHERE confirmation_status = 'PENDING'),
            'not_fueled', COUNT(*) FILTER (WHERE confirmation_status = 'NOT_FUELED'),
            'other', COUNT(*) FILTER (WHERE confirmation_status NOT IN ('CONFIRMED','PENDING','NOT_FUELED')),
            'confirmed_reported_litres', COALESCE(SUM(confirmed_litres) FILTER (WHERE confirmation_status = 'CONFIRMED'), 0)
        ) FROM filtered_confirmations),
        'monthly_allowances', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'applicant_id', applicant_id, 'customer', applicant_name,
            'product', product, 'allowance_type', 'MONTHLY',
            'limit_litres', allowance_litres,
            'current_month_confirmed_litres', current_month_confirmed_litres,
            'remaining_litres', GREATEST(allowance_litres - current_month_confirmed_litres, 0),
            'utilization_percent', CASE WHEN allowance_litres > 0
                THEN ROUND(100 * current_month_confirmed_litres / allowance_litres, 2)
                ELSE NULL END,
            'potential_exceedance', current_month_confirmed_litres > allowance_litres
        ) ORDER BY applicant_name, product), '[]'::jsonb) FROM monthly_allowances)
    ) INTO v_result;

    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_container_fuel_report_v2(date, date)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_container_fuel_report_v2(date, date)
TO authenticated;
