/**
 * Strips credential-like keys from untyped control-plane payloads.
 * Never logs request bodies, tokens, or authorization headers.
 */
public with sharing class ControlPlaneSanitize {
    private static final Set<String> FORBIDDEN_KEYS = new Set<String>{
        'refreshtoken',
        'accesstoken',
        'token',
        'authorization',
        'clientsecret',
        'clientid',
        'password',
        'credentials',
        'secret',
        'apikey',
        'sessionid'
    };

    public static Map<String, Object> sanitize(Map<String, Object> raw) {
        if (raw == null) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) cleanValue(raw);
    }

    public static Boolean containsForbiddenKey(Map<String, Object> raw) {
        if (raw == null) {
            return false;
        }
        for (String key : raw.keySet()) {
            if (isForbidden(key)) {
                return true;
            }
            Object value = raw.get(key);
            if (value instanceof Map<String, Object>) {
                if (containsForbiddenKey((Map<String, Object>) value)) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Object cleanValue(Object value) {
        if (value instanceof Map<String, Object>) {
            Map<String, Object> source = (Map<String, Object>) value;
            Map<String, Object> cleaned = new Map<String, Object>();
            for (String key : source.keySet()) {
                if (isForbidden(key)) {
                    continue;
                }
                cleaned.put(key, cleanValue(source.get(key)));
            }
            return cleaned;
        }
        if (value instanceof List<Object>) {
            List<Object> cleaned = new List<Object>();
            for (Object item : (List<Object>) value) {
                cleaned.add(cleanValue(item));
            }
            return cleaned;
        }
        return value;
    }

    private static Boolean isForbidden(String key) {
        return String.isNotBlank(key) &&
            FORBIDDEN_KEYS.contains(key.trim().toLowerCase());
    }
}