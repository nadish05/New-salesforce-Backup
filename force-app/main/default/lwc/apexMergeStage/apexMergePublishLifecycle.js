import { METHOD_MERGE_MODE } from './apexMergeMethodInventory';

export const CLASS_ROW_STATUS = {
    RESOLVED: 'RESOLVED'
};

export const PUBLISH_STATE = {
    PUBLISHED: 'PUBLISHED'
};

export const SESSION_STATUS = {
    SEALED: 'SEALED'
};

export function collectMethodPublishMetadataNames(classRows) {
    if (!Array.isArray(classRows)) {
        return [];
    }

    return classRows
        .filter(
            (row) =>
                row?.status === CLASS_ROW_STATUS.RESOLVED &&
                row?.mergeMode === METHOD_MERGE_MODE
        )
        .map((row) => row.metadataName)
        .filter((name) => Boolean(String(name || '').trim()));
}

export function isPublishResponseConfirmed(parsed) {
    if (!parsed || parsed.success === false) {
        return false;
    }

    const sha = parsed.publishedCommitSha;

    return (
        parsed.publishState === PUBLISH_STATE.PUBLISHED &&
        typeof sha === 'string' &&
        sha.trim().length > 0
    );
}

export function isSessionPublishConfirmed(statusPayload) {
    if (!statusPayload || statusPayload.success === false) {
        return false;
    }

    const publish =
        statusPayload.publish ||
        (statusPayload.publishState
            ? {
                  publishState: statusPayload.publishState,
                  publishedCommitSha: statusPayload.publishedCommitSha
              }
            : null);

    if (!publish) {
        return false;
    }

    const sha = publish.publishedCommitSha;

    return (
        publish.publishState === PUBLISH_STATE.PUBLISHED &&
        typeof sha === 'string' &&
        sha.trim().length > 0
    );
}

export function sessionRequiresMethodPublish(classRows) {
    return collectMethodPublishMetadataNames(classRows).length > 0;
}

export function resolveMergeModeFromResponse(parsed, fallbackMode) {
    const fromResponse = parsed?.mergeMode;
    if (fromResponse === METHOD_MERGE_MODE || fromResponse === 'FULL') {
        return fromResponse;
    }
    return fallbackMode;
}

export function isPublishOutcomeAmbiguous(error, parsed) {
    if (isPublishResponseConfirmed(parsed)) {
        return false;
    }

    const message = String(
        error?.body?.message ||
            error?.message ||
            parsed?.error ||
            parsed?.code ||
            ''
    ).toLowerCase();

    if (
        message.includes('timeout') ||
        message.includes('uncommitted work') ||
        message.includes('network')
    ) {
        return true;
    }

    if (!parsed) {
        return true;
    }

    const parsedError = String(parsed?.error || '').toLowerCase();
    if (parsedError.includes('timeout')) {
        return true;
    }

    if (parsed.success === false && !parsed.code && !parsed.error) {
        return true;
    }

    return false;
}