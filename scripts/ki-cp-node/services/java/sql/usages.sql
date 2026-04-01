CREATE INDEX idx_pod_usages_ns_res_not_empty
    ON pod_usages (namespace)
    WHERE resources <> '{}'::jsonb;

