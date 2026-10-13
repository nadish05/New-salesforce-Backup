/**
 * Pure rollback async-response parsing and manual-item display helpers.
 */

export const ROLLBACK_MANUAL_ROLLBACK_REQUIRED_CODE =
    'ROLLBACK_MANUAL_ROLLBACK_REQUIRED';

const REASON_CODE_FRIENDLY = Object.freeze({
    RECORDTYPE_DELETE_UNSUPPORTED:
        'Record Type deletion is not supported through the Salesforce Metadata API.',
    ASSOCIATED_WITH_UNSUPPORTED_RECORDTYPE:
        'This Sales Process is associated with a Record Type that requires manual rollback.'
});

const METADATA_TYPE_LABELS = Object.freeze({
    BusinessProcess: 'Sales Process'
});

const INSTRUCTION_BY_REASON_CODE = Object.freeze({
    RECORDTYPE_DELETE_UNSUPPORTED:
        'Manual action required: Delete the Record Type from Salesforce Setup after confirming its dependencies.',
    ASSOCIATED_WITH_UNSUPPORTED_RECORDTYPE:
        'Manual action required: Review/remove the Sales Process from Salesforce Setup as appropriate.'
});

function text(value) {
    return value === undefined || value === null ? '' : String(value).trim();
}

function resolvePayload(parsed) {
    const result =
        parsed.result && typeof parsed.result === 'object' ? parsed.result : {};

    const code =
        text(result.code) ||
        text(parsed.code) ||
        text(parsed.resultCode) ||
        null;

    const message =
        text(result.message) ||
        text(parsed.message) ||
        text(parsed.error) ||
        text(parsed.statusMessage) ||
        'Rollback completed.';

    return {
        status: text(parsed.status).toUpperCase(),
        success: parsed.success,
        blocked: parsed.blocked === true,
        failed: parsed.failed === true,
        unknownResult: parsed.unknownResult === true,
        code,
        message,
        partialSuccess: result.partialSuccess === true,
        manualRollbackRequired:
            result.manualRollbackRequired === true ||
            parsed.manualRollbackRequired === true,
        manualRollbackItems: normalizeManualRollbackItems(
            result.manualRollbackItems ?? parsed.manualRollbackItems
        ),
        operationId: text(parsed.operationId) || null
    };
}

export function normalizeManualRollbackItems(raw) {
    if (!Array.isArray(raw)) {
        return [];
    }

    return raw
        .filter((item) => item && typeof item === 'object')
        .map((item, index) => ({
            metadataType: text(item.metadataType),
            metadataName: text(item.metadataName),
            reasonCode: text(item.reasonCode),
            reason: text(item.reason),
            key: `${text(item.metadataType)}:${text(item.metadataName)}:${index}`
        }));
}

export function metadataTypeDisplayLabel(metadataType) {
    const normalized = text(metadataType);
    return METADATA_TYPE_LABELS[normalized] || normalized || '—';
}

export function friendlyReasonForCode(reasonCode) {
    const code = text(reasonCode);
    return REASON_CODE_FRIENDLY[code] || '';
}

export function manualInstructionForReasonCode(reasonCode) {
    const code = text(reasonCode);
    return INSTRUCTION_BY_REASON_CODE[code] || '';
}

export function formatManualRollbackItemForDisplay(item) {
    const reasonCode = text(item?.reasonCode);
    const backendReason = text(item?.reason);
    const friendlyReason = friendlyReasonForCode(reasonCode);
    const instruction = manualInstructionForReasonCode(reasonCode);

    return {
        key: item?.key || `${item?.metadataType}:${item?.metadataName}`,
        metadataType: text(item?.metadataType),
        metadataTypeLabel: metadataTypeDisplayLabel(item?.metadataType),
        metadataName: text(item?.metadataName),
        reasonCode,
        reason: backendReason,
        displayReason: friendlyReason || backendReason || reasonCode || '—',
        instruction
    };
}

export function formatManualRollbackItemsForDisplay(items) {
    return normalizeManualRollbackItems(items).map((item) =>
        formatManualRollbackItemForDisplay(item)
    );
}

function isManualOnlyOutcome(resolved) {
    if (resolved.code === ROLLBACK_MANUAL_ROLLBACK_REQUIRED_CODE) {
        return true;
    }

    return (
        resolved.manualRollbackRequired === true &&
        resolved.partialSuccess !== true &&
        resolved.status === 'FAILED'
    );
}

function isPartialSuccessOutcome(resolved) {
    if (resolved.partialSuccess === true) {
        return true;
    }

    return (
        resolved.status === 'SUCCEEDED' &&
        resolved.manualRollbackRequired === true &&
        resolved.manualRollbackItems.length > 0
    );
}

export function parseRollbackResponse(raw) {
    if (raw == null) {
        return {
            kind: 'error',
            message: 'Rollback returned no response.',
            code: null,
            manualRollbackItems: []
        };
    }

    let parsed = raw;

    if (typeof raw === 'string') {
        try {
            parsed = JSON.parse(raw);
        } catch (error) {
            return {
                kind: 'unknownResult',
                message: raw,
                code: null,
                manualRollbackItems: []
            };
        }
    }

    if (typeof parsed !== 'object' || parsed == null) {
        return {
            kind: 'unknownResult',
            message: String(parsed),
            code: null,
            manualRollbackItems: []
        };
    }

    const resolved = resolvePayload(parsed);

    if (resolved.status === 'IN_PROGRESS') {
        return {
            kind: 'inProgress',
            message: resolved.message,
            code: resolved.code,
            operationId: resolved.operationId,
            manualRollbackItems: []
        };
    }

    if (isManualOnlyOutcome(resolved)) {
        return {
            kind: 'manualRequired',
            message:
                resolved.message ||
                'Manual rollback required. No automatic rollback was performed.',
            code: resolved.code || ROLLBACK_MANUAL_ROLLBACK_REQUIRED_CODE,
            manualRollbackRequired: true,
            partialSuccess: false,
            manualRollbackItems: resolved.manualRollbackItems
        };
    }

    if (isPartialSuccessOutcome(resolved)) {
        return {
            kind: 'partialSuccess',
            message:
                resolved.message ||
                'Supported metadata was rolled back automatically. Some items require manual action.',
            code: resolved.code,
            manualRollbackRequired: true,
            partialSuccess: true,
            manualRollbackItems: resolved.manualRollbackItems
        };
    }

    if (resolved.status === 'SUCCEEDED') {
        return {
            kind: 'success',
            message: resolved.message,
            code: resolved.code,
            manualRollbackItems: []
        };
    }

    if (resolved.status === 'UNKNOWN_RESULT') {
        return {
            kind: 'unknownResult',
            message:
                text(parsed.error) ||
                resolved.message ||
                'Rollback result could not be confirmed.',
            code: resolved.code,
            manualRollbackItems: []
        };
    }

    if (resolved.status === 'FAILED') {
        return {
            kind: 'failed',
            message: resolved.message,
            code: resolved.code,
            manualRollbackItems: []
        };
    }

    if (resolved.blocked === true) {
        return {
            kind: 'blocked',
            message: resolved.message,
            code: resolved.code,
            manualRollbackItems: []
        };
    }

    if (resolved.failed === true) {
        return {
            kind: 'failed',
            message: resolved.message,
            code: resolved.code,
            manualRollbackItems: []
        };
    }

    if (resolved.unknownResult === true) {
        return {
            kind: 'unknownResult',
            message: resolved.message,
            code: resolved.code,
            manualRollbackItems: []
        };
    }

    if (resolved.success === false || text(parsed.error)) {
        if (resolved.code === ROLLBACK_MANUAL_ROLLBACK_REQUIRED_CODE) {
            return {
                kind: 'manualRequired',
                message: resolved.message,
                code: resolved.code,
                manualRollbackRequired: true,
                partialSuccess: false,
                manualRollbackItems: resolved.manualRollbackItems
            };
        }

        return {
            kind: 'error',
            message: resolved.message,
            code: resolved.code,
            manualRollbackItems: []
        };
    }

    return {
        kind: 'unknownResult',
        message: resolved.message,
        code: resolved.code,
        manualRollbackItems: []
    };
}