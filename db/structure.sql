SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    name character varying NOT NULL,
    subdomain character varying NOT NULL,
    time_zone character varying DEFAULT 'Nairobi'::character varying NOT NULL,
    currency character varying DEFAULT 'KES'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    require_two_factor_for_managers boolean DEFAULT false NOT NULL,
    max_cashier_discount_percent numeric(5,2) DEFAULT 5.0 NOT NULL,
    receipt_footer text,
    sms_enabled boolean DEFAULT false NOT NULL
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: admin_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: admin_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_sessions_id_seq OWNED BY public.admin_sessions.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: barcodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.barcodes (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    product_id bigint NOT NULL,
    product_unit_id bigint,
    code character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.barcodes FORCE ROW LEVEL SECURITY;


--
-- Name: barcodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.barcodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: barcodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.barcodes_id_seq OWNED BY public.barcodes.id;


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    name character varying NOT NULL,
    address character varying,
    phone character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    code character varying
);

ALTER TABLE ONLY public.branches FORCE ROW LEVEL SECURITY;


--
-- Name: branches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.branches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: branches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.branches_id_seq OWNED BY public.branches.id;


--
-- Name: brands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.brands (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.brands FORCE ROW LEVEL SECURITY;


--
-- Name: brands_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.brands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: brands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.brands_id_seq OWNED BY public.brands.id;


--
-- Name: cash_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_movements (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    shift_id bigint NOT NULL,
    creator_id bigint,
    kind character varying NOT NULL,
    amount_cents bigint NOT NULL,
    reason character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.cash_movements FORCE ROW LEVEL SECURITY;


--
-- Name: cash_movements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cash_movements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cash_movements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cash_movements_id_seq OWNED BY public.cash_movements.id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    parent_id bigint,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    etims_class_code character varying
);

ALTER TABLE ONLY public.categories FORCE ROW LEVEL SECURITY;


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: customer_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_order_lines (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    customer_order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    product_unit_id bigint,
    quantity numeric(14,3) NOT NULL,
    unit_price_cents bigint DEFAULT 0 NOT NULL,
    tax_rate numeric(5,2) DEFAULT 0.0 NOT NULL,
    total_cents bigint DEFAULT 0 NOT NULL,
    tax_cents bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.customer_order_lines FORCE ROW LEVEL SECURITY;


--
-- Name: customer_order_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customer_order_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_order_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customer_order_lines_id_seq OWNED BY public.customer_order_lines.id;


--
-- Name: customer_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_orders (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    creator_id bigint,
    number integer NOT NULL,
    status character varying DEFAULT 'quote'::character varying NOT NULL,
    valid_until date,
    needed_by date,
    note character varying,
    total_cents bigint DEFAULT 0 NOT NULL,
    tax_cents bigint DEFAULT 0 NOT NULL,
    ordered_at timestamp(6) without time zone,
    collected_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.customer_orders FORCE ROW LEVEL SECURITY;


--
-- Name: customer_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customer_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customer_orders_id_seq OWNED BY public.customer_orders.id;


--
-- Name: customer_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_payments (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    shift_id bigint,
    creator_id bigint,
    paid_on date NOT NULL,
    amount_cents bigint NOT NULL,
    payment_method character varying NOT NULL,
    reference character varying,
    note character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.customer_payments FORCE ROW LEVEL SECURITY;


--
-- Name: customer_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customer_payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customer_payments_id_seq OWNED BY public.customer_payments.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    price_list_id bigint,
    name character varying NOT NULL,
    phone character varying,
    email character varying,
    tax_pin character varying,
    credit_limit_cents bigint DEFAULT 0 NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payment_terms_days integer DEFAULT 30 NOT NULL,
    address character varying
);

ALTER TABLE ONLY public.customers FORCE ROW LEVEL SECURITY;


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: delivery_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_notes (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    sale_id bigint NOT NULL,
    creator_id bigint,
    number integer NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    address character varying NOT NULL,
    contact_phone character varying,
    driver_name character varying,
    vehicle character varying,
    received_by character varying,
    note character varying,
    dispatched_at timestamp(6) without time zone,
    delivered_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.delivery_notes FORCE ROW LEVEL SECURITY;


--
-- Name: delivery_notes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.delivery_notes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: delivery_notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.delivery_notes_id_seq OWNED BY public.delivery_notes.id;


--
-- Name: deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    customer_order_id bigint NOT NULL,
    shift_id bigint,
    creator_id bigint,
    amount_cents bigint NOT NULL,
    tender character varying NOT NULL,
    reference character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.deposits FORCE ROW LEVEL SECURITY;


--
-- Name: deposits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposits_id_seq OWNED BY public.deposits.id;


--
-- Name: document_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_sequences (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    kind character varying NOT NULL,
    last_number integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.document_sequences FORCE ROW LEVEL SECURITY;


--
-- Name: document_sequences_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_sequences_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_sequences_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_sequences_id_seq OWNED BY public.document_sequences.id;


--
-- Name: etims_devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.etims_devices (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    environment character varying DEFAULT 'sandbox'::character varying NOT NULL,
    tin character varying NOT NULL,
    bhf_id character varying DEFAULT '00'::character varying NOT NULL,
    serial_number character varying NOT NULL,
    cmc_key text,
    sdc_id character varying,
    mrc_no character varying,
    default_item_class_code character varying DEFAULT '5020230500'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    initialized_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.etims_devices FORCE ROW LEVEL SECURITY;


--
-- Name: etims_devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.etims_devices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: etims_devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.etims_devices_id_seq OWNED BY public.etims_devices.id;


--
-- Name: etims_item_registrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.etims_item_registrations (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    device_id bigint NOT NULL,
    product_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.etims_item_registrations FORCE ROW LEVEL SECURITY;


--
-- Name: etims_item_registrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.etims_item_registrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: etims_item_registrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.etims_item_registrations_id_seq OWNED BY public.etims_item_registrations.id;


--
-- Name: etims_submissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.etims_submissions (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    device_id bigint NOT NULL,
    document_type character varying NOT NULL,
    document_id bigint NOT NULL,
    kind character varying NOT NULL,
    invoice_number integer NOT NULL,
    original_invoice_number integer,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error character varying,
    last_attempted_at timestamp(6) without time zone,
    receipt_number integer,
    total_receipt_number integer,
    internal_data character varying,
    receipt_signature character varying,
    sdc_date_time character varying,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.etims_submissions FORCE ROW LEVEL SECURITY;


--
-- Name: etims_submissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.etims_submissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: etims_submissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.etims_submissions_id_seq OWNED BY public.etims_submissions.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    creator_id bigint,
    eventable_type character varying NOT NULL,
    eventable_id bigint NOT NULL,
    action character varying NOT NULL,
    particulars jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.events FORCE ROW LEVEL SECURITY;


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: goods_receipt_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goods_receipt_lines (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    goods_receipt_id bigint NOT NULL,
    purchase_order_line_id bigint,
    product_id bigint NOT NULL,
    quantity numeric(14,3) NOT NULL,
    unit_cost_cents bigint NOT NULL,
    landed_unit_cost_cents bigint DEFAULT 0 NOT NULL
);

ALTER TABLE ONLY public.goods_receipt_lines FORCE ROW LEVEL SECURITY;


--
-- Name: goods_receipt_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.goods_receipt_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: goods_receipt_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.goods_receipt_lines_id_seq OWNED BY public.goods_receipt_lines.id;


--
-- Name: goods_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goods_receipts (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    supplier_id bigint NOT NULL,
    purchase_order_id bigint,
    branch_id bigint NOT NULL,
    receiver_id bigint,
    number integer NOT NULL,
    supplier_reference character varying,
    extra_costs_cents bigint DEFAULT 0 NOT NULL,
    total_cents bigint DEFAULT 0 NOT NULL,
    note character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.goods_receipts FORCE ROW LEVEL SECURITY;


--
-- Name: goods_receipts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.goods_receipts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: goods_receipts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.goods_receipts_id_seq OWNED BY public.goods_receipts.id;


--
-- Name: kit_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kit_components (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    kit_id bigint NOT NULL,
    component_id bigint NOT NULL,
    quantity numeric(14,3) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.kit_components FORCE ROW LEVEL SECURITY;


--
-- Name: kit_components_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kit_components_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kit_components_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kit_components_id_seq OWNED BY public.kit_components.id;


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role character varying DEFAULT 'cashier'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    pin_digest character varying,
    failed_pin_attempts integer DEFAULT 0 NOT NULL,
    approval_pin_digest character varying,
    daily_summary boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY public.memberships FORCE ROW LEVEL SECURITY;


--
-- Name: memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.memberships_id_seq OWNED BY public.memberships.id;


--
-- Name: mpesa_shortcodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mpesa_shortcodes (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint,
    name character varying NOT NULL,
    environment character varying DEFAULT 'sandbox'::character varying NOT NULL,
    transaction_type character varying DEFAULT 'paybill'::character varying NOT NULL,
    shortcode character varying NOT NULL,
    till_number character varying,
    consumer_key text,
    consumer_secret text,
    passkey text,
    callback_token character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    c2b_registered_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.mpesa_shortcodes FORCE ROW LEVEL SECURITY;


--
-- Name: mpesa_shortcodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mpesa_shortcodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mpesa_shortcodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mpesa_shortcodes_id_seq OWNED BY public.mpesa_shortcodes.id;


--
-- Name: mpesa_stk_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mpesa_stk_requests (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    shortcode_id bigint NOT NULL,
    sale_id bigint NOT NULL,
    payment_id bigint,
    requested_by_id bigint,
    phone character varying NOT NULL,
    amount_cents bigint NOT NULL,
    merchant_request_id character varying,
    checkout_request_id character varying,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    result_code character varying,
    result_description character varying,
    receipt_number character varying,
    resolved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.mpesa_stk_requests FORCE ROW LEVEL SECURITY;


--
-- Name: mpesa_stk_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mpesa_stk_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mpesa_stk_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mpesa_stk_requests_id_seq OWNED BY public.mpesa_stk_requests.id;


--
-- Name: mpesa_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mpesa_transactions (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    shortcode_id bigint NOT NULL,
    source character varying NOT NULL,
    trans_id character varying NOT NULL,
    amount_cents bigint NOT NULL,
    phone character varying,
    payer_name character varying,
    bill_reference character varying,
    transacted_at timestamp(6) without time zone NOT NULL,
    matched_type character varying,
    matched_id bigint,
    matched_at timestamp(6) without time zone,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.mpesa_transactions FORCE ROW LEVEL SECURITY;


--
-- Name: mpesa_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mpesa_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mpesa_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mpesa_transactions_id_seq OWNED BY public.mpesa_transactions.id;


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    sale_id bigint NOT NULL,
    tender character varying NOT NULL,
    amount_cents bigint NOT NULL,
    tendered_cents bigint,
    reference character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.payments FORCE ROW LEVEL SECURITY;


--
-- Name: payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payments_id_seq OWNED BY public.payments.id;


--
-- Name: price_list_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_list_items (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    price_list_id bigint,
    product_id bigint NOT NULL,
    min_quantity numeric(14,3) DEFAULT 1.0 NOT NULL,
    price_cents bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.price_list_items FORCE ROW LEVEL SECURITY;


--
-- Name: price_list_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.price_list_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: price_list_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.price_list_items_id_seq OWNED BY public.price_list_items.id;


--
-- Name: price_lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_lists (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.price_lists FORCE ROW LEVEL SECURITY;


--
-- Name: price_lists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.price_lists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: price_lists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.price_lists_id_seq OWNED BY public.price_lists.id;


--
-- Name: product_imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_imports (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    creator_id bigint,
    branch_id bigint,
    status character varying DEFAULT 'checking'::character varying NOT NULL,
    filename character varying,
    csv text NOT NULL,
    rows_count integer DEFAULT 0 NOT NULL,
    created_count integer DEFAULT 0 NOT NULL,
    updated_count integer DEFAULT 0 NOT NULL,
    problems jsonb DEFAULT '[]'::jsonb NOT NULL,
    preview jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.product_imports FORCE ROW LEVEL SECURITY;


--
-- Name: product_imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_imports_id_seq OWNED BY public.product_imports.id;


--
-- Name: product_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_units (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    product_id bigint NOT NULL,
    unit_id bigint NOT NULL,
    quantity numeric(14,3) NOT NULL,
    price_cents bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.product_units FORCE ROW LEVEL SECURITY;


--
-- Name: product_units_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_units_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_units_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_units_id_seq OWNED BY public.product_units.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    category_id bigint,
    brand_id bigint,
    unit_id bigint NOT NULL,
    tax_rate_id bigint,
    name character varying NOT NULL,
    sku character varying NOT NULL,
    description text,
    cost_cents bigint DEFAULT 0 NOT NULL,
    price_cents bigint NOT NULL,
    reorder_level numeric(14,3) DEFAULT 0.0 NOT NULL,
    track_stock boolean DEFAULT true NOT NULL,
    serialized boolean DEFAULT false NOT NULL,
    kit boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    quick_pick boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.products FORCE ROW LEVEL SECURITY;


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: purchase_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_order_lines (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    purchase_order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity numeric(14,3) NOT NULL,
    received_quantity numeric(14,3) DEFAULT 0.0 NOT NULL,
    unit_cost_cents bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.purchase_order_lines FORCE ROW LEVEL SECURITY;


--
-- Name: purchase_order_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchase_order_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchase_order_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchase_order_lines_id_seq OWNED BY public.purchase_order_lines.id;


--
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_orders (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    supplier_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    creator_id bigint,
    number integer NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    expected_on date,
    note character varying,
    total_cents bigint DEFAULT 0 NOT NULL,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.purchase_orders FORCE ROW LEVEL SECURITY;


--
-- Name: purchase_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchase_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchase_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchase_orders_id_seq OWNED BY public.purchase_orders.id;


--
-- Name: registers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.registers (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.registers FORCE ROW LEVEL SECURITY;


--
-- Name: registers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.registers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: registers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.registers_id_seq OWNED BY public.registers.id;


--
-- Name: sale_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_lines (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    sale_id bigint NOT NULL,
    product_id bigint NOT NULL,
    product_unit_id bigint,
    quantity numeric(14,3) NOT NULL,
    unit_price_cents bigint NOT NULL,
    discount_cents bigint DEFAULT 0 NOT NULL,
    tax_rate numeric(5,2) DEFAULT 0.0 NOT NULL,
    total_cents bigint DEFAULT 0 NOT NULL,
    tax_cents bigint DEFAULT 0 NOT NULL,
    serial_number character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    customer_order_line_id bigint,
    cost_cents bigint DEFAULT 0 NOT NULL
);

ALTER TABLE ONLY public.sale_lines FORCE ROW LEVEL SECURITY;


--
-- Name: sale_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sale_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sale_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sale_lines_id_seq OWNED BY public.sale_lines.id;


--
-- Name: sale_return_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_return_lines (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    sale_return_id bigint NOT NULL,
    sale_line_id bigint NOT NULL,
    quantity numeric(14,3) NOT NULL,
    restock boolean DEFAULT true NOT NULL,
    total_cents bigint DEFAULT 0 NOT NULL,
    tax_cents bigint DEFAULT 0 NOT NULL
);

ALTER TABLE ONLY public.sale_return_lines FORCE ROW LEVEL SECURITY;


--
-- Name: sale_return_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sale_return_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sale_return_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sale_return_lines_id_seq OWNED BY public.sale_return_lines.id;


--
-- Name: sale_returns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_returns (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    sale_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    shift_id bigint NOT NULL,
    creator_id bigint NOT NULL,
    approver_id bigint,
    number integer NOT NULL,
    refund_method character varying NOT NULL,
    total_cents bigint DEFAULT 0 NOT NULL,
    tax_cents bigint DEFAULT 0 NOT NULL,
    reason character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.sale_returns FORCE ROW LEVEL SECURITY;


--
-- Name: sale_returns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sale_returns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sale_returns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sale_returns_id_seq OWNED BY public.sale_returns.id;


--
-- Name: sales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    register_id bigint NOT NULL,
    shift_id bigint NOT NULL,
    customer_id bigint,
    cashier_id bigint NOT NULL,
    discount_approver_id bigint,
    approved_discount_percent numeric(5,2),
    voided_by_id bigint,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    number integer,
    discount_cents bigint DEFAULT 0 NOT NULL,
    subtotal_cents bigint DEFAULT 0 NOT NULL,
    tax_cents bigint DEFAULT 0 NOT NULL,
    total_cents bigint DEFAULT 0 NOT NULL,
    note character varying,
    void_reason character varying,
    completed_at timestamp(6) without time zone,
    voided_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    customer_order_id bigint,
    credit_approver_id bigint
);

ALTER TABLE ONLY public.sales FORCE ROW LEVEL SECURITY;


--
-- Name: sales_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sales_id_seq OWNED BY public.sales.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    sign_in_method character varying DEFAULT 'password'::character varying NOT NULL,
    impersonator_id bigint,
    expires_at timestamp(6) without time zone
);

ALTER TABLE ONLY public.sessions FORCE ROW LEVEL SECURITY;


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shifts (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    register_id bigint NOT NULL,
    opened_by_id bigint NOT NULL,
    closed_by_id bigint,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    opening_float_cents bigint DEFAULT 0 NOT NULL,
    expected_cash_cents bigint,
    counted_cash_cents bigint,
    note character varying,
    opened_at timestamp(6) without time zone NOT NULL,
    closed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.shifts FORCE ROW LEVEL SECURITY;


--
-- Name: shifts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.shifts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: shifts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.shifts_id_seq OWNED BY public.shifts.id;


--
-- Name: sms_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sms_messages (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    source_type character varying,
    source_id bigint,
    sender_id bigint,
    recipient character varying NOT NULL,
    body text NOT NULL,
    purpose character varying NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    provider_message_id character varying,
    cost character varying,
    error character varying,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.sms_messages FORCE ROW LEVEL SECURITY;


--
-- Name: sms_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sms_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sms_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sms_messages_id_seq OWNED BY public.sms_messages.id;


--
-- Name: stock_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_adjustments (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    product_id bigint NOT NULL,
    creator_id bigint,
    quantity numeric(14,3) NOT NULL,
    reason character varying NOT NULL,
    note character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.stock_adjustments FORCE ROW LEVEL SECURITY;


--
-- Name: stock_adjustments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stock_adjustments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stock_adjustments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stock_adjustments_id_seq OWNED BY public.stock_adjustments.id;


--
-- Name: stock_count_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_count_lines (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    stock_count_id bigint NOT NULL,
    product_id bigint NOT NULL,
    expected_quantity numeric(14,3) NOT NULL,
    counted_quantity numeric(14,3),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.stock_count_lines FORCE ROW LEVEL SECURITY;


--
-- Name: stock_count_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stock_count_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stock_count_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stock_count_lines_id_seq OWNED BY public.stock_count_lines.id;


--
-- Name: stock_counts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_counts (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    category_id bigint,
    creator_id bigint,
    approver_id bigint,
    status character varying DEFAULT 'counting'::character varying NOT NULL,
    note character varying,
    submitted_at timestamp(6) without time zone,
    approved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.stock_counts FORCE ROW LEVEL SECURITY;


--
-- Name: stock_counts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stock_counts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stock_counts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stock_counts_id_seq OWNED BY public.stock_counts.id;


--
-- Name: stock_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_levels (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity numeric(14,3) DEFAULT 0.0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.stock_levels FORCE ROW LEVEL SECURITY;


--
-- Name: stock_levels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stock_levels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stock_levels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stock_levels_id_seq OWNED BY public.stock_levels.id;


--
-- Name: stock_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_movements (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    branch_id bigint NOT NULL,
    product_id bigint NOT NULL,
    source_type character varying,
    source_id bigint,
    creator_id bigint,
    quantity numeric(14,3) NOT NULL,
    balance numeric(14,3) NOT NULL,
    reason character varying NOT NULL,
    unit_cost_cents bigint,
    note character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.stock_movements FORCE ROW LEVEL SECURITY;


--
-- Name: stock_movements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stock_movements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stock_movements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stock_movements_id_seq OWNED BY public.stock_movements.id;


--
-- Name: stock_transfer_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_transfer_lines (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    stock_transfer_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity numeric(14,3) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.stock_transfer_lines FORCE ROW LEVEL SECURITY;


--
-- Name: stock_transfer_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stock_transfer_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stock_transfer_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stock_transfer_lines_id_seq OWNED BY public.stock_transfer_lines.id;


--
-- Name: stock_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_transfers (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    from_branch_id bigint NOT NULL,
    to_branch_id bigint NOT NULL,
    sender_id bigint,
    receiver_id bigint,
    status character varying DEFAULT 'in_transit'::character varying NOT NULL,
    note character varying,
    sent_at timestamp(6) without time zone,
    received_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.stock_transfers FORCE ROW LEVEL SECURITY;


--
-- Name: stock_transfers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stock_transfers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stock_transfers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stock_transfers_id_seq OWNED BY public.stock_transfers.id;


--
-- Name: supplier_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_invoices (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    supplier_id bigint NOT NULL,
    goods_receipt_id bigint,
    creator_id bigint,
    number character varying NOT NULL,
    invoice_date date NOT NULL,
    due_date date NOT NULL,
    total_cents bigint NOT NULL,
    tax_cents bigint DEFAULT 0 NOT NULL,
    note character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.supplier_invoices FORCE ROW LEVEL SECURITY;


--
-- Name: supplier_invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.supplier_invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: supplier_invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.supplier_invoices_id_seq OWNED BY public.supplier_invoices.id;


--
-- Name: supplier_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_payments (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    supplier_id bigint NOT NULL,
    creator_id bigint,
    paid_on date NOT NULL,
    amount_cents bigint NOT NULL,
    payment_method character varying NOT NULL,
    reference character varying,
    note character varying,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.supplier_payments FORCE ROW LEVEL SECURITY;


--
-- Name: supplier_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.supplier_payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: supplier_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.supplier_payments_id_seq OWNED BY public.supplier_payments.id;


--
-- Name: supplier_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_products (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    supplier_id bigint NOT NULL,
    product_id bigint NOT NULL,
    supplier_sku character varying,
    cost_cents bigint DEFAULT 0 NOT NULL,
    lead_time_days integer DEFAULT 7 NOT NULL,
    min_order_quantity numeric(14,3) DEFAULT 1.0 NOT NULL,
    preferred boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.supplier_products FORCE ROW LEVEL SECURITY;


--
-- Name: supplier_products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.supplier_products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: supplier_products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.supplier_products_id_seq OWNED BY public.supplier_products.id;


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suppliers (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    name character varying NOT NULL,
    contact_name character varying,
    phone character varying,
    email character varying,
    tax_pin character varying,
    address character varying,
    payment_terms_days integer DEFAULT 30 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.suppliers FORCE ROW LEVEL SECURITY;


--
-- Name: suppliers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suppliers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suppliers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.suppliers_id_seq OWNED BY public.suppliers.id;


--
-- Name: tax_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_rates (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    name character varying NOT NULL,
    rate numeric(5,2) NOT NULL,
    "default" boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    etims_code character varying
);

ALTER TABLE ONLY public.tax_rates FORCE ROW LEVEL SECURITY;


--
-- Name: tax_rates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tax_rates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tax_rates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tax_rates_id_seq OWNED BY public.tax_rates.id;


--
-- Name: units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.units (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    name character varying NOT NULL,
    abbreviation character varying NOT NULL,
    fractional boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    etims_code character varying
);

ALTER TABLE ONLY public.units FORCE ROW LEVEL SECURITY;


--
-- Name: units_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.units_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: units_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.units_id_seq OWNED BY public.units.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    name character varying NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    two_factor_secret character varying,
    two_factor_recovery_codes text,
    two_factor_enabled_at timestamp(6) without time zone,
    two_factor_last_used_at bigint,
    admin boolean DEFAULT false NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: admin_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_sessions ALTER COLUMN id SET DEFAULT nextval('public.admin_sessions_id_seq'::regclass);


--
-- Name: barcodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barcodes ALTER COLUMN id SET DEFAULT nextval('public.barcodes_id_seq'::regclass);


--
-- Name: branches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches ALTER COLUMN id SET DEFAULT nextval('public.branches_id_seq'::regclass);


--
-- Name: brands id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands ALTER COLUMN id SET DEFAULT nextval('public.brands_id_seq'::regclass);


--
-- Name: cash_movements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements ALTER COLUMN id SET DEFAULT nextval('public.cash_movements_id_seq'::regclass);


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: customer_order_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_lines ALTER COLUMN id SET DEFAULT nextval('public.customer_order_lines_id_seq'::regclass);


--
-- Name: customer_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_orders ALTER COLUMN id SET DEFAULT nextval('public.customer_orders_id_seq'::regclass);


--
-- Name: customer_payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payments ALTER COLUMN id SET DEFAULT nextval('public.customer_payments_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: delivery_notes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_notes ALTER COLUMN id SET DEFAULT nextval('public.delivery_notes_id_seq'::regclass);


--
-- Name: deposits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits ALTER COLUMN id SET DEFAULT nextval('public.deposits_id_seq'::regclass);


--
-- Name: document_sequences id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_sequences ALTER COLUMN id SET DEFAULT nextval('public.document_sequences_id_seq'::regclass);


--
-- Name: etims_devices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_devices ALTER COLUMN id SET DEFAULT nextval('public.etims_devices_id_seq'::regclass);


--
-- Name: etims_item_registrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_item_registrations ALTER COLUMN id SET DEFAULT nextval('public.etims_item_registrations_id_seq'::regclass);


--
-- Name: etims_submissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_submissions ALTER COLUMN id SET DEFAULT nextval('public.etims_submissions_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: goods_receipt_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines ALTER COLUMN id SET DEFAULT nextval('public.goods_receipt_lines_id_seq'::regclass);


--
-- Name: goods_receipts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts ALTER COLUMN id SET DEFAULT nextval('public.goods_receipts_id_seq'::regclass);


--
-- Name: kit_components id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kit_components ALTER COLUMN id SET DEFAULT nextval('public.kit_components_id_seq'::regclass);


--
-- Name: memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships ALTER COLUMN id SET DEFAULT nextval('public.memberships_id_seq'::regclass);


--
-- Name: mpesa_shortcodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_shortcodes ALTER COLUMN id SET DEFAULT nextval('public.mpesa_shortcodes_id_seq'::regclass);


--
-- Name: mpesa_stk_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_stk_requests ALTER COLUMN id SET DEFAULT nextval('public.mpesa_stk_requests_id_seq'::regclass);


--
-- Name: mpesa_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_transactions ALTER COLUMN id SET DEFAULT nextval('public.mpesa_transactions_id_seq'::regclass);


--
-- Name: payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments ALTER COLUMN id SET DEFAULT nextval('public.payments_id_seq'::regclass);


--
-- Name: price_list_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items ALTER COLUMN id SET DEFAULT nextval('public.price_list_items_id_seq'::regclass);


--
-- Name: price_lists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_lists ALTER COLUMN id SET DEFAULT nextval('public.price_lists_id_seq'::regclass);


--
-- Name: product_imports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_imports ALTER COLUMN id SET DEFAULT nextval('public.product_imports_id_seq'::regclass);


--
-- Name: product_units id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units ALTER COLUMN id SET DEFAULT nextval('public.product_units_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: purchase_order_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines ALTER COLUMN id SET DEFAULT nextval('public.purchase_order_lines_id_seq'::regclass);


--
-- Name: purchase_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders ALTER COLUMN id SET DEFAULT nextval('public.purchase_orders_id_seq'::regclass);


--
-- Name: registers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registers ALTER COLUMN id SET DEFAULT nextval('public.registers_id_seq'::regclass);


--
-- Name: sale_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_lines ALTER COLUMN id SET DEFAULT nextval('public.sale_lines_id_seq'::regclass);


--
-- Name: sale_return_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_lines ALTER COLUMN id SET DEFAULT nextval('public.sale_return_lines_id_seq'::regclass);


--
-- Name: sale_returns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns ALTER COLUMN id SET DEFAULT nextval('public.sale_returns_id_seq'::regclass);


--
-- Name: sales id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ALTER COLUMN id SET DEFAULT nextval('public.sales_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: shifts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts ALTER COLUMN id SET DEFAULT nextval('public.shifts_id_seq'::regclass);


--
-- Name: sms_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_messages ALTER COLUMN id SET DEFAULT nextval('public.sms_messages_id_seq'::regclass);


--
-- Name: stock_adjustments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_adjustments ALTER COLUMN id SET DEFAULT nextval('public.stock_adjustments_id_seq'::regclass);


--
-- Name: stock_count_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_count_lines ALTER COLUMN id SET DEFAULT nextval('public.stock_count_lines_id_seq'::regclass);


--
-- Name: stock_counts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_counts ALTER COLUMN id SET DEFAULT nextval('public.stock_counts_id_seq'::regclass);


--
-- Name: stock_levels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels ALTER COLUMN id SET DEFAULT nextval('public.stock_levels_id_seq'::regclass);


--
-- Name: stock_movements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements ALTER COLUMN id SET DEFAULT nextval('public.stock_movements_id_seq'::regclass);


--
-- Name: stock_transfer_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_lines ALTER COLUMN id SET DEFAULT nextval('public.stock_transfer_lines_id_seq'::regclass);


--
-- Name: stock_transfers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers ALTER COLUMN id SET DEFAULT nextval('public.stock_transfers_id_seq'::regclass);


--
-- Name: supplier_invoices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_invoices ALTER COLUMN id SET DEFAULT nextval('public.supplier_invoices_id_seq'::regclass);


--
-- Name: supplier_payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_payments ALTER COLUMN id SET DEFAULT nextval('public.supplier_payments_id_seq'::regclass);


--
-- Name: supplier_products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_products ALTER COLUMN id SET DEFAULT nextval('public.supplier_products_id_seq'::regclass);


--
-- Name: suppliers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers ALTER COLUMN id SET DEFAULT nextval('public.suppliers_id_seq'::regclass);


--
-- Name: tax_rates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_rates ALTER COLUMN id SET DEFAULT nextval('public.tax_rates_id_seq'::regclass);


--
-- Name: units id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units ALTER COLUMN id SET DEFAULT nextval('public.units_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: admin_sessions admin_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_sessions
    ADD CONSTRAINT admin_sessions_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: barcodes barcodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barcodes
    ADD CONSTRAINT barcodes_pkey PRIMARY KEY (id);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: brands brands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT brands_pkey PRIMARY KEY (id);


--
-- Name: cash_movements cash_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: customer_order_lines customer_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_lines
    ADD CONSTRAINT customer_order_lines_pkey PRIMARY KEY (id);


--
-- Name: customer_orders customer_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_orders
    ADD CONSTRAINT customer_orders_pkey PRIMARY KEY (id);


--
-- Name: customer_payments customer_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payments
    ADD CONSTRAINT customer_payments_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: delivery_notes delivery_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_notes
    ADD CONSTRAINT delivery_notes_pkey PRIMARY KEY (id);


--
-- Name: deposits deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_pkey PRIMARY KEY (id);


--
-- Name: document_sequences document_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_sequences
    ADD CONSTRAINT document_sequences_pkey PRIMARY KEY (id);


--
-- Name: etims_devices etims_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_devices
    ADD CONSTRAINT etims_devices_pkey PRIMARY KEY (id);


--
-- Name: etims_item_registrations etims_item_registrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_item_registrations
    ADD CONSTRAINT etims_item_registrations_pkey PRIMARY KEY (id);


--
-- Name: etims_submissions etims_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_submissions
    ADD CONSTRAINT etims_submissions_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: goods_receipt_lines goods_receipt_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT goods_receipt_lines_pkey PRIMARY KEY (id);


--
-- Name: goods_receipts goods_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT goods_receipts_pkey PRIMARY KEY (id);


--
-- Name: kit_components kit_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kit_components
    ADD CONSTRAINT kit_components_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: mpesa_shortcodes mpesa_shortcodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_shortcodes
    ADD CONSTRAINT mpesa_shortcodes_pkey PRIMARY KEY (id);


--
-- Name: mpesa_stk_requests mpesa_stk_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_stk_requests
    ADD CONSTRAINT mpesa_stk_requests_pkey PRIMARY KEY (id);


--
-- Name: mpesa_transactions mpesa_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_transactions
    ADD CONSTRAINT mpesa_transactions_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: price_list_items price_list_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT price_list_items_pkey PRIMARY KEY (id);


--
-- Name: price_lists price_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_lists
    ADD CONSTRAINT price_lists_pkey PRIMARY KEY (id);


--
-- Name: product_imports product_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_imports
    ADD CONSTRAINT product_imports_pkey PRIMARY KEY (id);


--
-- Name: product_units product_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT product_units_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: purchase_order_lines purchase_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT purchase_order_lines_pkey PRIMARY KEY (id);


--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- Name: registers registers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registers
    ADD CONSTRAINT registers_pkey PRIMARY KEY (id);


--
-- Name: sale_lines sale_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_lines
    ADD CONSTRAINT sale_lines_pkey PRIMARY KEY (id);


--
-- Name: sale_return_lines sale_return_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_lines
    ADD CONSTRAINT sale_return_lines_pkey PRIMARY KEY (id);


--
-- Name: sale_returns sale_returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT sale_returns_pkey PRIMARY KEY (id);


--
-- Name: sales sales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: shifts shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_pkey PRIMARY KEY (id);


--
-- Name: sms_messages sms_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_messages
    ADD CONSTRAINT sms_messages_pkey PRIMARY KEY (id);


--
-- Name: stock_adjustments stock_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_adjustments
    ADD CONSTRAINT stock_adjustments_pkey PRIMARY KEY (id);


--
-- Name: stock_count_lines stock_count_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_count_lines
    ADD CONSTRAINT stock_count_lines_pkey PRIMARY KEY (id);


--
-- Name: stock_counts stock_counts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_counts
    ADD CONSTRAINT stock_counts_pkey PRIMARY KEY (id);


--
-- Name: stock_levels stock_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_pkey PRIMARY KEY (id);


--
-- Name: stock_movements stock_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_pkey PRIMARY KEY (id);


--
-- Name: stock_transfer_lines stock_transfer_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_lines
    ADD CONSTRAINT stock_transfer_lines_pkey PRIMARY KEY (id);


--
-- Name: stock_transfers stock_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_pkey PRIMARY KEY (id);


--
-- Name: supplier_invoices supplier_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_invoices
    ADD CONSTRAINT supplier_invoices_pkey PRIMARY KEY (id);


--
-- Name: supplier_payments supplier_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_payments
    ADD CONSTRAINT supplier_payments_pkey PRIMARY KEY (id);


--
-- Name: supplier_products supplier_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_products
    ADD CONSTRAINT supplier_products_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: tax_rates tax_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_rates
    ADD CONSTRAINT tax_rates_pkey PRIMARY KEY (id);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_document_type_document_id_kind_94f3085d1e; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_document_type_document_id_kind_94f3085d1e ON public.etims_submissions USING btree (document_type, document_id, kind);


--
-- Name: idx_on_product_id_branch_id_created_at_dd8be66641; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_product_id_branch_id_created_at_dd8be66641 ON public.stock_movements USING btree (product_id, branch_id, created_at);


--
-- Name: idx_on_product_id_price_list_id_min_quantity_f69598ecfa; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_product_id_price_list_id_min_quantity_f69598ecfa ON public.price_list_items USING btree (product_id, price_list_id, min_quantity) NULLS NOT DISTINCT;


--
-- Name: index_accounts_on_subdomain; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_subdomain ON public.accounts USING btree (subdomain);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_admin_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_sessions_on_user_id ON public.admin_sessions USING btree (user_id);


--
-- Name: index_barcodes_on_account_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_barcodes_on_account_id_and_code ON public.barcodes USING btree (account_id, code);


--
-- Name: index_barcodes_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_barcodes_on_product_id ON public.barcodes USING btree (product_id);


--
-- Name: index_barcodes_on_product_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_barcodes_on_product_unit_id ON public.barcodes USING btree (product_unit_id);


--
-- Name: index_branches_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_branches_on_account_id ON public.branches USING btree (account_id);


--
-- Name: index_branches_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_branches_on_account_id_and_name ON public.branches USING btree (account_id, name);


--
-- Name: index_brands_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_brands_on_account_id_and_name ON public.brands USING btree (account_id, name);


--
-- Name: index_cash_movements_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_creator_id ON public.cash_movements USING btree (creator_id);


--
-- Name: index_cash_movements_on_shift_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_shift_id ON public.cash_movements USING btree (shift_id);


--
-- Name: index_categories_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_categories_on_account_id_and_name ON public.categories USING btree (account_id, name);


--
-- Name: index_categories_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_on_parent_id ON public.categories USING btree (parent_id);


--
-- Name: index_customer_order_lines_on_customer_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_order_lines_on_customer_order_id ON public.customer_order_lines USING btree (customer_order_id);


--
-- Name: index_customer_order_lines_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_order_lines_on_product_id ON public.customer_order_lines USING btree (product_id);


--
-- Name: index_customer_order_lines_on_product_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_order_lines_on_product_unit_id ON public.customer_order_lines USING btree (product_unit_id);


--
-- Name: index_customer_orders_on_account_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_orders_on_account_id_and_status ON public.customer_orders USING btree (account_id, status);


--
-- Name: index_customer_orders_on_branch_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customer_orders_on_branch_id_and_number ON public.customer_orders USING btree (branch_id, number);


--
-- Name: index_customer_orders_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_orders_on_creator_id ON public.customer_orders USING btree (creator_id);


--
-- Name: index_customer_orders_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_orders_on_customer_id ON public.customer_orders USING btree (customer_id);


--
-- Name: index_customer_payments_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_payments_on_creator_id ON public.customer_payments USING btree (creator_id);


--
-- Name: index_customer_payments_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_payments_on_customer_id ON public.customer_payments USING btree (customer_id);


--
-- Name: index_customer_payments_on_shift_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_payments_on_shift_id ON public.customer_payments USING btree (shift_id);


--
-- Name: index_customers_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_account_id_and_name ON public.customers USING btree (account_id, name);


--
-- Name: index_customers_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_name ON public.customers USING gin (name public.gin_trgm_ops);


--
-- Name: index_customers_on_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_phone ON public.customers USING btree (phone);


--
-- Name: index_customers_on_price_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_price_list_id ON public.customers USING btree (price_list_id);


--
-- Name: index_delivery_notes_on_account_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_delivery_notes_on_account_id_and_status ON public.delivery_notes USING btree (account_id, status);


--
-- Name: index_delivery_notes_on_branch_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_delivery_notes_on_branch_id_and_number ON public.delivery_notes USING btree (branch_id, number);


--
-- Name: index_delivery_notes_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_delivery_notes_on_creator_id ON public.delivery_notes USING btree (creator_id);


--
-- Name: index_delivery_notes_on_sale_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_delivery_notes_on_sale_id ON public.delivery_notes USING btree (sale_id);


--
-- Name: index_deposits_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposits_on_creator_id ON public.deposits USING btree (creator_id);


--
-- Name: index_deposits_on_customer_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposits_on_customer_order_id ON public.deposits USING btree (customer_order_id);


--
-- Name: index_deposits_on_shift_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposits_on_shift_id ON public.deposits USING btree (shift_id);


--
-- Name: index_document_sequences_on_branch_id_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_document_sequences_on_branch_id_and_kind ON public.document_sequences USING btree (branch_id, kind);


--
-- Name: index_etims_devices_on_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_etims_devices_on_branch_id ON public.etims_devices USING btree (branch_id);


--
-- Name: index_etims_item_registrations_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_etims_item_registrations_on_device_id ON public.etims_item_registrations USING btree (device_id);


--
-- Name: index_etims_item_registrations_on_device_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_etims_item_registrations_on_device_id_and_product_id ON public.etims_item_registrations USING btree (device_id, product_id);


--
-- Name: index_etims_item_registrations_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_etims_item_registrations_on_product_id ON public.etims_item_registrations USING btree (product_id);


--
-- Name: index_etims_submissions_on_account_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_etims_submissions_on_account_id_and_status ON public.etims_submissions USING btree (account_id, status);


--
-- Name: index_etims_submissions_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_etims_submissions_on_device_id ON public.etims_submissions USING btree (device_id);


--
-- Name: index_etims_submissions_on_device_id_and_invoice_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_etims_submissions_on_device_id_and_invoice_number ON public.etims_submissions USING btree (device_id, invoice_number);


--
-- Name: index_events_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_account_id_and_created_at ON public.events USING btree (account_id, created_at);


--
-- Name: index_events_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_creator_id ON public.events USING btree (creator_id);


--
-- Name: index_events_on_eventable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_eventable ON public.events USING btree (eventable_type, eventable_id);


--
-- Name: index_goods_receipt_lines_on_goods_receipt_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_goods_receipt_lines_on_goods_receipt_id ON public.goods_receipt_lines USING btree (goods_receipt_id);


--
-- Name: index_goods_receipt_lines_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_goods_receipt_lines_on_product_id ON public.goods_receipt_lines USING btree (product_id);


--
-- Name: index_goods_receipt_lines_on_purchase_order_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_goods_receipt_lines_on_purchase_order_line_id ON public.goods_receipt_lines USING btree (purchase_order_line_id);


--
-- Name: index_goods_receipts_on_branch_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_goods_receipts_on_branch_id_and_number ON public.goods_receipts USING btree (branch_id, number);


--
-- Name: index_goods_receipts_on_purchase_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_goods_receipts_on_purchase_order_id ON public.goods_receipts USING btree (purchase_order_id);


--
-- Name: index_goods_receipts_on_receiver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_goods_receipts_on_receiver_id ON public.goods_receipts USING btree (receiver_id);


--
-- Name: index_goods_receipts_on_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_goods_receipts_on_supplier_id ON public.goods_receipts USING btree (supplier_id);


--
-- Name: index_kit_components_on_component_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_kit_components_on_component_id ON public.kit_components USING btree (component_id);


--
-- Name: index_kit_components_on_kit_id_and_component_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_kit_components_on_kit_id_and_component_id ON public.kit_components USING btree (kit_id, component_id);


--
-- Name: index_memberships_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_account_id ON public.memberships USING btree (account_id);


--
-- Name: index_memberships_on_account_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_account_id_and_user_id ON public.memberships USING btree (account_id, user_id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_mpesa_shortcodes_on_account_id_and_shortcode; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mpesa_shortcodes_on_account_id_and_shortcode ON public.mpesa_shortcodes USING btree (account_id, shortcode);


--
-- Name: index_mpesa_shortcodes_on_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_shortcodes_on_branch_id ON public.mpesa_shortcodes USING btree (branch_id);


--
-- Name: index_mpesa_shortcodes_on_callback_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mpesa_shortcodes_on_callback_token ON public.mpesa_shortcodes USING btree (callback_token);


--
-- Name: index_mpesa_stk_requests_on_checkout_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mpesa_stk_requests_on_checkout_request_id ON public.mpesa_stk_requests USING btree (checkout_request_id);


--
-- Name: index_mpesa_stk_requests_on_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_stk_requests_on_payment_id ON public.mpesa_stk_requests USING btree (payment_id);


--
-- Name: index_mpesa_stk_requests_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_stk_requests_on_requested_by_id ON public.mpesa_stk_requests USING btree (requested_by_id);


--
-- Name: index_mpesa_stk_requests_on_sale_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_stk_requests_on_sale_id ON public.mpesa_stk_requests USING btree (sale_id);


--
-- Name: index_mpesa_stk_requests_on_shortcode_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_stk_requests_on_shortcode_id ON public.mpesa_stk_requests USING btree (shortcode_id);


--
-- Name: index_mpesa_transactions_on_account_id_and_trans_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mpesa_transactions_on_account_id_and_trans_id ON public.mpesa_transactions USING btree (account_id, trans_id);


--
-- Name: index_mpesa_transactions_on_account_id_and_transacted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_transactions_on_account_id_and_transacted_at ON public.mpesa_transactions USING btree (account_id, transacted_at);


--
-- Name: index_mpesa_transactions_on_matched; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_transactions_on_matched ON public.mpesa_transactions USING btree (matched_type, matched_id);


--
-- Name: index_mpesa_transactions_on_shortcode_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mpesa_transactions_on_shortcode_id ON public.mpesa_transactions USING btree (shortcode_id);


--
-- Name: index_payments_on_sale_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payments_on_sale_id ON public.payments USING btree (sale_id);


--
-- Name: index_price_list_items_on_price_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_price_list_items_on_price_list_id ON public.price_list_items USING btree (price_list_id);


--
-- Name: index_price_lists_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_price_lists_on_account_id_and_name ON public.price_lists USING btree (account_id, name);


--
-- Name: index_product_imports_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_imports_on_account_id_and_created_at ON public.product_imports USING btree (account_id, created_at);


--
-- Name: index_product_imports_on_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_imports_on_branch_id ON public.product_imports USING btree (branch_id);


--
-- Name: index_product_imports_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_imports_on_creator_id ON public.product_imports USING btree (creator_id);


--
-- Name: index_product_units_on_product_id_and_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_product_units_on_product_id_and_unit_id ON public.product_units USING btree (product_id, unit_id);


--
-- Name: index_product_units_on_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_units_on_unit_id ON public.product_units USING btree (unit_id);


--
-- Name: index_products_on_account_id_and_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_products_on_account_id_and_sku ON public.products USING btree (account_id, sku);


--
-- Name: index_products_on_brand_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_brand_id ON public.products USING btree (brand_id);


--
-- Name: index_products_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_category_id ON public.products USING btree (category_id);


--
-- Name: index_products_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_name ON public.products USING gin (name public.gin_trgm_ops);


--
-- Name: index_products_on_sku_trigram; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_sku_trigram ON public.products USING gin (sku public.gin_trgm_ops);


--
-- Name: index_products_on_tax_rate_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_tax_rate_id ON public.products USING btree (tax_rate_id);


--
-- Name: index_products_on_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_unit_id ON public.products USING btree (unit_id);


--
-- Name: index_purchase_order_lines_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchase_order_lines_on_product_id ON public.purchase_order_lines USING btree (product_id);


--
-- Name: index_purchase_order_lines_on_purchase_order_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchase_order_lines_on_purchase_order_id_and_product_id ON public.purchase_order_lines USING btree (purchase_order_id, product_id);


--
-- Name: index_purchase_orders_on_account_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchase_orders_on_account_id_and_status ON public.purchase_orders USING btree (account_id, status);


--
-- Name: index_purchase_orders_on_branch_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchase_orders_on_branch_id_and_number ON public.purchase_orders USING btree (branch_id, number);


--
-- Name: index_purchase_orders_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchase_orders_on_creator_id ON public.purchase_orders USING btree (creator_id);


--
-- Name: index_purchase_orders_on_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchase_orders_on_supplier_id ON public.purchase_orders USING btree (supplier_id);


--
-- Name: index_registers_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_registers_on_account_id ON public.registers USING btree (account_id);


--
-- Name: index_registers_on_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_registers_on_branch_id ON public.registers USING btree (branch_id);


--
-- Name: index_registers_on_branch_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_registers_on_branch_id_and_name ON public.registers USING btree (branch_id, name);


--
-- Name: index_sale_lines_on_customer_order_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_lines_on_customer_order_line_id ON public.sale_lines USING btree (customer_order_line_id);


--
-- Name: index_sale_lines_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_lines_on_product_id ON public.sale_lines USING btree (product_id);


--
-- Name: index_sale_lines_on_product_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_lines_on_product_unit_id ON public.sale_lines USING btree (product_unit_id);


--
-- Name: index_sale_lines_on_sale_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_lines_on_sale_id ON public.sale_lines USING btree (sale_id);


--
-- Name: index_sale_return_lines_on_sale_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_return_lines_on_sale_line_id ON public.sale_return_lines USING btree (sale_line_id);


--
-- Name: index_sale_return_lines_on_sale_return_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_return_lines_on_sale_return_id ON public.sale_return_lines USING btree (sale_return_id);


--
-- Name: index_sale_returns_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_returns_on_account_id_and_created_at ON public.sale_returns USING btree (account_id, created_at);


--
-- Name: index_sale_returns_on_approver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_returns_on_approver_id ON public.sale_returns USING btree (approver_id);


--
-- Name: index_sale_returns_on_branch_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sale_returns_on_branch_id_and_number ON public.sale_returns USING btree (branch_id, number);


--
-- Name: index_sale_returns_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_returns_on_creator_id ON public.sale_returns USING btree (creator_id);


--
-- Name: index_sale_returns_on_sale_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_returns_on_sale_id ON public.sale_returns USING btree (sale_id);


--
-- Name: index_sale_returns_on_shift_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_returns_on_shift_id ON public.sale_returns USING btree (shift_id);


--
-- Name: index_sales_on_account_id_and_completed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_account_id_and_completed_at ON public.sales USING btree (account_id, completed_at);


--
-- Name: index_sales_on_branch_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_on_branch_id_and_number ON public.sales USING btree (branch_id, number) WHERE (number IS NOT NULL);


--
-- Name: index_sales_on_cashier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_cashier_id ON public.sales USING btree (cashier_id);


--
-- Name: index_sales_on_credit_approver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_credit_approver_id ON public.sales USING btree (credit_approver_id);


--
-- Name: index_sales_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_customer_id ON public.sales USING btree (customer_id);


--
-- Name: index_sales_on_customer_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_customer_order_id ON public.sales USING btree (customer_order_id);


--
-- Name: index_sales_on_discount_approver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_discount_approver_id ON public.sales USING btree (discount_approver_id);


--
-- Name: index_sales_on_register_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_register_id ON public.sales USING btree (register_id);


--
-- Name: index_sales_on_register_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_register_id_and_status ON public.sales USING btree (register_id, status);


--
-- Name: index_sales_on_shift_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_shift_id ON public.sales USING btree (shift_id);


--
-- Name: index_sales_on_voided_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_on_voided_by_id ON public.sales USING btree (voided_by_id);


--
-- Name: index_sessions_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_account_id ON public.sessions USING btree (account_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_shifts_on_account_id_and_closed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shifts_on_account_id_and_closed_at ON public.shifts USING btree (account_id, closed_at);


--
-- Name: index_shifts_on_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shifts_on_branch_id ON public.shifts USING btree (branch_id);


--
-- Name: index_shifts_on_closed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shifts_on_closed_by_id ON public.shifts USING btree (closed_by_id);


--
-- Name: index_shifts_on_opened_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shifts_on_opened_by_id ON public.shifts USING btree (opened_by_id);


--
-- Name: index_shifts_on_register_id_and_opened_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shifts_on_register_id_and_opened_at ON public.shifts USING btree (register_id, opened_at);


--
-- Name: index_shifts_one_open_per_register; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shifts_one_open_per_register ON public.shifts USING btree (register_id) WHERE ((status)::text = 'open'::text);


--
-- Name: index_sms_messages_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sms_messages_on_account_id_and_created_at ON public.sms_messages USING btree (account_id, created_at);


--
-- Name: index_sms_messages_on_sender_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sms_messages_on_sender_id ON public.sms_messages USING btree (sender_id);


--
-- Name: index_sms_messages_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sms_messages_on_source ON public.sms_messages USING btree (source_type, source_id);


--
-- Name: index_stock_adjustments_on_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_adjustments_on_branch_id ON public.stock_adjustments USING btree (branch_id);


--
-- Name: index_stock_adjustments_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_adjustments_on_creator_id ON public.stock_adjustments USING btree (creator_id);


--
-- Name: index_stock_adjustments_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_adjustments_on_product_id ON public.stock_adjustments USING btree (product_id);


--
-- Name: index_stock_count_lines_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_count_lines_on_product_id ON public.stock_count_lines USING btree (product_id);


--
-- Name: index_stock_count_lines_on_stock_count_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_count_lines_on_stock_count_id_and_product_id ON public.stock_count_lines USING btree (stock_count_id, product_id);


--
-- Name: index_stock_counts_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_counts_on_account_id_and_created_at ON public.stock_counts USING btree (account_id, created_at);


--
-- Name: index_stock_counts_on_approver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_counts_on_approver_id ON public.stock_counts USING btree (approver_id);


--
-- Name: index_stock_counts_on_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_counts_on_branch_id ON public.stock_counts USING btree (branch_id);


--
-- Name: index_stock_counts_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_counts_on_category_id ON public.stock_counts USING btree (category_id);


--
-- Name: index_stock_counts_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_counts_on_creator_id ON public.stock_counts USING btree (creator_id);


--
-- Name: index_stock_levels_on_account_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_levels_on_account_id_and_product_id ON public.stock_levels USING btree (account_id, product_id);


--
-- Name: index_stock_levels_on_branch_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_levels_on_branch_id_and_product_id ON public.stock_levels USING btree (branch_id, product_id);


--
-- Name: index_stock_levels_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_levels_on_product_id ON public.stock_levels USING btree (product_id);


--
-- Name: index_stock_movements_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_movements_on_account_id_and_created_at ON public.stock_movements USING btree (account_id, created_at);


--
-- Name: index_stock_movements_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_movements_on_creator_id ON public.stock_movements USING btree (creator_id);


--
-- Name: index_stock_movements_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_movements_on_source ON public.stock_movements USING btree (source_type, source_id);


--
-- Name: index_stock_transfer_lines_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_transfer_lines_on_product_id ON public.stock_transfer_lines USING btree (product_id);


--
-- Name: index_stock_transfer_lines_on_stock_transfer_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_transfer_lines_on_stock_transfer_id_and_product_id ON public.stock_transfer_lines USING btree (stock_transfer_id, product_id);


--
-- Name: index_stock_transfers_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_transfers_on_account_id_and_created_at ON public.stock_transfers USING btree (account_id, created_at);


--
-- Name: index_stock_transfers_on_from_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_transfers_on_from_branch_id ON public.stock_transfers USING btree (from_branch_id);


--
-- Name: index_stock_transfers_on_receiver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_transfers_on_receiver_id ON public.stock_transfers USING btree (receiver_id);


--
-- Name: index_stock_transfers_on_sender_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_transfers_on_sender_id ON public.stock_transfers USING btree (sender_id);


--
-- Name: index_stock_transfers_on_to_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_transfers_on_to_branch_id ON public.stock_transfers USING btree (to_branch_id);


--
-- Name: index_supplier_invoices_on_account_id_and_invoice_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supplier_invoices_on_account_id_and_invoice_date ON public.supplier_invoices USING btree (account_id, invoice_date);


--
-- Name: index_supplier_invoices_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supplier_invoices_on_creator_id ON public.supplier_invoices USING btree (creator_id);


--
-- Name: index_supplier_invoices_on_goods_receipt_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supplier_invoices_on_goods_receipt_id ON public.supplier_invoices USING btree (goods_receipt_id);


--
-- Name: index_supplier_invoices_on_supplier_id_and_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supplier_invoices_on_supplier_id_and_due_date ON public.supplier_invoices USING btree (supplier_id, due_date);


--
-- Name: index_supplier_invoices_on_supplier_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_supplier_invoices_on_supplier_id_and_number ON public.supplier_invoices USING btree (supplier_id, number);


--
-- Name: index_supplier_payments_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supplier_payments_on_creator_id ON public.supplier_payments USING btree (creator_id);


--
-- Name: index_supplier_payments_on_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supplier_payments_on_supplier_id ON public.supplier_payments USING btree (supplier_id);


--
-- Name: index_supplier_products_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supplier_products_on_product_id ON public.supplier_products USING btree (product_id);


--
-- Name: index_supplier_products_on_supplier_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_supplier_products_on_supplier_id_and_product_id ON public.supplier_products USING btree (supplier_id, product_id);


--
-- Name: index_suppliers_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_suppliers_on_account_id_and_name ON public.suppliers USING btree (account_id, name);


--
-- Name: index_suppliers_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_suppliers_on_name ON public.suppliers USING gin (name public.gin_trgm_ops);


--
-- Name: index_tax_rates_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tax_rates_on_account_id_and_name ON public.tax_rates USING btree (account_id, name);


--
-- Name: index_units_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_units_on_account_id_and_name ON public.units USING btree (account_id, name);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: stock_count_lines fk_rails_039c3d997e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_count_lines
    ADD CONSTRAINT fk_rails_039c3d997e FOREIGN KEY (stock_count_id) REFERENCES public.stock_counts(id) DEFERRABLE;


--
-- Name: customer_payments fk_rails_045749c2cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payments
    ADD CONSTRAINT fk_rails_045749c2cc FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: customer_orders fk_rails_07be4466a9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_orders
    ADD CONSTRAINT fk_rails_07be4466a9 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: product_units fk_rails_0817b7e517; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT fk_rails_0817b7e517 FOREIGN KEY (unit_id) REFERENCES public.units(id) DEFERRABLE;


--
-- Name: delivery_notes fk_rails_08d3745445; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_notes
    ADD CONSTRAINT fk_rails_08d3745445 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: customer_order_lines fk_rails_09b5ec3af1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_lines
    ADD CONSTRAINT fk_rails_09b5ec3af1 FOREIGN KEY (product_unit_id) REFERENCES public.product_units(id) DEFERRABLE;


--
-- Name: mpesa_shortcodes fk_rails_0afac4c3ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_shortcodes
    ADD CONSTRAINT fk_rails_0afac4c3ad FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: stock_transfer_lines fk_rails_100e940960; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_lines
    ADD CONSTRAINT fk_rails_100e940960 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: customer_orders fk_rails_13f33fda6c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_orders
    ADD CONSTRAINT fk_rails_13f33fda6c FOREIGN KEY (customer_id) REFERENCES public.customers(id) DEFERRABLE;


--
-- Name: supplier_invoices fk_rails_14468d4381; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_invoices
    ADD CONSTRAINT fk_rails_14468d4381 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: supplier_payments fk_rails_1472ef0893; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_payments
    ADD CONSTRAINT fk_rails_1472ef0893 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: shifts fk_rails_153ce46569; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT fk_rails_153ce46569 FOREIGN KEY (register_id) REFERENCES public.registers(id) DEFERRABLE;


--
-- Name: events fk_rails_15c34a9137; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_15c34a9137 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: events fk_rails_17c5f28626; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_17c5f28626 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: etims_item_registrations fk_rails_1817605044; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_item_registrations
    ADD CONSTRAINT fk_rails_1817605044 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: supplier_payments fk_rails_1846f352d5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_payments
    ADD CONSTRAINT fk_rails_1846f352d5 FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) DEFERRABLE;


--
-- Name: etims_devices fk_rails_184c56433c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_devices
    ADD CONSTRAINT fk_rails_184c56433c FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: sales fk_rails_1ce6d6bb84; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_1ce6d6bb84 FOREIGN KEY (customer_order_id) REFERENCES public.customer_orders(id) DEFERRABLE;


--
-- Name: supplier_invoices fk_rails_1ced2062f2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_invoices
    ADD CONSTRAINT fk_rails_1ced2062f2 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: stock_counts fk_rails_1cf6040ee2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_counts
    ADD CONSTRAINT fk_rails_1cf6040ee2 FOREIGN KEY (approver_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: mpesa_stk_requests fk_rails_1d2e5d8b9d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_stk_requests
    ADD CONSTRAINT fk_rails_1d2e5d8b9d FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: purchase_orders fk_rails_1d67bb2d7b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT fk_rails_1d67bb2d7b FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) DEFERRABLE;


--
-- Name: stock_movements fk_rails_1e404f4e69; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_1e404f4e69 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: stock_counts fk_rails_1f3c89c8eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_counts
    ADD CONSTRAINT fk_rails_1f3c89c8eb FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: stock_movements fk_rails_2243dd98bb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_2243dd98bb FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: supplier_invoices fk_rails_291f86350e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_invoices
    ADD CONSTRAINT fk_rails_291f86350e FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) DEFERRABLE;


--
-- Name: stock_adjustments fk_rails_2beda46d36; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_adjustments
    ADD CONSTRAINT fk_rails_2beda46d36 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: supplier_products fk_rails_2d632ee52e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_products
    ADD CONSTRAINT fk_rails_2d632ee52e FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: goods_receipts fk_rails_2ed6dc1c7f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT fk_rails_2ed6dc1c7f FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: cash_movements fk_rails_3709e4898d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_3709e4898d FOREIGN KEY (shift_id) REFERENCES public.shifts(id) DEFERRABLE;


--
-- Name: product_imports fk_rails_3d203e20af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_imports
    ADD CONSTRAINT fk_rails_3d203e20af FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: registers fk_rails_3d6ef39a50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registers
    ADD CONSTRAINT fk_rails_3d6ef39a50 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: stock_transfers fk_rails_407d4ecd77; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT fk_rails_407d4ecd77 FOREIGN KEY (receiver_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: products fk_rails_436525b193; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_436525b193 FOREIGN KEY (unit_id) REFERENCES public.units(id) DEFERRABLE;


--
-- Name: sales fk_rails_4449f8e567; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_4449f8e567 FOREIGN KEY (cashier_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: cash_movements fk_rails_4567471f5f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_4567471f5f FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: customer_order_lines fk_rails_457f9ffe1c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_lines
    ADD CONSTRAINT fk_rails_457f9ffe1c FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: customer_payments fk_rails_46bd4fcc4d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payments
    ADD CONSTRAINT fk_rails_46bd4fcc4d FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: barcodes fk_rails_480951f2bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barcodes
    ADD CONSTRAINT fk_rails_480951f2bc FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: admin_sessions fk_rails_485432b69c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_sessions
    ADD CONSTRAINT fk_rails_485432b69c FOREIGN KEY (user_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: sms_messages fk_rails_487dcbac01; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_messages
    ADD CONSTRAINT fk_rails_487dcbac01 FOREIGN KEY (sender_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: sale_returns fk_rails_49a99170eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT fk_rails_49a99170eb FOREIGN KEY (sale_id) REFERENCES public.sales(id) DEFERRABLE;


--
-- Name: stock_adjustments fk_rails_49bc36f82a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_adjustments
    ADD CONSTRAINT fk_rails_49bc36f82a FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: kit_components fk_rails_4c258499d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kit_components
    ADD CONSTRAINT fk_rails_4c258499d2 FOREIGN KEY (component_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: stock_transfers fk_rails_4d5a54adc6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT fk_rails_4d5a54adc6 FOREIGN KEY (sender_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: mpesa_stk_requests fk_rails_4d9dd4a507; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_stk_requests
    ADD CONSTRAINT fk_rails_4d9dd4a507 FOREIGN KEY (payment_id) REFERENCES public.payments(id) DEFERRABLE;


--
-- Name: etims_devices fk_rails_4dcecea8a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_devices
    ADD CONSTRAINT fk_rails_4dcecea8a0 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: categories fk_rails_4fd3bba7e8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT fk_rails_4fd3bba7e8 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: deposits fk_rails_523551a98d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT fk_rails_523551a98d FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: stock_movements fk_rails_52f9c5d347; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_52f9c5d347 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: sessions fk_rails_5599381559; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_5599381559 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: stock_levels fk_rails_5607af8fe7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT fk_rails_5607af8fe7 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: price_list_items fk_rails_592b3cdaf4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT fk_rails_592b3cdaf4 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: delivery_notes fk_rails_5a5cb24495; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_notes
    ADD CONSTRAINT fk_rails_5a5cb24495 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: etims_submissions fk_rails_5aa9444ca6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_submissions
    ADD CONSTRAINT fk_rails_5aa9444ca6 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: registers fk_rails_5af33f0b45; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registers
    ADD CONSTRAINT fk_rails_5af33f0b45 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: sales fk_rails_5b8efe3d2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_5b8efe3d2e FOREIGN KEY (discount_approver_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: purchase_orders fk_rails_5c343fe226; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT fk_rails_5c343fe226 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: delivery_notes fk_rails_5d133c6939; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_notes
    ADD CONSTRAINT fk_rails_5d133c6939 FOREIGN KEY (sale_id) REFERENCES public.sales(id) DEFERRABLE;


--
-- Name: sale_returns fk_rails_5d56732d50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT fk_rails_5d56732d50 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: etims_item_registrations fk_rails_5f20ac645c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_item_registrations
    ADD CONSTRAINT fk_rails_5f20ac645c FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: shifts fk_rails_64dbadba30; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT fk_rails_64dbadba30 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: customer_order_lines fk_rails_65d173b232; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_lines
    ADD CONSTRAINT fk_rails_65d173b232 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: goods_receipts fk_rails_68b64d7d0c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT fk_rails_68b64d7d0c FOREIGN KEY (receiver_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: customer_payments fk_rails_6a2298bcd2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payments
    ADD CONSTRAINT fk_rails_6a2298bcd2 FOREIGN KEY (customer_id) REFERENCES public.customers(id) DEFERRABLE;


--
-- Name: products fk_rails_6dc06b37ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_6dc06b37ef FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: sales fk_rails_6e7599c2ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_6e7599c2ae FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: kit_components fk_rails_6f4cbebe89; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kit_components
    ADD CONSTRAINT fk_rails_6f4cbebe89 FOREIGN KEY (kit_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: mpesa_transactions fk_rails_6fff61037d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_transactions
    ADD CONSTRAINT fk_rails_6fff61037d FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: sale_returns fk_rails_71880e17ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT fk_rails_71880e17ea FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: stock_adjustments fk_rails_725b9e1daf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_adjustments
    ADD CONSTRAINT fk_rails_725b9e1daf FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: mpesa_stk_requests fk_rails_734fdbc1b4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_stk_requests
    ADD CONSTRAINT fk_rails_734fdbc1b4 FOREIGN KEY (sale_id) REFERENCES public.sales(id) DEFERRABLE;


--
-- Name: sale_return_lines fk_rails_74c5caa1fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_lines
    ADD CONSTRAINT fk_rails_74c5caa1fe FOREIGN KEY (sale_line_id) REFERENCES public.sale_lines(id) DEFERRABLE;


--
-- Name: stock_transfers fk_rails_74db096ab8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT fk_rails_74db096ab8 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: stock_counts fk_rails_74decdd260; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_counts
    ADD CONSTRAINT fk_rails_74decdd260 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: shifts fk_rails_791f504d7e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT fk_rails_791f504d7e FOREIGN KEY (opened_by_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: stock_counts fk_rails_79e8c88cba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_counts
    ADD CONSTRAINT fk_rails_79e8c88cba FOREIGN KEY (category_id) REFERENCES public.categories(id) DEFERRABLE;


--
-- Name: sales fk_rails_7c1f560977; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_7c1f560977 FOREIGN KEY (customer_id) REFERENCES public.customers(id) DEFERRABLE;


--
-- Name: price_lists fk_rails_7d8d7d3a3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_lists
    ADD CONSTRAINT fk_rails_7d8d7d3a3d FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: sale_returns fk_rails_7ef5cafe23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT fk_rails_7ef5cafe23 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: payments fk_rails_81b2605d2a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_rails_81b2605d2a FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: categories fk_rails_82f48f7407; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT fk_rails_82f48f7407 FOREIGN KEY (parent_id) REFERENCES public.categories(id) DEFERRABLE;


--
-- Name: branches fk_rails_863a15f468; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT fk_rails_863a15f468 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: price_list_items fk_rails_868b9d34b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT fk_rails_868b9d34b5 FOREIGN KEY (price_list_id) REFERENCES public.price_lists(id) DEFERRABLE;


--
-- Name: deposits fk_rails_869f62908d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT fk_rails_869f62908d FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: supplier_payments fk_rails_89a9bab56d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_payments
    ADD CONSTRAINT fk_rails_89a9bab56d FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: goods_receipts fk_rails_8cb1c140bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT fk_rails_8cb1c140bf FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: supplier_products fk_rails_8e1c65b71a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_products
    ADD CONSTRAINT fk_rails_8e1c65b71a FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) DEFERRABLE;


--
-- Name: sale_returns fk_rails_94137afb72; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT fk_rails_94137afb72 FOREIGN KEY (approver_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: stock_count_lines fk_rails_95d9016807; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_count_lines
    ADD CONSTRAINT fk_rails_95d9016807 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: deposits fk_rails_963028660e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT fk_rails_963028660e FOREIGN KEY (shift_id) REFERENCES public.shifts(id) DEFERRABLE;


--
-- Name: sessions fk_rails_96502740f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_96502740f9 FOREIGN KEY (impersonator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: sale_returns fk_rails_97b234ef8b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT fk_rails_97b234ef8b FOREIGN KEY (shift_id) REFERENCES public.shifts(id) DEFERRABLE;


--
-- Name: memberships fk_rails_99326fb65d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_99326fb65d FOREIGN KEY (user_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id) DEFERRABLE;


--
-- Name: supplier_products fk_rails_9a363579c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_products
    ADD CONSTRAINT fk_rails_9a363579c5 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: document_sequences fk_rails_9acc2b60b1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_sequences
    ADD CONSTRAINT fk_rails_9acc2b60b1 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: product_imports fk_rails_9c4c03515c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_imports
    ADD CONSTRAINT fk_rails_9c4c03515c FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: goods_receipt_lines fk_rails_9f16d899e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT fk_rails_9f16d899e5 FOREIGN KEY (purchase_order_line_id) REFERENCES public.purchase_order_lines(id) DEFERRABLE;


--
-- Name: units fk_rails_a04853fc0a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT fk_rails_a04853fc0a FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: product_units fk_rails_a0982ff51e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT fk_rails_a0982ff51e FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: purchase_order_lines fk_rails_a4215877c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT fk_rails_a4215877c0 FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) DEFERRABLE;


--
-- Name: sale_return_lines fk_rails_a63cffa5db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_lines
    ADD CONSTRAINT fk_rails_a63cffa5db FOREIGN KEY (sale_return_id) REFERENCES public.sale_returns(id) DEFERRABLE;


--
-- Name: shifts fk_rails_a644c1fb7c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT fk_rails_a644c1fb7c FOREIGN KEY (closed_by_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: purchase_order_lines fk_rails_a75963ca00; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT fk_rails_a75963ca00 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: document_sequences fk_rails_a8ef275743; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_sequences
    ADD CONSTRAINT fk_rails_a8ef275743 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: mpesa_stk_requests fk_rails_aa751da206; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_stk_requests
    ADD CONSTRAINT fk_rails_aa751da206 FOREIGN KEY (shortcode_id) REFERENCES public.mpesa_shortcodes(id) DEFERRABLE;


--
-- Name: sales fk_rails_ab14f0c7ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_ab14f0c7ff FOREIGN KEY (voided_by_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: shifts fk_rails_ac3cac7c53; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT fk_rails_ac3cac7c53 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: payments fk_rails_b09036db54; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_rails_b09036db54 FOREIGN KEY (sale_id) REFERENCES public.sales(id) DEFERRABLE;


--
-- Name: suppliers fk_rails_b2568e91c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT fk_rails_b2568e91c4 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: customer_payments fk_rails_b70f755a3f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payments
    ADD CONSTRAINT fk_rails_b70f755a3f FOREIGN KEY (shift_id) REFERENCES public.shifts(id) DEFERRABLE;


--
-- Name: sale_return_lines fk_rails_b7496a0bb6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_lines
    ADD CONSTRAINT fk_rails_b7496a0bb6 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: supplier_invoices fk_rails_b87e804d59; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_invoices
    ADD CONSTRAINT fk_rails_b87e804d59 FOREIGN KEY (goods_receipt_id) REFERENCES public.goods_receipts(id) DEFERRABLE;


--
-- Name: goods_receipt_lines fk_rails_b8f8f3e8a5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT fk_rails_b8f8f3e8a5 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: goods_receipts fk_rails_bbe00c5362; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT fk_rails_bbe00c5362 FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) DEFERRABLE;


--
-- Name: sms_messages fk_rails_bd9e782380; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_messages
    ADD CONSTRAINT fk_rails_bd9e782380 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: customer_orders fk_rails_bdb6d95444; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_orders
    ADD CONSTRAINT fk_rails_bdb6d95444 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: etims_item_registrations fk_rails_bf0a6f8617; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_item_registrations
    ADD CONSTRAINT fk_rails_bf0a6f8617 FOREIGN KEY (device_id) REFERENCES public.etims_devices(id) DEFERRABLE;


--
-- Name: stock_transfers fk_rails_bfe016d5ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT fk_rails_bfe016d5ae FOREIGN KEY (to_branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: purchase_orders fk_rails_c3649bab02; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT fk_rails_c3649bab02 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id) DEFERRABLE;


--
-- Name: purchase_order_lines fk_rails_c4844677c7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT fk_rails_c4844677c7 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: barcodes fk_rails_c4f3f76a0d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barcodes
    ADD CONSTRAINT fk_rails_c4f3f76a0d FOREIGN KEY (product_unit_id) REFERENCES public.product_units(id) DEFERRABLE;


--
-- Name: deposits fk_rails_c92b54cb89; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT fk_rails_c92b54cb89 FOREIGN KEY (customer_order_id) REFERENCES public.customer_orders(id) DEFERRABLE;


--
-- Name: kit_components fk_rails_ce48264f0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kit_components
    ADD CONSTRAINT fk_rails_ce48264f0b FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: delivery_notes fk_rails_cf07ace81d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_notes
    ADD CONSTRAINT fk_rails_cf07ace81d FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: sale_lines fk_rails_d1a1fea6f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_lines
    ADD CONSTRAINT fk_rails_d1a1fea6f0 FOREIGN KEY (customer_order_line_id) REFERENCES public.customer_order_lines(id) DEFERRABLE;


--
-- Name: customer_order_lines fk_rails_d48831d047; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order_lines
    ADD CONSTRAINT fk_rails_d48831d047 FOREIGN KEY (customer_order_id) REFERENCES public.customer_orders(id) DEFERRABLE;


--
-- Name: customer_orders fk_rails_d4dae4ddfe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_orders
    ADD CONSTRAINT fk_rails_d4dae4ddfe FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: stock_count_lines fk_rails_d96a46556a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_count_lines
    ADD CONSTRAINT fk_rails_d96a46556a FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: stock_levels fk_rails_daaaba7e71; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT fk_rails_daaaba7e71 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: goods_receipt_lines fk_rails_dac7fab7a3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT fk_rails_dac7fab7a3 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: mpesa_transactions fk_rails_dcc3194566; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_transactions
    ADD CONSTRAINT fk_rails_dcc3194566 FOREIGN KEY (shortcode_id) REFERENCES public.mpesa_shortcodes(id) DEFERRABLE;


--
-- Name: mpesa_shortcodes fk_rails_de0d651629; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_shortcodes
    ADD CONSTRAINT fk_rails_de0d651629 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: sales fk_rails_de939a1f04; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_de939a1f04 FOREIGN KEY (register_id) REFERENCES public.registers(id) DEFERRABLE;


--
-- Name: stock_movements fk_rails_deb37fa2ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_deb37fa2ee FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: goods_receipts fk_rails_df6450b6dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT fk_rails_df6450b6dd FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) DEFERRABLE;


--
-- Name: etims_submissions fk_rails_e079f26906; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etims_submissions
    ADD CONSTRAINT fk_rails_e079f26906 FOREIGN KEY (device_id) REFERENCES public.etims_devices(id) DEFERRABLE;


--
-- Name: sales fk_rails_e2379d3017; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_e2379d3017 FOREIGN KEY (branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: brands fk_rails_e23d885924; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT fk_rails_e23d885924 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: stock_transfer_lines fk_rails_e25d7fc485; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_lines
    ADD CONSTRAINT fk_rails_e25d7fc485 FOREIGN KEY (stock_transfer_id) REFERENCES public.stock_transfers(id) DEFERRABLE;


--
-- Name: mpesa_stk_requests fk_rails_e4f337bfe9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mpesa_stk_requests
    ADD CONSTRAINT fk_rails_e4f337bfe9 FOREIGN KEY (requested_by_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: products fk_rails_e50d729180; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_e50d729180 FOREIGN KEY (tax_rate_id) REFERENCES public.tax_rates(id) DEFERRABLE;


--
-- Name: sale_lines fk_rails_e636823f58; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_lines
    ADD CONSTRAINT fk_rails_e636823f58 FOREIGN KEY (sale_id) REFERENCES public.sales(id) DEFERRABLE;


--
-- Name: tax_rates fk_rails_e6fafa7706; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_rates
    ADD CONSTRAINT fk_rails_e6fafa7706 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: stock_levels fk_rails_e76267ceb9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT fk_rails_e76267ceb9 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: cash_movements fk_rails_e76e79a2c1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_e76e79a2c1 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: price_list_items fk_rails_e772b9cb5f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT fk_rails_e772b9cb5f FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: customers fk_rails_ea95afa005; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_ea95afa005 FOREIGN KEY (price_list_id) REFERENCES public.price_lists(id) DEFERRABLE;


--
-- Name: sale_lines fk_rails_ebd0e69cb7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_lines
    ADD CONSTRAINT fk_rails_ebd0e69cb7 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: sales fk_rails_ec4ebc1eb6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_ec4ebc1eb6 FOREIGN KEY (shift_id) REFERENCES public.shifts(id) DEFERRABLE;


--
-- Name: customers fk_rails_ed7ccfecee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_ed7ccfecee FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: memberships fk_rails_edbc202c67; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_edbc202c67 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: product_imports fk_rails_ee10a7fc5b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_imports
    ADD CONSTRAINT fk_rails_ee10a7fc5b FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: product_units fk_rails_f23d08af71; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT fk_rails_f23d08af71 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: stock_counts fk_rails_f245e0e820; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_counts
    ADD CONSTRAINT fk_rails_f245e0e820 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: sale_lines fk_rails_f2b75ee91f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_lines
    ADD CONSTRAINT fk_rails_f2b75ee91f FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: stock_transfer_lines fk_rails_f2e00b1f87; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_lines
    ADD CONSTRAINT fk_rails_f2e00b1f87 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: goods_receipt_lines fk_rails_f2f12b04b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT fk_rails_f2f12b04b3 FOREIGN KEY (goods_receipt_id) REFERENCES public.goods_receipts(id) DEFERRABLE;


--
-- Name: purchase_orders fk_rails_f3a3354387; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT fk_rails_f3a3354387 FOREIGN KEY (account_id) REFERENCES public.accounts(id) DEFERRABLE;


--
-- Name: sales fk_rails_f3a8888c10; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_rails_f3a8888c10 FOREIGN KEY (credit_approver_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: products fk_rails_f3b4d49caa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_f3b4d49caa FOREIGN KEY (brand_id) REFERENCES public.brands(id) DEFERRABLE;


--
-- Name: stock_adjustments fk_rails_f41864ed33; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_adjustments
    ADD CONSTRAINT fk_rails_f41864ed33 FOREIGN KEY (creator_id) REFERENCES public.users(id) DEFERRABLE;


--
-- Name: barcodes fk_rails_f6f6672052; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barcodes
    ADD CONSTRAINT fk_rails_f6f6672052 FOREIGN KEY (product_id) REFERENCES public.products(id) DEFERRABLE;


--
-- Name: sale_lines fk_rails_f8599f972d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_lines
    ADD CONSTRAINT fk_rails_f8599f972d FOREIGN KEY (product_unit_id) REFERENCES public.product_units(id) DEFERRABLE;


--
-- Name: products fk_rails_fb915499a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_fb915499a4 FOREIGN KEY (category_id) REFERENCES public.categories(id) DEFERRABLE;


--
-- Name: stock_transfers fk_rails_fcc993a913; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT fk_rails_fcc993a913 FOREIGN KEY (from_branch_id) REFERENCES public.branches(id) DEFERRABLE;


--
-- Name: barcodes account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.barcodes USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: branches account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.branches USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: brands account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.brands USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: cash_movements account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.cash_movements USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: categories account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.categories USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: customer_order_lines account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.customer_order_lines USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: customer_orders account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.customer_orders USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: customer_payments account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.customer_payments USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: customers account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.customers USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: delivery_notes account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.delivery_notes USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: deposits account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.deposits USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: document_sequences account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.document_sequences USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: etims_devices account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.etims_devices USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: etims_item_registrations account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.etims_item_registrations USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: etims_submissions account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.etims_submissions USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: events account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.events USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: goods_receipt_lines account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.goods_receipt_lines USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: goods_receipts account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.goods_receipts USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: kit_components account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.kit_components USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: memberships account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.memberships USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: mpesa_shortcodes account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.mpesa_shortcodes USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: mpesa_stk_requests account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.mpesa_stk_requests USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: mpesa_transactions account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.mpesa_transactions USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: payments account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.payments USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: price_list_items account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.price_list_items USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: price_lists account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.price_lists USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: product_imports account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.product_imports USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: product_units account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.product_units USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: products account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.products USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: purchase_order_lines account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.purchase_order_lines USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: purchase_orders account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.purchase_orders USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: registers account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.registers USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: sale_lines account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.sale_lines USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: sale_return_lines account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.sale_return_lines USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: sale_returns account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.sale_returns USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: sales account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.sales USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: sessions account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.sessions USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: shifts account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.shifts USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: sms_messages account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.sms_messages USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: stock_adjustments account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.stock_adjustments USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: stock_count_lines account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.stock_count_lines USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: stock_counts account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.stock_counts USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: stock_levels account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.stock_levels USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: stock_movements account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.stock_movements USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: stock_transfer_lines account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.stock_transfer_lines USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: stock_transfers account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.stock_transfers USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: supplier_invoices account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.supplier_invoices USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: supplier_payments account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.supplier_payments USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: supplier_products account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.supplier_products USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: suppliers account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.suppliers USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: tax_rates account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.tax_rates USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: units account_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY account_isolation ON public.units USING (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint))) WITH CHECK (((current_setting('app.bypass_rls'::text, true) = 'on'::text) OR (account_id = (NULLIF(current_setting('app.current_account_id'::text, true), ''::text))::bigint)));


--
-- Name: barcodes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.barcodes ENABLE ROW LEVEL SECURITY;

--
-- Name: branches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

--
-- Name: brands; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.brands ENABLE ROW LEVEL SECURITY;

--
-- Name: cash_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cash_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: delivery_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delivery_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: deposits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deposits ENABLE ROW LEVEL SECURITY;

--
-- Name: document_sequences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_sequences ENABLE ROW LEVEL SECURITY;

--
-- Name: etims_devices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.etims_devices ENABLE ROW LEVEL SECURITY;

--
-- Name: etims_item_registrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.etims_item_registrations ENABLE ROW LEVEL SECURITY;

--
-- Name: etims_submissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.etims_submissions ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: goods_receipt_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.goods_receipt_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: goods_receipts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.goods_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: kit_components; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kit_components ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: mpesa_shortcodes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mpesa_shortcodes ENABLE ROW LEVEL SECURITY;

--
-- Name: mpesa_stk_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mpesa_stk_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: mpesa_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mpesa_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: price_list_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.price_list_items ENABLE ROW LEVEL SECURITY;

--
-- Name: price_lists; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.price_lists ENABLE ROW LEVEL SECURITY;

--
-- Name: product_imports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_imports ENABLE ROW LEVEL SECURITY;

--
-- Name: product_units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_units ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: registers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.registers ENABLE ROW LEVEL SECURITY;

--
-- Name: sale_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sale_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: sale_return_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sale_return_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: sale_returns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sale_returns ENABLE ROW LEVEL SECURITY;

--
-- Name: sales; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: shifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;

--
-- Name: sms_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sms_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_adjustments ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_count_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_count_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_counts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_counts ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_levels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_levels ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_transfer_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_transfer_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_transfers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supplier_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supplier_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier_products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supplier_products ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- Name: tax_rates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tax_rates ENABLE ROW LEVEL SECURITY;

--
-- Name: units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260925120200'),
('20260925120100'),
('20260925120000'),
('20260925110000'),
('20260925100000'),
('20260925090401'),
('20260925090400'),
('20260925090300'),
('20260925090200'),
('20260925090100'),
('20260925090000'),
('20260924100400'),
('20260924100300'),
('20260924100200'),
('20260924100100'),
('20260924100000'),
('20260924083604'),
('20260924083603'),
('20260924083602'),
('20260924083601'),
('20260924083600');

