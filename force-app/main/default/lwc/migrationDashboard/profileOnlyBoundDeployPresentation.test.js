import {
    BOUND_DEPLOY_CODES,
    PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH,
    bindingContextMatches,
    buildBoundDeployBindingContext,
    canRetainBoundDeployBinding,
    interpretBoundDeployResponse,
    shouldUseLegacyDeployPath
} from './profileOnlyBoundDeployPresentation';

describe('profileOnlyBoundDeployPresentation', () => {
    describe('buildBoundDeployBindingContext', () => {
        it('builds a stable explicit selection key', () => {
            const ctx = buildBoundDeployBindingContext({
                comparisonId: 'cmp1',
                destinationOrgId: '00Dxx',
                profileOnlyMinimalPackage: true,
                explicitPrimarySelectedMetadata: [
                    { metadataType: 'Profile', metadataName: 'Admin' },
                    { metadataType: 'Profile', metadataName: 'Standard' }
                ]
            });

            expect(ctx.explicitSelectionKey).toBe(
                'Profile:Admin|Profile:Standard'
            );
        });
    });

    describe('canRetainBoundDeployBinding', () => {
        it('retains when profile-only check-only succeeds with artifact', () => {
            expect(
                canRetainBoundDeployBinding({
                    profileOnlyMinimalPackage: true,
                    checkOnlySuccess: true,
                    boundDeployArtifact: { validationId: 'validation_abc' },
                    asyncValidationId: 'validation_abc',
                    validationExecutionPath:
                        PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH
                })
            ).toBe(true);
        });

        it('rejects when validationExecutionPath is not PROFILE_ONLY_MINIMAL', () => {
            expect(
                canRetainBoundDeployBinding({
                    profileOnlyMinimalPackage: true,
                    checkOnlySuccess: true,
                    boundDeployArtifact: { validationId: 'validation_abc' },
                    asyncValidationId: 'validation_abc',
                    validationExecutionPath: 'STANDARD'
                })
            ).toBe(false);
        });

        it('rejects backend profile-only blocked flag', () => {
            expect(
                canRetainBoundDeployBinding({
                    profileOnlyMinimalPackage: true,
                    checkOnlySuccess: true,
                    boundDeployArtifact: { validationId: 'validation_abc' },
                    asyncValidationId: 'validation_abc',
                    validationExecutionPath:
                        PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH,
                    profileOnlyMinimalPackageBlocked: true
                })
            ).toBe(false);
        });

        it('rejects failed check-only', () => {
            expect(
                canRetainBoundDeployBinding({
                    profileOnlyMinimalPackage: true,
                    checkOnlySuccess: false,
                    boundDeployArtifact: {},
                    asyncValidationId: 'validation_abc'
                })
            ).toBe(false);
        });

        it('rejects non validation_* ids', () => {
            expect(
                canRetainBoundDeployBinding({
                    profileOnlyMinimalPackage: true,
                    checkOnlySuccess: true,
                    boundDeployArtifact: {},
                    asyncValidationId: 'history_123',
                    validationExecutionPath:
                        PROFILE_ONLY_MINIMAL_VALIDATION_EXECUTION_PATH
                })
            ).toBe(false);
        });
    });

    describe('bindingContextMatches', () => {
        it('invalidates when comparison changes', () => {
            const stored = buildBoundDeployBindingContext({
                comparisonId: 'a',
                destinationOrgId: '00D',
                profileOnlyMinimalPackage: true,
                explicitPrimarySelectedMetadata: []
            });
            const current = buildBoundDeployBindingContext({
                comparisonId: 'b',
                destinationOrgId: '00D',
                profileOnlyMinimalPackage: true,
                explicitPrimarySelectedMetadata: []
            });

            expect(bindingContextMatches(stored, current)).toBe(false);
        });
    });

    describe('interpretBoundDeployResponse', () => {
        it('maps in-progress without legacy fallback', () => {
            const interpretation = interpretBoundDeployResponse({
                parsed: {
                    boundDeploy: {
                        code: BOUND_DEPLOY_CODES.IN_PROGRESS
                    }
                }
            });

            expect(interpretation.kind).toBe('BLOCKED_IN_PROGRESS');
            expect(interpretation.allowLegacyFallback).toBe(false);
        });

        it('maps success with deployment completion processing', () => {
            const interpretation = interpretBoundDeployResponse({
                parsed: {
                    success: true,
                    boundDeploy: { code: BOUND_DEPLOY_CODES.SUCCEEDED },
                    deploymentExecution: { success: true }
                }
            });

            expect(interpretation.kind).toBe('SUCCESS');
            expect(interpretation.processAsDeploymentCompletion).toBe(true);
        });

        it('maps transport errors as uncertain', () => {
            const interpretation = interpretBoundDeployResponse({
                transportError: true
            });

            expect(interpretation.kind).toBe('TRANSPORT_UNCERTAIN');
            expect(interpretation.allowLegacyFallback).toBe(false);
        });
    });

    describe('shouldUseLegacyDeployPath', () => {
        it('uses legacy when profile-only is off', () => {
            expect(
                shouldUseLegacyDeployPath({
                    profileOnlyMinimalPackage: false,
                    hasValidBoundBinding: false,
                    boundDeployLegacyBlocked: false
                })
            ).toBe(true);
        });

        it('uses legacy when profile-only is off even with stale bound block', () => {
            expect(
                shouldUseLegacyDeployPath({
                    profileOnlyMinimalPackage: false,
                    hasValidBoundBinding: false,
                    boundDeployLegacyBlocked: true
                })
            ).toBe(true);
        });

        it('never uses legacy when profile-only is on', () => {
            expect(
                shouldUseLegacyDeployPath({
                    profileOnlyMinimalPackage: true,
                    hasValidBoundBinding: true,
                    boundDeployLegacyBlocked: false
                })
            ).toBe(false);
        });

        it('never uses legacy when profile-only is on and bound deploy is blocked', () => {
            expect(
                shouldUseLegacyDeployPath({
                    profileOnlyMinimalPackage: true,
                    hasValidBoundBinding: false,
                    boundDeployLegacyBlocked: true
                })
            ).toBe(false);
        });
    });
});