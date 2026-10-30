/**
 * Presentation helpers for Stage 3 User Licence Comparison (backend JSON → UI view model).
 */

export const LICENSE_COMPARISON_TABLE_COLUMNS = [
    { label: 'Licence name', fieldName: 'name', type: 'text', wrapText: true },
    { label: 'Total', fieldName: 'totalLicenses', type: 'text' },
    { label: 'Used', fieldName: 'usedLicenses', type: 'text' },
    { label: 'Details', fieldName: 'details', type: 'text', wrapText: true }
];

export function parseLicenseComparisonJson(resultString) {
    if (resultString == null || resultString === '') {
        return { parseError: 'License comparison returned an empty response.' };
    }

    if (typeof resultString !== 'string') {
        return { parseError: 'License comparison returned an invalid response.' };
    }

    try {
        const data = JSON.parse(resultString);
        if (data == null || typeof data !== 'object' || Array.isArray(data)) {
            return { parseError: 'License comparison returned an invalid response.' };
        }
        return { data };
    } catch (_ignore) {
        return { parseError: 'License comparison returned invalid JSON.' };
    }
}

export function buildLicenseComparisonDisplay(data) {
    if (!data || typeof data !== 'object') {
        return failureView('License comparison returned no data.');
    }

    if (data.success === false) {
        return failureView(formatBackendError(data), normalizeWarnings(data.warnings));
    }

    if (data.statusCode === 400 && data.error) {
        return failureView(String(data.error));
    }

    const sourceLicenses = extractLicenseList(data.source);
    const destinationLicenses = extractLicenseList(data.destination);
    const both = normalizeComparisonEntries(data.both, 'both');
    const sourceOnly = normalizeComparisonEntries(data.sourceOnly, 'sourceOnly');
    const destinationOnly = normalizeComparisonEntries(
        data.destinationOnly,
        'destinationOnly'
    );
    const unmatched = normalizeUnmatchedEntries(data.unmatched);
    const warnings = normalizeWarnings(data.warnings);

    const tables = {
        source: mapLicenseRows(sourceLicenses, 'source'),
        destination: mapLicenseRows(destinationLicenses, 'destination'),
        both,
        sourceOnly,
        destinationOnly,
        unmatched
    };

    const hasAnyResults =
        tables.source.length > 0 ||
        tables.destination.length > 0 ||
        tables.both.length > 0 ||
        tables.sourceOnly.length > 0 ||
        tables.destinationOnly.length > 0 ||
        tables.unmatched.length > 0;

    if (!hasAnyResults && warnings.length === 0 && data.success !== true) {
        return failureView(
            'License comparison completed but returned no licence data.'
        );
    }

    return {
        isSuccess: true,
        errorMessage: null,
        warningMessages: warnings,
        hasWarnings: warnings.length > 0,
        kpis: {
            sourceCount: tables.source.length,
            destinationCount: tables.destination.length,
            bothCount: tables.both.length,
            sourceOnlyCount: tables.sourceOnly.length,
            destinationOnlyCount: tables.destinationOnly.length,
            unmatchedCount: tables.unmatched.length
        },
        tables,
        hasAnyResults
    };
}

function failureView(errorMessage, warningMessages = []) {
    const warnings = Array.isArray(warningMessages) ? warningMessages : [];
    return {
        isSuccess: false,
        errorMessage: errorMessage || 'License comparison failed.',
        warningMessages: warnings,
        hasWarnings: warnings.length > 0,
        kpis: emptyKpis(),
        tables: emptyTables(),
        hasAnyResults: false
    };
}

function emptyKpis() {
    return {
        sourceCount: 0,
        destinationCount: 0,
        bothCount: 0,
        sourceOnlyCount: 0,
        destinationOnlyCount: 0,
        unmatchedCount: 0
    };
}

function emptyTables() {
    return {
        source: [],
        destination: [],
        both: [],
        sourceOnly: [],
        destinationOnly: [],
        unmatched: []
    };
}

function formatBackendError(data) {
    const parts = [];
    if (data.error) {
        parts.push(String(data.error));
    }
    if (data.failedSide) {
        parts.push(`Failed side: ${data.failedSide}`);
    }
    if (data.code) {
        parts.push(`Code: ${data.code}`);
    }
    return parts.length
        ? parts.join(' ')
        : 'License comparison failed for one or both orgs.';
}

function extractLicenseList(side) {
    if (!side || typeof side !== 'object') {
        return [];
    }
    if (Array.isArray(side.licenses)) {
        return side.licenses;
    }
    if (Array.isArray(side)) {
        return side;
    }
    return [];
}

function normalizeWarnings(warnings) {
    if (!Array.isArray(warnings)) {
        return [];
    }

    return warnings
        .map((entry) => {
            if (entry == null) {
                return '';
            }
            if (typeof entry === 'string') {
                return entry.trim();
            }
            if (typeof entry === 'object') {
                return (
                    entry.message ||
                    entry.warning ||
                    entry.text ||
                    entry.detail ||
                    ''
                )
                    .toString()
                    .trim();
            }
            return String(entry).trim();
        })
        .filter((text) => text);
}

function normalizeComparisonEntries(entries, prefix) {
    if (!Array.isArray(entries)) {
        return [];
    }

    return entries
        .map((entry, index) => mapLicenseRow(entry, `${prefix}-${index}`))
        .filter(Boolean);
}

function normalizeUnmatchedEntries(unmatched) {
    if (unmatched == null) {
        return [];
    }

    if (Array.isArray(unmatched)) {
        return normalizeComparisonEntries(unmatched, 'unmatched');
    }

    if (typeof unmatched !== 'object') {
        return [];
    }

    const rows = [];
    const sourceList = Array.isArray(unmatched.source) ? unmatched.source : [];
    const destinationList = Array.isArray(unmatched.destination)
        ? unmatched.destination
        : [];

    sourceList.forEach((entry, index) => {
        const row = mapUnmatchedRow(entry, `unmatched-source-${index}`, 'Source');
        if (row) {
            rows.push(row);
        }
    });

    destinationList.forEach((entry, index) => {
        const row = mapUnmatchedRow(
            entry,
            `unmatched-destination-${index}`,
            'Destination'
        );
        if (row) {
            rows.push(row);
        }
    });

    return rows;
}

function mapUnmatchedRow(entry, id, originLabel) {
    const row = mapLicenseRow(entry, id);
    if (!row) {
        return null;
    }

    return {
        ...row,
        details: appendDetailPart(row.details, `Origin: ${originLabel}`)
    };
}

function mapLicenseRows(licenses, prefix) {
    if (!Array.isArray(licenses)) {
        return [];
    }

    return licenses
        .map((entry, index) => mapLicenseRow(entry, `${prefix}-${index}`))
        .filter(Boolean);
}

function mapLicenseRow(entry, id) {
    if (entry == null) {
        return null;
    }

    if (typeof entry === 'string') {
        const name = entry.trim();
        if (!name) {
            return null;
        }
        return {
            id,
            name,
            totalLicenses: '—',
            usedLicenses: '—',
            details: '—'
        };
    }

    if (typeof entry !== 'object') {
        return null;
    }

    if (isBothComparisonEntry(entry)) {
        return mapBothComparisonEntry(entry, id);
    }

    if (isNestedLicenseComparisonEntry(entry)) {
        const comparisonKey = readComparisonKey(entry);
        return mapLicenseRecord(entry.license, id, comparisonKey);
    }

    const comparisonKey = readComparisonKey(entry);
    if (comparisonKey && !hasLicenseIdentityFields(entry)) {
        return null;
    }

    return mapLicenseRecord(entry, id, comparisonKey);
}

function isBothComparisonEntry(entry) {
    return (
        entry.source != null &&
        typeof entry.source === 'object' &&
        entry.destination != null &&
        typeof entry.destination === 'object'
    );
}

function isNestedLicenseComparisonEntry(entry) {
    return entry.license != null && typeof entry.license === 'object';
}

function hasLicenseIdentityFields(entry) {
    return !!(
        resolveLicenseName(entry) ||
        entry.totalLicenses != null ||
        entry.TotalLicenses != null ||
        entry.usedLicenses != null ||
        entry.UsedLicenses != null
    );
}

function mapBothComparisonEntry(entry, id) {
    const comparisonKey = readComparisonKey(entry);
    const source = entry.source;
    const destination = entry.destination;
    const sourceName = resolveLicenseName(source);
    const destinationName = resolveLicenseName(destination);

    let name = '—';
    if (sourceName && destinationName) {
        name =
            sourceName === destinationName
                ? sourceName
                : `${sourceName} / ${destinationName}`;
    } else {
        name = sourceName || destinationName || comparisonKey || '—';
    }

    const detailsParts = [];
    if (comparisonKey && comparisonKey !== name && comparisonKey !== sourceName) {
        detailsParts.push(`Key: ${comparisonKey}`);
    }
    if (sourceName) {
        detailsParts.push(
            `Source: ${sourceName} (${formatCount(source.totalLicenses)}/${formatCount(source.usedLicenses)})`
        );
    }
    if (destinationName) {
        detailsParts.push(
            `Destination: ${destinationName} (${formatCount(destination.totalLicenses)}/${formatCount(destination.usedLicenses)})`
        );
    }

    return {
        id,
        name: String(name),
        totalLicenses: formatCount(
            source.totalLicenses ?? source.TotalLicenses
        ),
        usedLicenses: formatCount(
            destination.usedLicenses ?? destination.UsedLicenses
        ),
        details: detailsParts.length ? detailsParts.join(' · ') : '—'
    };
}

function mapLicenseRecord(license, id, comparisonKey) {
    if (!license || typeof license !== 'object') {
        return null;
    }

    const resolvedName = resolveLicenseName(license);
    const name = resolvedName || comparisonKey || '—';

    return {
        id,
        name: String(name),
        totalLicenses: formatCount(
            license.totalLicenses ?? license.TotalLicenses
        ),
        usedLicenses: formatCount(
            license.usedLicenses ?? license.UsedLicenses
        ),
        details: buildDetails(license, comparisonKey, resolvedName)
    };
}

function readComparisonKey(entry) {
    if (!entry || typeof entry !== 'object') {
        return '';
    }
    return (
        entry.licenseDefinitionKey ||
        entry.LicenseDefinitionKey ||
        ''
    ).toString().trim();
}

function resolveLicenseName(license) {
    if (!license || typeof license !== 'object') {
        return '';
    }

    const name = (
        license.name ||
        license.masterLabel ||
        license.label ||
        license.MasterLabel ||
        ''
    )
        .toString()
        .trim();

    return name;
}

function formatCount(value) {
    if (value === null || value === undefined || value === '') {
        return '—';
    }
    if (typeof value === 'number' && Number.isFinite(value)) {
        return String(value);
    }
    const text = String(value).trim();
    return text || '—';
}

function buildDetails(license, comparisonKey, resolvedName) {
    const parts = [];
    const key =
        comparisonKey ||
        license.licenseDefinitionKey ||
        license.LicenseDefinitionKey;
    const name = resolvedName || resolveLicenseName(license);
    const status = license.status || license.Status;

    if (key && key !== name) {
        parts.push(`Key: ${key}`);
    }
    if (status) {
        parts.push(`Status: ${status}`);
    }

    return parts.length ? parts.join(' · ') : '—';
}

function appendDetailPart(existingDetails, part) {
    if (!part) {
        return existingDetails || '—';
    }
    if (!existingDetails || existingDetails === '—') {
        return part;
    }
    return `${existingDetails} · ${part}`;
}